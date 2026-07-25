import Foundation

// MARK: - 카탈로그 파일 IO

enum LibraryCatalogFile {

    static func defaultURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support", isDirectory: true
            )
        return base
            .appendingPathComponent("negaflow", isDirectory: true)
            .appendingPathComponent("library.sqlite")
    }

    static func backupURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension(
            LibraryCatalogSQLiteStore.isSQLiteURL(url) ? "backup.sqlite" : "backup.json"
        )
    }

    static func load(from url: URL) -> LibraryCatalog? {
        switch read(from: url) {
        case let .loaded(catalog, _):
            return catalog
        case .unsupportedVersion:
            // 미래 버전 primary를 과거 backup으로 조용히 대체하지 않는다.
            return nil
        case .unsupportedStorageVersion:
            return nil
        case .missing, .unreadable, .invalid:
            return loadPrimary(from: backupURL(for: url))
        }
    }

    static func loadPrimary(from url: URL) -> LibraryCatalog? {
        guard case let .loaded(catalog, _) = read(from: url) else { return nil }
        return catalog
    }

    static func decode(_ data: Data) -> LibraryCatalog? {
        guard case let .loaded(catalog, _) = decodeResult(data) else { return nil }
        return catalog
    }

    static func read(
        from url: URL,
        fileManager: FileManager = .default
    ) -> LibraryCatalogReadResult {
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        if LibraryCatalogSQLiteStore.isSQLiteURL(url) {
            switch LibraryCatalogSQLiteStore.read(from: url) {
            case let .loaded(catalog):
                return .loaded(catalog: catalog, sourceVersion: catalog.version)
            case let .unsupportedStorageVersion(version):
                return .unsupportedStorageVersion(version)
            case .invalid:
                return .invalid
            }
        }
        do {
            return decodeResult(try Data(contentsOf: url))
        } catch {
            return .unreadable
        }
    }

    static func decodeResult(_ data: Data) -> LibraryCatalogReadResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let probe = try? decoder.decode(LibraryCatalogVersionProbe.self, from: data) else {
            return .invalid
        }

        switch probe.version {
        case 1:
            guard let legacy = try? decoder.decode(LibraryCatalogV1.self, from: data) else {
                return .invalid
            }
            return .loaded(catalog: migrateV1ToV6(legacy), sourceVersion: 1)
        case 2:
            guard let legacy = try? decoder.decode(LibraryCatalogV2.self, from: data),
                  legacy.minimumReaderVersion == 2 else {
                return .invalid
            }
            return .loaded(catalog: migrateV2ToV6(legacy), sourceVersion: 2)
        case 3:
            guard let legacy = try? decoder.decode(LibraryCatalogV3.self, from: data),
                  legacy.minimumReaderVersion == 3 else {
                return .invalid
            }
            return .loaded(catalog: migrateV3ToV6(legacy), sourceVersion: 3)
        case 4:
            guard let legacy = try? decoder.decode(LibraryCatalogV4.self, from: data),
                  legacy.minimumReaderVersion == 4 else {
                return .invalid
            }
            return .loaded(catalog: migrateV4ToV6(legacy), sourceVersion: 4)
        case 5:
            guard let legacy = try? decoder.decode(LibraryCatalogV5.self, from: data),
                  legacy.minimumReaderVersion == 5 else {
                return .invalid
            }
            return .loaded(catalog: migrateV5ToV6(legacy), sourceVersion: 5)
        case LibraryCatalog.currentVersion:
            guard let catalog = try? decoder.decode(LibraryCatalog.self, from: data),
                  catalog.minimumReaderVersion == LibraryCatalog.oldestReaderVersion else {
                return .invalid
            }
            return .loaded(catalog: catalog, sourceVersion: catalog.version)
        default:
            return .unsupportedVersion(probe.version)
        }
    }


}
