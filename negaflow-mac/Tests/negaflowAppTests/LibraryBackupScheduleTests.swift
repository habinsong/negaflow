import XCTest
@testable import negaflowApp

@MainActor
final class LibraryBackupScheduleTests: XCTestCase {
    func testDailyAndWeeklyDueWindowsPersistVerification() throws {
        let defaults = try makeDefaults()
        let store = LibraryBackupScheduleStore(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_000_000)

        store.schedule = .daily
        XCTAssertTrue(store.isDue(at: start))
        store.recordAttempt(at: start)
        XCTAssertFalse(store.isDue(at: start.addingTimeInterval(23 * 60 * 60)))
        XCTAssertTrue(store.isDue(at: start.addingTimeInterval(24 * 60 * 60)))

        store.schedule = .weekly
        XCTAssertFalse(store.isDue(at: start.addingTimeInterval(6 * 24 * 60 * 60)))
        XCTAssertTrue(store.isDue(at: start.addingTimeInterval(7 * 24 * 60 * 60)))
        let drill = LibraryBackupRestoreDrillResult(
            generationID: "backup-test",
            verifiedAt: start,
            succeeded: true
        )
        store.recordSuccess(drill, at: start)

        let restored = LibraryBackupScheduleStore(defaults: defaults)
        XCTAssertEqual(restored.schedule, .weekly)
        XCTAssertEqual(restored.lastAttemptAt, start)
        XCTAssertEqual(restored.lastSuccessAt, start)
        XCTAssertEqual(restored.lastRestoreDrill, drill)
    }

    func testDailyScheduleCreatesAndVerifiesOnlyWhenDue() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryBackupScheduleStore(defaults: try makeDefaults())
        store.schedule = .daily
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let model = AppModel(
            backupScheduleStore: store,
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: backups
        )
        model.libraryPersistenceEnabled = true
        let start = Date(timeIntervalSince1970: 2_000_000)

        await model.runScheduledBackupIfDue(at: start)
        XCTAssertEqual(try LibraryBackupStore.generations(in: backups).count, 1)
        XCTAssertEqual(store.lastRestoreDrill?.succeeded, true)
        await model.runScheduledBackupIfDue(at: start.addingTimeInterval(60 * 60))
        XCTAssertEqual(try LibraryBackupStore.generations(in: backups).count, 1)
        await model.runScheduledBackupIfDue(at: start.addingTimeInterval(24 * 60 * 60))
        XCTAssertEqual(try LibraryBackupStore.generations(in: backups).count, 2)
    }

    func testQuitRepliesWithoutWaitingForBackup() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryBackupScheduleStore(defaults: try makeDefaults())
        store.schedule = .automatic
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let model = AppModel(
            backupScheduleStore: store,
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: backups
        )
        model.libraryPersistenceEnabled = true
        defer { model.libraryPersistenceEnabled = false }
        var replies: [Bool] = []

        let decision = model.beginApplicationTermination(
            scheduleCommit: { _, _, _, _, completion in completion(.success(())) },
            completion: { replies.append($0) }
        )

        // 커밋 승인 즉시 답한다 — 백업을 만들거나 기다리지 않는다.
        XCTAssertEqual(decision, .terminateLater)
        XCTAssertEqual(replies, [true])
        XCTAssertNil(store.lastAttemptAt)
        XCTAssertNil(model.sessionBackupTask)
        XCTAssertEqual(try LibraryBackupStore.generations(in: backups).count, 0)
    }

    func testSavedChangesScheduleAutomaticBackupAtMostHourly() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryBackupScheduleStore(defaults: try makeDefaults())
        store.schedule = .automatic
        let model = AppModel(
            backupScheduleStore: store,
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        model.libraryPersistenceEnabled = true
        defer {
            model.libraryPersistenceEnabled = false
            model.sessionBackupTask?.cancel()
        }

        XCTAssertTrue(model.saveLibrary(synchronous: true))
        XCTAssertNotNil(model.sessionBackupTask)

        model.sessionBackupTask?.cancel()
        model.sessionBackupTask = nil
        let now = Date()
        store.recordAttempt(at: now.addingTimeInterval(-10 * 60))
        model.scheduleSessionBackupAfterSave(now: now)
        XCTAssertNil(model.sessionBackupTask)

        store.schedule = .manual
        model.scheduleSessionBackupAfterSave(now: now.addingTimeInterval(2 * 60 * 60))
        XCTAssertNil(model.sessionBackupTask)
    }

    func testAutomaticBackupFreezesMemoryWithoutTouchingLiveCatalog() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryBackupScheduleStore(defaults: try makeDefaults())
        store.schedule = .automatic
        let catalogURL = root.appendingPathComponent("library.sqlite")
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let model = AppModel(
            backupScheduleStore: store,
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: backups
        )
        model.libraryPersistenceEnabled = true
        defer {
            model.libraryPersistenceEnabled = false
            model.sessionBackupTask?.cancel()
        }
        model.transitionLibraryLifecycle(to: .ready)
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        model.sessionBackupTask?.cancel()
        model.sessionBackupTask = nil

        // 저장할 변경이 남아 있으면 뜨지 않는다.
        model.markLibraryCatalogDirty()
        let refused = await model.createSessionBackup(at: Date())
        XCTAssertFalse(refused)
        XCTAssertEqual(try LibraryBackupStore.generations(in: backups).count, 0)
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        model.sessionBackupTask?.cancel()
        model.sessionBackupTask = nil
        let liveSaved = try Data(contentsOf: catalogURL)
        let liveSavedAt = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: catalogURL.path)[.modificationDate] as? Date
        )

        let created = await model.createSessionBackup(at: Date())

        XCTAssertTrue(created)
        XCTAssertFalse(model.isLibraryMaintenanceInProgress)
        XCTAssertEqual(store.lastRestoreDrill?.succeeded, true)
        XCTAssertEqual(try LibraryBackupStore.generations(in: backups).count, 1)
        // 백업은 메모리에서 만든다. 살아 있는 카탈로그 파일은 그대로다.
        XCTAssertEqual(try Data(contentsOf: catalogURL), liveSaved)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: catalogURL.path)[.modificationDate] as? Date,
            liveSavedAt
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "LibraryBackupScheduleTests-\(UUID().uuidString)"))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-backup-schedule-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
