import Foundation
import CryptoKit
import SQLite3
import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class LibraryCatalogSQLiteStoreTests: XCTestCase {
    func testSQLiteRoundTripAndIncrementalReplacementPreserveCanonicalCatalog() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let firstFrame = makeFrame(index: 1)
        let secondFrame = makeFrame(index: 2)
        let first = LibraryCatalog(
            folders: ["/library/a"],
            frames: [LibraryFrameRecord(frame: firstFrame)]
        )

        XCTAssertTrue(LibraryCatalogSQLiteStore.write(first, to: url))
        XCTAssertTrue(LibraryCatalogSQLiteStore.isValidRecoverySource(at: url))
        guard case let .loaded(firstRead) = LibraryCatalogSQLiteStore.read(from: url) else {
            return XCTFail("SQLite catalog should load")
        }
        XCTAssertEqual(
            LibraryCatalogFile.canonicalData(firstRead),
            LibraryCatalogFile.canonicalData(first)
        )

        let second = LibraryCatalog(
            folders: ["/library/b", "/library/c"],
            frames: [LibraryFrameRecord(frame: secondFrame)]
        )
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(second, to: url))
        guard case let .loaded(secondRead) = LibraryCatalogSQLiteStore.read(from: url) else {
            return XCTFail("updated SQLite catalog should load")
        }
        XCTAssertEqual(
            LibraryCatalogFile.canonicalData(secondRead),
            LibraryCatalogFile.canonicalData(second)
        )
        XCTAssertFalse(secondRead.frames.contains { $0.id == firstFrame.id })
    }

    func testSQLiteWriteTouchesOnlyChangedFrameWhenIdentityAndOrderAreStable() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let frames = (1...3).map { LibraryFrameRecord(frame: makeFrame(index: $0)) }
        let original = LibraryCatalog(frames: frames)

        XCTAssertTrue(LibraryCatalogSQLiteStore.write(original, to: url))
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let database else { return XCTFail("SQLite catalog should open") }
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, """
            CREATE TABLE write_audit(action TEXT NOT NULL, id TEXT NOT NULL);
            CREATE TRIGGER audit_frame_insert AFTER INSERT ON frames BEGIN
              INSERT INTO write_audit(action, id) VALUES('insert', NEW.id);
            END;
            CREATE TRIGGER audit_frame_update AFTER UPDATE ON frames BEGIN
              INSERT INTO write_audit(action, id) VALUES('update', NEW.id);
            END;
            CREATE TRIGGER audit_frame_delete AFTER DELETE ON frames BEGIN
              INSERT INTO write_audit(action, id) VALUES('delete', OLD.id);
            END;
            """, nil, nil, nil), SQLITE_OK)
        guard case .loaded = LibraryCatalogSQLiteStore.read(from: url) else {
            return XCTFail("audited SQLite catalog should load")
        }

        XCTAssertTrue(LibraryCatalogSQLiteStore.write(original, to: url))
        XCTAssertEqual(try auditRows(database), [])

        var changed = original
        changed.frames[1].rating = 4
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(changed, to: url))
        XCTAssertEqual(try auditRows(database), ["update:\(changed.frames[1].id.uuidString)"])
        guard case let .loaded(persisted) = LibraryCatalogSQLiteStore.read(from: url) else {
            return XCTFail("updated SQLite catalog should load")
        }
        XCTAssertEqual(persisted, changed)
    }

    func testExternalSQLiteChangeInvalidatesIncrementalWriteCache() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let catalog = LibraryCatalog(
            frames: (1...3).map { LibraryFrameRecord(frame: makeFrame(index: $0)) }
        )
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(catalog, to: url))

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(
            database,
            "DELETE FROM frames WHERE id='\(catalog.frames[1].id.uuidString)'",
            nil,
            nil,
            nil
        ), SQLITE_OK)
        sqlite3_close(database)

        XCTAssertTrue(LibraryCatalogSQLiteStore.write(catalog, to: url))
        guard case let .loaded(persisted) = LibraryCatalogSQLiteStore.read(from: url) else {
            return XCTFail("repaired SQLite catalog should load")
        }
        XCTAssertEqual(persisted, catalog)
    }

    func testParallelSQLiteDecodePreservesOrderAndFailsClosedOnCorruptPayload() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let catalog = LibraryCatalog(
            frames: (1...1_024).map { LibraryFrameRecord(frame: makeFrame(index: $0)) }
        )
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(catalog, to: url))
        guard case let .loaded(persisted) = LibraryCatalogSQLiteStore.read(from: url) else {
            return XCTFail("parallel SQLite catalog should load")
        }
        XCTAssertEqual(persisted, catalog)

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(
            database,
            "UPDATE frames SET payload=x'00' WHERE position=511",
            nil,
            nil,
            nil
        ), SQLITE_OK)
        sqlite3_close(database)
        guard case .invalid = LibraryCatalogSQLiteStore.read(from: url) else {
            return XCTFail("one corrupt payload must fail the whole catalog closed")
        }
    }

    func testIncrementalVerifierAcceptsChangedRowAndRejectsCorruptReadback() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let original = LibraryCatalog(
            frames: (1...3).map { LibraryFrameRecord(frame: makeFrame(index: $0)) }
        )
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(original, to: url))
        var changed = original
        changed.frames[1].rating = 5
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(changed, to: url))
        XCTAssertTrue(LibraryCatalogSQLiteIncrementalVerifier.verify(
            changed,
            from: original,
            at: url
        ))

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(
            database,
            "UPDATE frames SET payload=x'00' WHERE position=1",
            nil,
            nil,
            nil
        ), SQLITE_OK)
        sqlite3_close(database)
        XCTAssertFalse(LibraryCatalogSQLiteIncrementalVerifier.verify(
            changed,
            from: original,
            at: url
        ))
    }

    func testUnknownSQLiteStorageVersionFailsClosed() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(LibraryCatalog(), to: url))
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "PRAGMA user_version=99", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        XCTAssertFalse(LibraryCatalogSQLiteStore.isValidRecoverySource(at: url))

        guard case let .unsupportedStorageVersion(version) = LibraryCatalogFile.read(from: url) else {
            return XCTFail("future storage schema must fail closed")
        }
        XCTAssertEqual(version, 99)
        guard case let .blocked(reason) = LibraryCatalogFile.prepareForUse(
            at: url,
            defectDirectory: root.appendingPathComponent("Defects"),
            backupDirectory: root.appendingPathComponent("Backups")
        ) else {
            return XCTFail("future storage schema must block open")
        }
        XCTAssertEqual(reason, .unsupportedStorageVersion(99))
    }

    func testSQLiteWritePreservesPreviousValidPrimaryAsRecoveryBackup() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let first = LibraryCatalog(folders: ["/first"])
        let second = LibraryCatalog(folders: ["/second"])

        XCTAssertTrue(LibraryCatalogFile.writeCatalogSync(first, to: url))
        XCTAssertTrue(LibraryCatalogFile.writeCatalogSync(second, to: url))

        XCTAssertEqual(LibraryCatalogFile.loadPrimary(from: url)?.folders, ["/second"])
        XCTAssertEqual(
            LibraryCatalogFile.loadPrimary(from: LibraryCatalogFile.backupURL(for: url))?.folders,
            ["/first"]
        )
    }

    func testLegacyJSONMigratesOnceAndRetiresOldPrimary() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonURL = root.appendingPathComponent("library.json")
        let sqliteURL = root.appendingPathComponent("library.sqlite")
        let defects = root.appendingPathComponent("Defects")
        let backups = root.appendingPathComponent("Backups")
        let catalog = LibraryCatalog(
            folders: ["/legacy"],
            frames: [LibraryFrameRecord(frame: makeFrame(index: 1))]
        )
        try XCTUnwrap(LibraryCatalogFile.encode(catalog)).write(to: jsonURL, options: .atomic)

        guard case let .loaded(migrated, recovered, _, _) = LibraryCatalogFile.prepareForUse(
            at: sqliteURL,
            defectDirectory: defects,
            backupDirectory: backups
        ) else {
            return XCTFail("legacy JSON should migrate")
        }
        XCTAssertFalse(recovered)
        XCTAssertEqual(
            LibraryCatalogFile.canonicalData(migrated),
            LibraryCatalogFile.canonicalData(catalog)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sqliteURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path))
        // 마이그레이션이 끝나면 마커는 사라져야 한다. 남겨 두면 나중에 sqlite 가 없어졌을 때
        // "중단된 마이그레이션" 으로 오인돼 라이브러리가 영구히 열리지 않는다.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("library.sqlite-migration.json").path
        ))
        XCTAssertEqual(try LibraryBackupStore.generations(in: backups).count, 1)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.path)
                .filter { $0.hasPrefix("library.pre-sqlite-") && $0.hasSuffix(".json") }.count,
            1
        )

        guard case let .loaded(reopened, _, _, _) = LibraryCatalogFile.prepareForUse(
            at: sqliteURL,
            defectDirectory: defects,
            backupDirectory: backups
        ) else {
            return XCTFail("migrated SQLite should reopen")
        }
        XCTAssertEqual(
            LibraryCatalogFile.canonicalData(reopened),
            LibraryCatalogFile.canonicalData(catalog)
        )
    }

    func testInterruptedLegacyMigrationResumesFromVerifiedMarkerAndTemporaryDatabase() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonURL = root.appendingPathComponent("library.json")
        let sqliteURL = root.appendingPathComponent("library.sqlite")
        let temporaryURL = root.appendingPathComponent(".library-migrating-fixture.sqlite")
        let catalog = LibraryCatalog(folders: ["/interrupted"])
        let sourceData = try XCTUnwrap(LibraryCatalogFile.encode(catalog))
        try sourceData.write(to: jsonURL, options: .atomic)
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(catalog, to: temporaryURL))
        let digest = SHA256.hash(data: sourceData)
            .map { String(format: "%02x", $0) }
            .joined()
        let preservedName = "library.pre-sqlite-\(digest.prefix(12)).json"
        let marker: [String: Any] = [
            "version": 1,
            "sourceSHA256": digest,
            "sourceCatalogVersion": LibraryCatalog.currentVersion,
            "sqliteStorageVersion": Int(LibraryCatalogSQLiteStore.storageSchemaVersion),
            "temporaryDatabaseFileName": temporaryURL.lastPathComponent,
            "preservedLegacyFileName": preservedName,
            "createdAt": "2026-07-12T00:00:00Z",
        ]
        try JSONSerialization.data(withJSONObject: marker).write(
            to: root.appendingPathComponent("library.sqlite-migration.json"),
            options: .atomic
        )

        guard case let .loaded(recovered, recoveredFromBackup, _, _) =
                LibraryCatalogFile.prepareForUse(
                    at: sqliteURL,
                    defectDirectory: root.appendingPathComponent("Defects"),
                    backupDirectory: root.appendingPathComponent("Backups")
                ) else {
            return XCTFail("verified interrupted migration should resume")
        }
        XCTAssertFalse(recoveredFromBackup)
        XCTAssertEqual(recovered.folders, ["/interrupted"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sqliteURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(preservedName).path
        ))
    }

    func testInterruptedMigrationWithMismatchedTemporaryDatabaseFailsClosed() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let jsonURL = root.appendingPathComponent("library.json")
        let sqliteURL = root.appendingPathComponent("library.sqlite")
        let temporaryURL = root.appendingPathComponent(".library-migrating-fixture.sqlite")
        let sourceData = try XCTUnwrap(
            LibraryCatalogFile.encode(LibraryCatalog(folders: ["/source"]))
        )
        try sourceData.write(to: jsonURL, options: .atomic)
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(
            LibraryCatalog(folders: ["/different"]),
            to: temporaryURL
        ))
        let digest = SHA256.hash(data: sourceData)
            .map { String(format: "%02x", $0) }
            .joined()
        let marker: [String: Any] = [
            "version": 1,
            "sourceSHA256": digest,
            "sourceCatalogVersion": LibraryCatalog.currentVersion,
            "sqliteStorageVersion": Int(LibraryCatalogSQLiteStore.storageSchemaVersion),
            "temporaryDatabaseFileName": temporaryURL.lastPathComponent,
            "preservedLegacyFileName": "library.pre-sqlite-\(digest.prefix(12)).json",
            "createdAt": "2026-07-12T00:00:00Z",
        ]
        try JSONSerialization.data(withJSONObject: marker).write(
            to: root.appendingPathComponent("library.sqlite-migration.json"),
            options: .atomic
        )

        guard case let .blocked(reason) = LibraryCatalogFile.prepareForUse(
            at: sqliteURL,
            defectDirectory: root.appendingPathComponent("Defects"),
            backupDirectory: root.appendingPathComponent("Backups")
        ) else {
            return XCTFail("mismatched interrupted migration must fail closed")
        }
        XCTAssertEqual(reason, .writeFailed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sqliteURL.path))
    }

    func testJSONBackupSnapshotRestoresIntoSQLitePrimary() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sqliteURL = root.appendingPathComponent("library.sqlite")
        let defects = root.appendingPathComponent("Defects")
        let backups = root.appendingPathComponent("Backups")
        let catalog = LibraryCatalog(folders: ["/restorable"])
        let data = try XCTUnwrap(LibraryCatalogFile.encode(catalog))
        XCTAssertTrue(LibraryCatalogFile.writeSync(data, to: sqliteURL))
        _ = try LibraryBackupStore.createSnapshot(
            catalogURL: sqliteURL,
            defectDirectory: defects,
            backupDirectory: backups
        )
        try Data("corrupt".utf8).write(to: sqliteURL, options: .atomic)

        let restored = try XCTUnwrap(LibraryBackupStore.restoreLatest(
            catalogURL: sqliteURL,
            defectDirectory: defects,
            backupDirectory: backups
        ))

        XCTAssertEqual(restored.folders, ["/restorable"])
        XCTAssertEqual(LibraryCatalogFile.loadPrimary(from: sqliteURL)?.folders, ["/restorable"])
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-sqlite-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func auditRows(_ database: OpaquePointer) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT action, id FROM write_audit ORDER BY rowid",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_finalize(statement) }
        var rows: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let action = sqlite3_column_text(statement, 0),
                  let id = sqlite3_column_text(statement, 1) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            rows.append("\(String(cString: action)):\(String(cString: id))")
        }
        return rows
    }

    private func makeFrame(index: Int) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: URL(fileURLWithPath: "/source/frame-\(index).tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourcePixelWidth: 6_000,
            sourcePixelHeight: 4_000,
            sourceBitDepth: 16,
            scannedAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index))
        )
    }
}
