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

    func testQuitScheduleWaitsForVerifiedBackupBeforeReplying() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryBackupScheduleStore(defaults: try makeDefaults())
        store.schedule = .onTermination
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let model = AppModel(
            backupScheduleStore: store,
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: backups
        )
        model.libraryPersistenceEnabled = true
        let replied = expectation(description: "termination reply")
        var reply: Bool?

        let decision = model.beginApplicationTermination(
            scheduleCommit: { _, _, _, _, completion in completion(.success(())) },
            completion: {
                reply = $0
                replied.fulfill()
            }
        )

        XCTAssertEqual(decision, .terminateLater)
        await fulfillment(of: [replied], timeout: 3)
        XCTAssertEqual(reply, true)
        XCTAssertEqual(store.lastRestoreDrill?.succeeded, true)
        XCTAssertEqual(try LibraryBackupStore.generations(in: backups).count, 1)
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
