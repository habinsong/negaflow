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
            // 마커는 여기서 수명이 끝난다. 남겨 두면 나중에 sqlite 가 사라졌을 때 "중단된
            // 마이그레이션" 으로 오인돼 라이브러리가 영구히 열리지 않는다.
            try? fileManager.removeItem(at: markerURL)
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

        // 옮기던 임시 DB 가 없으면 중단된 마이그레이션이 아니다 — 예전에 끝난 마이그레이션의
        // 마커만 남은 것이다. 마커를 걷어내고 일반 경로(백업 복구/새 라이브러리)에 맡긴다.
        guard fileManager.fileExists(atPath: temporaryURL.path) else {
            try? fileManager.removeItem(at: markerURL)
            return nil
        }

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
            try? fileManager.removeItem(at: markerURL)
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

    /// sqlite 로 옮기면서 옆에 남겨 둔 예전 JSON 원본들. 최근 것부터 돌려준다.
    static func preservedLegacyURLs(
        besides sqliteURL: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        let parent = sqliteURL.deletingLastPathComponent()
        guard let contents = try? fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter {
                $0.lastPathComponent.hasPrefix("library.pre-sqlite-")
                    && $0.pathExtension == "json"
            }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.lastPathComponent < rhs.lastPathComponent
                }
                return lhsDate > rhsDate
            }
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
