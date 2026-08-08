import CryptoKit
import Foundation

enum LibraryCatalogSQLiteMigration {
    private struct Marker: Codable {
        static let currentVersion = 1
        let version: Int
        let sourceSHA256: String
        let sourceCatalogVersion: Int
        let sqliteStorageVersion: Int32
        let temporaryDatabaseFileName: String
        let preservedLegacyFileName: String
        let createdAt: Date
    }

    static func migrateLegacyJSONIfNeeded(
        to sqliteURL: URL,
        defectDirectory: URL,
        backupDirectory: URL,
        fileManager: FileManager
    ) -> LibraryCatalogOpenResult? {
        guard LibraryCatalogSQLiteStore.isSQLiteURL(sqliteURL),
              !fileManager.fileExists(atPath: sqliteURL.path) else { return nil }

        if let recovered = recoverInterruptedMigration(
            to: sqliteURL,
            fileManager: fileManager
        ) {
            return recovered
        }

        let legacyURL = legacyJSONURL(for: sqliteURL)
        guard fileManager.fileExists(atPath: legacyURL.path) else { return nil }
        let sourceData: Data
        do {
            sourceData = try Data(contentsOf: legacyURL)
        } catch {
            return .blocked(.unreadable)
        }
        let sourceVersion: Int
        let catalog: LibraryCatalog
        switch LibraryCatalogFile.decodeResult(sourceData) {
        case let .loaded(value, version):
            catalog = value
            sourceVersion = version
        case let .unsupportedVersion(version):
            return .blocked(.unsupportedVersion(version))
        case let .unsupportedStorageVersion(version):
            return .blocked(.unsupportedStorageVersion(version))
        case .missing, .unreadable, .invalid:
            return .blocked(.corrupt)
        }
        guard LibraryCatalogHealthInspector.inspect(
            catalog,
            defectDirectory: defectDirectory,
            fileManager: fileManager
        ).canOpenSafely else {
            return .blocked(.missingAuthoritativeData)
        }

        do {
            _ = try LibraryBackupStore.createSnapshot(
                catalogURL: legacyURL,
                defectDirectory: defectDirectory,
                backupDirectory: backupDirectory,
                fileManager: fileManager
            )
        } catch {
            return .blocked(.writeFailed)
        }

        let sourceSHA256 = sha256(sourceData)
        let temporaryURL = sqliteURL.deletingLastPathComponent().appendingPathComponent(
            ".library-migrating-\(UUID().uuidString).sqlite"
        )
        let preservedURL = sqliteURL.deletingLastPathComponent().appendingPathComponent(
            "library.pre-sqlite-\(sourceSHA256.prefix(12)).json"
        )
        let marker = Marker(
            version: Marker.currentVersion,
            sourceSHA256: sourceSHA256,
            sourceCatalogVersion: sourceVersion,
            sqliteStorageVersion: LibraryCatalogSQLiteStore.storageSchemaVersion,
            temporaryDatabaseFileName: temporaryURL.lastPathComponent,
            preservedLegacyFileName: preservedURL.lastPathComponent,
            createdAt: Date()
        )
        let markerURL = self.markerURL(for: sqliteURL)

        guard LibraryCatalogSQLiteStore.write(catalog, to: temporaryURL),
              case let .loaded(readback) = LibraryCatalogSQLiteStore.read(from: temporaryURL),
              LibraryCatalogFile.canonicalData(readback)
                == LibraryCatalogFile.canonicalData(catalog),
              writeMarker(marker, to: markerURL) else {
            try? fileManager.removeItem(at: temporaryURL)
            try? fileManager.removeItem(at: markerURL)
            return .blocked(.writeFailed)
        }

        do {
            if fileManager.fileExists(atPath: preservedURL.path) {
                guard (try? Data(contentsOf: preservedURL)) == sourceData else {
                    throw CocoaError(.fileWriteFileExists)
                }
                try fileManager.removeItem(at: legacyURL)
            } else {
                try fileManager.moveItem(at: legacyURL, to: preservedURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: sqliteURL)
        } catch {
            if !fileManager.fileExists(atPath: legacyURL.path),
               fileManager.fileExists(atPath: preservedURL.path) {
                try? fileManager.copyItem(at: preservedURL, to: legacyURL)
            }
            try? fileManager.removeItem(at: temporaryURL)
            try? fileManager.removeItem(at: sqliteURL)
            try? fileManager.removeItem(at: markerURL)
            return .blocked(.writeFailed)
        }

        return .loaded(
            catalog: catalog,
            recoveredFromBackup: false,
            migratedFromVersion: sourceVersion < LibraryCatalog.currentVersion
                ? sourceVersion
                : nil
        )
    }

    private static func recoverInterruptedMigration(
        to sqliteURL: URL,
        fileManager: FileManager
    ) -> LibraryCatalogOpenResult? {
        let markerURL = markerURL(for: sqliteURL)
        guard let marker = readMarker(from: markerURL),
              marker.version == Marker.currentVersion,
              marker.sqliteStorageVersion == LibraryCatalogSQLiteStore.storageSchemaVersion else {
            return nil
        }
        let parent = sqliteURL.deletingLastPathComponent()
        let temporaryURL = parent.appendingPathComponent(marker.temporaryDatabaseFileName)
        let preservedURL = parent.appendingPathComponent(marker.preservedLegacyFileName)
        let legacyURL = legacyJSONURL(for: sqliteURL)
        let sourceURL: URL
        if fileManager.fileExists(atPath: preservedURL.path) {
            sourceURL = preservedURL
        } else if fileManager.fileExists(atPath: legacyURL.path) {
            sourceURL = legacyURL
        } else {
            return .blocked(.writeFailed)
        }
        guard let sourceData = try? Data(contentsOf: sourceURL),
              sha256(sourceData) == marker.sourceSHA256,
              case let .loaded(sourceCatalog, sourceVersion)
                = LibraryCatalogFile.decodeResult(sourceData),
              sourceVersion == marker.sourceCatalogVersion,
              case let .loaded(sqliteCatalog)
                = LibraryCatalogSQLiteStore.read(from: temporaryURL),
              LibraryCatalogFile.canonicalData(sourceCatalog)
                == LibraryCatalogFile.canonicalData(sqliteCatalog) else {
            return .blocked(.writeFailed)
        }
        do {
            if sourceURL == legacyURL {
                try fileManager.moveItem(at: legacyURL, to: preservedURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: sqliteURL)
        } catch {
            return .blocked(.writeFailed)
        }
        return .loaded(
            catalog: sqliteCatalog,
            recoveredFromBackup: false,
            migratedFromVersion: sourceVersion < LibraryCatalog.currentVersion
                ? sourceVersion
                : nil
        )
    }

    private static func legacyJSONURL(for sqliteURL: URL) -> URL {
        sqliteURL.deletingLastPathComponent().appendingPathComponent("library.json")
    }

    private static func markerURL(for sqliteURL: URL) -> URL {
        sqliteURL.deletingLastPathComponent().appendingPathComponent(
            "library.sqlite-migration.json"
        )
    }

    private static func writeMarker(_ marker: Marker, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(marker).write(to: url, options: .atomic)
            return readMarker(from: url)?.sourceSHA256 == marker.sourceSHA256
        } catch {
            return false
        }
    }

    private static func readMarker(from url: URL) -> Marker? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Marker.self, from: data)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
