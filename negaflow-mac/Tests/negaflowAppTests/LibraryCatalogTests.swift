import XCTest
import Chromabase
import ScannerKit
import SQLite3
@testable import negaflowApp

@MainActor
final class LibraryCatalogTests: XCTestCase {
    func testCatalogSnapshotUpdatesOnlyDirtyFrameRecordsWithoutReturningStaleState() {
        let model = AppModel()
        defer { model.sourceAvailabilityRefreshTask?.cancel() }
        let first = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/cache-first.tiff"),
            filmType: .colorNegative
        )
        let second = ScanFrame(
            scanIndex: 2,
            rawScanURL: URL(fileURLWithPath: "/offline/cache-second.tiff"),
            filmType: .colorNegative
        )
        model.frames = [first, second]

        let initial = model.makeLibraryCatalogValue(
            frames: model.frames,
            rolls: [],
            activeRollID: nil,
            scanSessions: [],
            scanRollAssignments: []
        )
        XCTAssertEqual(initial.frames.count, 2)
        XCTAssertTrue(model.dirtyLibraryFrameRecordIDs.isEmpty)

        first.customDisplayName = "updated"
        let updated = model.makeLibraryCatalogValue(
            frames: model.frames,
            rolls: [],
            activeRollID: nil,
            scanSessions: [],
            scanRollAssignments: []
        )
        XCTAssertEqual(updated.frames.first { $0.id == first.id }?.customDisplayName, "updated")
        XCTAssertNil(updated.frames.first { $0.id == second.id }?.customDisplayName)

        model.frames = [first]
        _ = model.makeLibraryCatalogValue(
            frames: model.frames,
            rolls: [],
            activeRollID: nil,
            scanSessions: [],
            scanRollAssignments: []
        )
        XCTAssertEqual(Set(model.libraryFrameRecordCache.keys), Set([first.id]))
    }

    func testCatalogSnapshotSingleFrameEditPerformanceWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_CATALOG_SNAPSHOT_PERF"] == "1" else {
            throw XCTSkip("Set NEGAFLOW_CATALOG_SNAPSHOT_PERF=1 to run the catalog snapshot benchmark.")
        }
        let frameCount = 50_000
        let model = AppModel()
        defer { model.sourceAvailabilityRefreshTask?.cancel() }
        let frames = (0..<frameCount).map { index in
            ScanFrame(
                scanIndex: index + 1,
                rawScanURL: URL(fileURLWithPath: "/offline/catalog-cache-shared.tiff"),
                filmType: .colorNegative
            )
        }
        model.frames = frames
        model.sourceAvailabilityRefreshTask?.cancel()

        let firstStarted = ContinuousClock.now
        _ = model.makeLibraryCatalogValue(
            frames: frames,
            rolls: [],
            activeRollID: nil,
            scanSessions: [],
            scanRollAssignments: []
        )
        let firstMilliseconds = Self.milliseconds(firstStarted.duration(to: .now))

        var samples: [Double] = []
        for iteration in 0..<5 {
            frames[frameCount / 2].customDisplayName = "edited-\(iteration)"
            let started = ContinuousClock.now
            let catalog = model.makeLibraryCatalogValue(
                frames: frames,
                rolls: [],
                activeRollID: nil,
                scanSessions: [],
                scanRollAssignments: []
            )
            samples.append(Self.milliseconds(started.duration(to: .now)))
            XCTAssertEqual(catalog.frames[frameCount / 2].customDisplayName, "edited-\(iteration)")
        }
        let p50 = samples.sorted()[samples.count / 2]
        print(String(format: "[perf] catalog snapshot 50000 first=%.2fms single-edit-p50=%.2fms", firstMilliseconds, p50))
        XCTAssertLessThan(p50, firstMilliseconds * 0.25)
        XCTAssertLessThan(p50, 100)
    }

    func testFrameListAvailabilityProbePublishesLatestFramePaths() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-availability-probe-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let onlineURL = root.appendingPathComponent("online.tiff")
        try Data([0]).write(to: onlineURL)
        let offlineURL = root.appendingPathComponent("offline.tiff")
        let frames = (0..<300).map { index in
            ScanFrame(
                scanIndex: index + 1,
                rawScanURL: index.isMultiple(of: 2) ? onlineURL : offlineURL,
                filmType: .colorNegative
            )
        }
        let online = frames[0]
        let offline = frames[1]
        let model = AppModel()
        defer { model.sourceAvailabilityRefreshTask?.cancel() }

        model.frames = frames
        model.frames = Array(frames.reversed())
        for _ in 0..<100 where model.librarySourceAvailability(for: online) != .online
            || model.librarySourceAvailability(for: offline) != .offline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.librarySourceAvailability(for: online), .online)
        XCTAssertEqual(model.librarySourceAvailability(for: offline), .offline)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    func testFrameRecordNeverClaimsDefectState() {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/pending-defect.tiff"),
            filmType: .colorNegative
        )
        frame.defectEdits = [DefectEditItem(
            edit: .brush([]), label: .brush(strokeCount: 1), summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)), preview: [], baseSize: nil
        )]

        let record = LibraryFrameRecord(frame: frame)

        // 기록은 세션 전용이다 — catalog 레코드에 결함 상태를 남기지 않는다.
        XCTAssertNil(record.hasDefectEdits)
        XCTAssertNil(record.cleanedRawPath)
        XCTAssertNil(record.cleanedRawEditCount)
    }

    func testCatalogRoundTripPreservesFrameState() throws {
        let frame = ScanFrame(
            scanIndex: 3,
            rawScanURL: URL(fileURLWithPath: "/tmp/roll/a.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourcePixelWidth: 5000,
            sourcePixelHeight: 3400,
            sourceResolutionDPI: 3600,
            sourceBitDepth: 16,
            storageGroupName: "roll"
        )
        frame.setRating(4)
        frame.pickState = .picked
        frame.customDisplayName = "sunset"
        frame.hasDevelopedOnce = true
        frame.baseRGB = SIMD3(0.8, 0.6, 0.4)
        frame.updateTransform { $0.flipHorizontal = true }
        frame.updateParams { $0.filmType = .colorNegative }

        let record = LibraryFrameRecord(frame: frame)
        let catalog = LibraryCatalog(
            folders: ["/tmp/roll"],
            frames: [record]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-catalog-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let data = try XCTUnwrap(LibraryCatalogFile.encode(catalog))
        LibraryCatalogFile.write(data, to: url)
        let loaded = try XCTUnwrap(LibraryCatalogFile.load(from: url))

        XCTAssertEqual(loaded.folders, ["/tmp/roll"])
        XCTAssertEqual(loaded.frames.count, 1)
        XCTAssertNil(loaded.frames[0].scanSessionID)
        XCTAssertNil(loaded.frames[0].scanJobID)
        XCTAssertEqual(loaded.rolls.map(\.id), [LibraryRoll.unassignedID])
        XCTAssertEqual(loaded.rolls[0].frameIDs, [frame.id])
        XCTAssertNil(loaded.activeRollID)

        let restored = loaded.frames[0].makeFrame(presets: [])
        XCTAssertEqual(restored.id, frame.id)
        XCTAssertEqual(restored.scanIndex, 3)
        XCTAssertEqual(restored.rawScanURL.path, "/tmp/roll/a.tiff")
        XCTAssertEqual(restored.sourceKind.storageKey, "imported")
        XCTAssertEqual(restored.storageGroupName, "roll")
        XCTAssertEqual(restored.sourcePixelWidth, 5000)
        XCTAssertEqual(restored.rating, 4)
        XCTAssertEqual(restored.pickState, .picked)
        XCTAssertEqual(restored.customDisplayName, "sunset")
        XCTAssertTrue(restored.hasDevelopedOnce)
        XCTAssertEqual(restored.baseRGB, SIMD3(0.8, 0.6, 0.4))
        XCTAssertTrue(restored.imageTransform.flipHorizontal)
        XCTAssertEqual(restored.params, frame.params)
    }

    func testCatalogRoundTripPreservesScanSessionAndRollAssignment() throws {
        let session = try makeQueuedSession()
        let assignment = LibraryScanRollAssignment(
            sessionID: session.id,
            rollID: UUID(),
            draftName: "Roll 7",
            filmType: .colorNegative,
            createdAt: session.createdAt
        )
        let catalog = LibraryCatalog(
            scanSessions: [session],
            scanRollAssignments: [assignment]
        )

        let data = try XCTUnwrap(LibraryCatalogFile.encode(catalog))
        let loaded = try XCTUnwrap(LibraryCatalogFile.decode(data))

        XCTAssertEqual(loaded.scanSessions, [session])
        XCTAssertEqual(loaded.scanRollAssignments, [assignment])
        XCTAssertTrue(LibraryCatalogHealthInspector.inspect(loaded).canOpenSafely)
    }

    func testAcknowledgedCommitWaitsForQueuedWriteAndVerifiesNewestGeneration() throws {
        let url = writeTargetURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let older = LibraryCatalog(folders: ["/offline/older"])
        let newest = LibraryCatalog(folders: ["/offline/newest"])
        let queuedWrite = expectation(description: "queued catalog write")
        LibraryCatalogFile.writeAsync(
            try XCTUnwrap(LibraryCatalogFile.encode(older)),
            to: url
        ) { succeeded in
            XCTAssertTrue(succeeded)
            queuedWrite.fulfill()
        }

        let result = LibraryCatalogFile.commitAndVerify(newest, to: url)
        wait(for: [queuedWrite], timeout: 1)

        guard case .success = result else {
            return XCTFail("acknowledged commit이 실패했습니다: \(result)")
        }
        XCTAssertEqual(LibraryCatalogFile.loadPrimary(from: url)?.folders, newest.folders)
    }

    func testSQLiteAcknowledgedCommitUsesVerifiedIncrementalGeneration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-sqlite-commit-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let original = LibraryCatalogPerformanceTests.makeCatalog(frameCount: 3)
        guard case .success = LibraryCatalogFile.commitAndVerify(original, to: url) else {
            return XCTFail("initial SQLite acknowledged commit이 실패했습니다")
        }
        var changed = original
        changed.frames[1].rating = 5

        guard case .success = LibraryCatalogFile.commitAndVerify(changed, to: url) else {
            return XCTFail("incremental SQLite acknowledged commit이 실패했습니다")
        }
        XCTAssertEqual(LibraryCatalogFile.loadPrimary(from: url), changed)
    }

    func testSQLiteAcknowledgedWriteFailureRestoresExactPreviousPrimary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-sqlite-rollback-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(
            LibraryCatalog(folders: ["/offline/baseline"]),
            to: url
        ))
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "PRAGMA user_version=99", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        let baselineData = try Data(contentsOf: url)

        let result = LibraryCatalogFile.commitAndVerify(
            LibraryCatalog(folders: ["/offline/new"]),
            to: url
        )

        guard case let .failure(error) = result else {
            return XCTFail("unsupported SQLite primary commit이 성공했습니다")
        }
        XCTAssertEqual(error, .writeFailed)
        XCTAssertEqual(try Data(contentsOf: url), baselineData)
    }

    func testAcknowledgedCommitRejectsInvalidHealthWithoutOverwritingPrimary() throws {
        let url = writeTargetURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let baseline = LibraryCatalog(folders: ["/offline/baseline"])
        guard case .success = LibraryCatalogFile.commitAndVerify(baseline, to: url) else {
            return XCTFail("baseline commit이 실패했습니다")
        }
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/missing-roll.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        let invalid = LibraryCatalog(
            frames: [LibraryFrameRecord(frame: frame)],
            rolls: []
        )

        let result = LibraryCatalogFile.commitAndVerify(invalid, to: url)

        guard case .failure(let error) = result else {
            return XCTFail("invalid catalog commit이 성공했습니다")
        }
        XCTAssertEqual(error, .invalidCatalog)
        XCTAssertEqual(LibraryCatalogFile.loadPrimary(from: url)?.folders, baseline.folders)
    }

    func testAcknowledgedCommitReportsWriteFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-commit-blocked-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blockingFile = root.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blockingFile)
        let url = blockingFile.appendingPathComponent("library.json")

        let result = LibraryCatalogFile.commitAndVerify(LibraryCatalog(), to: url)

        guard case .failure(let error) = result else {
            return XCTFail("쓰기 불가 경로 commit이 성공했습니다")
        }
        XCTAssertEqual(error, .writeFailed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAcknowledgedCommitWriterFailureRestoresExactPreviousPrimary() throws {
        let url = writeTargetURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let baseline = LibraryCatalog(folders: ["/offline/writer-baseline"])
        guard case .success = LibraryCatalogFile.commitAndVerify(baseline, to: url) else {
            return XCTFail("baseline commit이 실패했습니다")
        }
        let baselineData = try Data(contentsOf: url)

        let result = LibraryCatalogFile.commitAndVerify(
            LibraryCatalog(folders: ["/offline/writer-new"]),
            to: url,
            commitWriter: { _, _, _ in false },
            readback: { _, _ in
                XCTFail("writer 실패 뒤 read-back을 실행하면 안 됩니다")
                return .unreadable
            }
        )

        guard case .failure(let error) = result else {
            return XCTFail("writer 실패 commit이 성공했습니다")
        }
        XCTAssertEqual(error, .writeFailed)
        XCTAssertEqual(try Data(contentsOf: url), baselineData)
    }

    func testAcknowledgedCommitReadbackMismatchRestoresExactPreviousPrimary() throws {
        let url = writeTargetURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let baseline = LibraryCatalog(folders: ["/offline/readback-baseline"])
        guard case .success = LibraryCatalogFile.commitAndVerify(baseline, to: url) else {
            return XCTFail("baseline commit이 실패했습니다")
        }
        let baselineData = try Data(contentsOf: url)
        let mismatched = LibraryCatalog(folders: ["/offline/readback-mismatch"])

        let result = LibraryCatalogFile.commitAndVerify(
            LibraryCatalog(folders: ["/offline/readback-new"]),
            to: url,
            commitWriter: { data, destination, fileManager in
                LibraryCatalogFile.write(data, to: destination, fileManager: fileManager)
            },
            readback: { _, _ in
                .loaded(
                    catalog: mismatched,
                    sourceVersion: LibraryCatalog.currentVersion
                )
            }
        )

        guard case .failure(let error) = result else {
            return XCTFail("read-back mismatch commit이 성공했습니다")
        }
        XCTAssertEqual(error, .readbackFailed)
        XCTAssertEqual(try Data(contentsOf: url), baselineData)
        XCTAssertEqual(LibraryCatalogFile.loadPrimary(from: url)?.folders, baseline.folders)
    }

    func testAcknowledgedCommitReadbackFailureRestoresPreviousAbsence() {
        let url = writeTargetURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let result = LibraryCatalogFile.commitAndVerify(
            LibraryCatalog(folders: ["/offline/readback-new"]),
            to: url,
            commitWriter: { data, destination, fileManager in
                LibraryCatalogFile.write(data, to: destination, fileManager: fileManager)
            },
            readback: { _, _ in .unreadable }
        )

        guard case .failure(let error) = result else {
            return XCTFail("read-back 실패 commit이 성공했습니다")
        }
        XCTAssertEqual(error, .readbackFailed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAcknowledgedCommitReportsRollbackFailureSeparately() throws {
        let url = writeTargetURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let baseline = LibraryCatalog(folders: ["/offline/rollback-baseline"])
        guard case .success = LibraryCatalogFile.commitAndVerify(baseline, to: url) else {
            return XCTFail("baseline commit이 실패했습니다")
        }
        let baselineData = try Data(contentsOf: url)

        let result = LibraryCatalogFile.commitAndVerify(
            LibraryCatalog(folders: ["/offline/rollback-new"]),
            to: url,
            commitWriter: { data, destination, fileManager in
                LibraryCatalogFile.write(data, to: destination, fileManager: fileManager)
            },
            readback: { _, _ in .unreadable },
            rollbackWriter: { _, _ in false }
        )

        guard case .failure(let error) = result else {
            return XCTFail("rollback 실패 commit이 성공했습니다")
        }
        XCTAssertEqual(error, .rollbackFailed)
        XCTAssertNotEqual(try Data(contentsOf: url), baselineData)
    }

    func testAppModelAcknowledgedTransactionGatesDebouncedAndTerminateStyleSave() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-app-commit-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        await model.restoreLibraryOnLaunch()
        XCTAssertEqual(model.libraryLifecycleState, .ready)
        XCTAssertTrue(model.beginAcknowledgedLibraryTransaction())

        model.scheduleLibrarySave()
        XCTAssertTrue(model.librarySaveRequestedDuringTransaction)
        XCTAssertNil(model.librarySaveTask)
        XCTAssertFalse(model.saveLibrary(synchronous: true))
        guard case .success = model.commitAcknowledgedLibrarySnapshot(
            frames: model.frames,
            rolls: model.rolls,
            activeRollID: model.activeRollID,
            scanSessions: model.scanSessions,
            scanRollAssignments: model.scanRollAssignments
        ) else {
            return XCTFail("AppModel acknowledged snapshot commit이 실패했습니다")
        }

        model.endAcknowledgedLibraryTransaction()
        XCTAssertFalse(model.isAcknowledgedLibraryTransactionActive)
        XCTAssertNotNil(model.librarySaveTask)
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        model.libraryPersistenceEnabled = false
        XCTAssertNotNil(LibraryCatalogFile.loadPrimary(from: model.libraryCatalogURL))
    }

    func testAsyncCatalogFailureRemainsDirtyUntilRetrySucceeds() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-app-async-save-\(UUID().uuidString)",
            isDirectory: true
        )
        let blockingParent = root.appendingPathComponent("catalog-parent")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not-a-directory".utf8).write(to: blockingParent, options: .atomic)

        let model = AppModel(
            libraryCatalogURL: blockingParent.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        model.libraryPersistenceEnabled = true
        defer {
            model.libraryPersistenceEnabled = false
            model.librarySaveTask?.cancel()
            model.librarySaveTask = nil
        }

        model.scheduleLibrarySave()
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        let failedGeneration = model.libraryCatalogDirtyGeneration

        XCTAssertTrue(model.hasUnsavedLibraryChanges)
        XCTAssertFalse(model.saveLibrary(synchronous: false))
        try await waitUntil("카탈로그 저장 실패 세대 반영", timeout: 3) {
            model.libraryCatalogPersistenceError?.generation == failedGeneration
        }

        XCTAssertEqual(model.libraryCatalogPersistedGeneration, 0)
        XCTAssertEqual(model.libraryCatalogPersistenceError?.generation, failedGeneration)
        XCTAssertTrue(model.hasUnsavedLibraryChanges)

        try FileManager.default.removeItem(at: blockingParent)
        model.retryLibrarySave()
        XCTAssertEqual(model.libraryCatalogPersistenceError?.generation, failedGeneration)
        XCTAssertTrue(model.hasUnsavedLibraryChanges)
        try await waitUntil("카탈로그 재저장 성공 반영", timeout: 3) {
            model.libraryCatalogPersistedGeneration == failedGeneration
                && model.libraryCatalogPersistenceError == nil
        }

        XCTAssertFalse(model.hasUnsavedLibraryChanges)
        XCTAssertNotNil(LibraryCatalogFile.loadPrimary(from: model.libraryCatalogURL))
    }

    func testDelayedCatalogCompletionCannotOverwriteNewerGenerationState() {
        let model = AppModel()
        model.libraryPersistenceEnabled = true
        defer {
            model.libraryPersistenceEnabled = false
            model.librarySaveTask?.cancel()
            model.librarySaveTask = nil
        }

        model.scheduleLibrarySave()
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        let olderGeneration = model.libraryCatalogDirtyGeneration

        model.scheduleLibrarySave()
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        let newerGeneration = model.libraryCatalogDirtyGeneration

        model.recordLibraryCatalogWriteResult(
            generation: newerGeneration,
            succeeded: false
        )
        model.recordLibraryCatalogWriteResult(
            generation: olderGeneration,
            succeeded: true
        )

        XCTAssertEqual(model.libraryCatalogPersistedGeneration, olderGeneration)
        XCTAssertEqual(model.libraryCatalogPersistenceError?.generation, newerGeneration)
        XCTAssertTrue(model.hasUnsavedLibraryChanges)

        model.recordLibraryCatalogWriteResult(
            generation: newerGeneration,
            succeeded: true
        )
        model.recordLibraryCatalogWriteResult(
            generation: olderGeneration,
            succeeded: false
        )

        XCTAssertEqual(model.libraryCatalogPersistedGeneration, newerGeneration)
        XCTAssertNil(model.libraryCatalogPersistenceError)
        XCTAssertFalse(model.hasUnsavedLibraryChanges)
    }

    @MainActor
    private func makeManualBackupScheduleStore() throws -> LibraryBackupScheduleStore {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "LibraryCatalogTests-\(UUID().uuidString)")
        )
        let store = LibraryBackupScheduleStore(defaults: defaults)
        store.schedule = .manual
        return store
    }

    func testApplicationTerminationWaitsForReadbackCommitApproval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-termination-approval-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        // 이 테스트가 보는 것은 종료 커밋 승인 흐름이다. 종료 시 자동 백업(기본값)이 끼면
        // completion 이 백업 완료 뒤로 밀리므로, 백업은 끈 채로 검사한다.
        let model = AppModel(
            backupScheduleStore: try makeManualBackupScheduleStore(),
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        let previewURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow_preview_\(UUID().uuidString).tiff"
        )
        try Data("preview".utf8).write(to: previewURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: previewURL) }
        model.frames = [ScanFrame(
            scanIndex: 1,
            rawScanURL: previewURL,
            filmType: .colorNegative,
            isPreviewScan: true
        )]
        model.libraryPersistenceEnabled = true
        defer { model.libraryPersistenceEnabled = false }
        var pendingCompletion: LibraryTerminationCommitCompletion?
        var pendingGeneration: UInt64?
        var replies: [Bool] = []

        let decision = model.beginApplicationTermination(
            scheduleCommit: { _, generation, _, _, completion in
                pendingGeneration = generation
                pendingCompletion = completion
            },
            completion: { replies.append($0) }
        )

        XCTAssertEqual(decision, .terminateLater)
        XCTAssertTrue(model.isLibraryTerminationSaveInProgress)
        XCTAssertEqual(model.libraryTerminationAttemptGeneration, pendingGeneration)
        XCTAssertTrue(model.hasUnsavedLibraryChanges)
        XCTAssertTrue(replies.isEmpty)

        pendingCompletion?(.success(()))

        XCTAssertEqual(replies, [true])
        XCTAssertFalse(model.isLibraryTerminationSaveInProgress)
        XCTAssertNil(model.libraryTerminationAttemptGeneration)
        XCTAssertEqual(model.libraryCatalogPersistedGeneration, pendingGeneration)
        XCTAssertFalse(model.hasUnsavedLibraryChanges)
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewURL.path))
    }

    func testProductionApplicationTerminationApprovesReadableCatalog() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-termination-production-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        model.libraryPersistenceEnabled = true
        defer { model.libraryPersistenceEnabled = false }

        let shouldTerminate = await withCheckedContinuation { continuation in
            let decision = model.beginApplicationTermination {
                continuation.resume(returning: $0)
            }
            XCTAssertEqual(decision, .terminateLater)
        }

        XCTAssertTrue(shouldTerminate)
        let catalog = try XCTUnwrap(
            LibraryCatalogFile.loadPrimary(from: model.libraryCatalogURL)
        )
        XCTAssertTrue(
            LibraryCatalogHealthInspector.inspect(
                catalog,
                defectDirectory: model.libraryDefectDirectoryURL
            ).canOpenSafely
        )
        XCTAssertFalse(model.hasUnsavedLibraryChanges)
        XCTAssertNil(model.libraryCatalogPersistenceError)
    }

    func testApplicationTerminationReadbackFailureKeepsUnsavedErrorAndCancelsQuit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-termination-failure-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        model.libraryPersistenceEnabled = true
        defer { model.libraryPersistenceEnabled = false }
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        let previouslyPersistedGeneration = model.libraryCatalogPersistedGeneration
        let previewURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow_preview_\(UUID().uuidString).tiff"
        )
        try Data("preview".utf8).write(to: previewURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: previewURL) }
        model.frames = [ScanFrame(
            scanIndex: 1,
            rawScanURL: previewURL,
            filmType: .colorNegative,
            isPreviewScan: true
        )]
        var pendingCompletion: LibraryTerminationCommitCompletion?
        var pendingGeneration: UInt64?
        var replies: [Bool] = []

        let decision = model.beginApplicationTermination(
            scheduleCommit: { _, generation, _, _, completion in
                pendingGeneration = generation
                pendingCompletion = completion
            },
            completion: { replies.append($0) }
        )
        let failedGeneration = try XCTUnwrap(pendingGeneration)

        XCTAssertEqual(decision, .terminateLater)
        XCTAssertGreaterThan(failedGeneration, previouslyPersistedGeneration)
        pendingCompletion?(.failure(.readbackFailed))

        XCTAssertEqual(replies, [false])
        XCTAssertFalse(model.isLibraryTerminationSaveInProgress)
        XCTAssertNil(model.libraryTerminationAttemptGeneration)
        XCTAssertEqual(
            model.libraryCatalogPersistedGeneration,
            previouslyPersistedGeneration
        )
        XCTAssertEqual(model.libraryCatalogPersistenceError?.generation, failedGeneration)
        XCTAssertTrue(model.hasUnsavedLibraryChanges)
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
    }

    func testApplicationTerminationReapprovesWhenNewerDirtyGenerationArrives() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-termination-newer-generation-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(
            backupScheduleStore: try makeManualBackupScheduleStore(),
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        model.libraryPersistenceEnabled = true
        defer {
            model.libraryPersistenceEnabled = false
            model.librarySaveTask?.cancel()
            model.librarySaveTask = nil
        }
        var scheduledGenerations: [UInt64] = []
        var pendingCompletions: [LibraryTerminationCommitCompletion] = []
        var replies: [Bool] = []

        let decision = model.beginApplicationTermination(
            scheduleCommit: { _, generation, _, _, completion in
                scheduledGenerations.append(generation)
                pendingCompletions.append(completion)
            },
            completion: { replies.append($0) }
        )
        XCTAssertEqual(decision, .terminateLater)
        XCTAssertEqual(scheduledGenerations.count, 1)

        model.scheduleLibrarySave()
        let changedGeneration = model.libraryCatalogDirtyGeneration
        let firstCompletion = try XCTUnwrap(pendingCompletions.first)
        firstCompletion(.success(()))

        XCTAssertTrue(replies.isEmpty)
        XCTAssertEqual(scheduledGenerations.count, 2)
        XCTAssertGreaterThan(try XCTUnwrap(scheduledGenerations.last), changedGeneration)
        XCTAssertTrue(model.isLibraryTerminationSaveInProgress)

        let latestCompletion = try XCTUnwrap(pendingCompletions.last)
        latestCompletion(.success(()))

        XCTAssertEqual(replies, [true])
        XCTAssertEqual(
            model.libraryCatalogPersistedGeneration,
            try XCTUnwrap(scheduledGenerations.last)
        )
        XCTAssertFalse(model.hasUnsavedLibraryChanges)
        XCTAssertFalse(model.isLibraryTerminationSaveInProgress)
    }

    func testFrameRecordPreservesImmutableScanWorkflowReference() {
        let sessionID = UUID()
        let jobID = UUID()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/scan-provenance.tiff"),
            filmType: .colorNegative,
            scanSessionID: sessionID,
            scanJobID: jobID
        )

        let record = LibraryFrameRecord(frame: frame)
        let restored = record.makeFrame(presets: [])

        XCTAssertEqual(record.scanSessionID, sessionID)
        XCTAssertEqual(record.scanJobID, jobID)
        XCTAssertEqual(restored.scanSessionID, sessionID)
        XCTAssertEqual(restored.scanJobID, jobID)
    }

    func testAppModelSaveAndRestoreKeepsQueuedScanWorkflow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-app-scan-workflow-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = root.appendingPathComponent("library.json")
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let session = try makeQueuedSession()
        let assignment = LibraryScanRollAssignment(
            sessionID: session.id,
            rollID: UUID(),
            draftName: "Queued roll",
            filmType: .colorNegative,
            createdAt: session.createdAt
        )
        let source = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defects,
            libraryBackupDirectoryURL: backups
        )
        source.scanSessions = [session]
        source.scanRollAssignments = [assignment]
        source.librarySaveTask?.cancel()
        source.librarySaveTask = nil
        source.libraryPersistenceEnabled = true
        XCTAssertTrue(source.saveLibrary(synchronous: true))
        source.libraryPersistenceEnabled = false

        let restored = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defects,
            libraryBackupDirectoryURL: backups
        )
        await restored.restoreLibraryOnLaunch()
        defer {
            restored.libraryPersistenceEnabled = false
            restored.librarySaveTask?.cancel()
            restored.librarySaveTask = nil
        }

        XCTAssertEqual(restored.scanSessions, [session])
        XCTAssertEqual(restored.scanRollAssignments, [assignment])
        XCTAssertEqual(restored.libraryLifecycleState, .ready)
    }

    func testVersionsThreeAndFourDecodeRequireScanWorkflowKeys() throws {
        let versionFourData = try makeVersionFourData(LibraryCatalog())
        let versionThreeData = try makeVersionThreeData(LibraryCatalog())

        for (version, data) in [(3, versionThreeData), (4, versionFourData)] {
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            for missingKey in ["scanSessions", "scanRollAssignments"] {
                var malformed = object
                malformed.removeValue(forKey: missingKey)
                let malformedData = try JSONSerialization.data(withJSONObject: malformed)
                guard case .invalid = LibraryCatalogFile.decodeResult(malformedData) else {
                    return XCTFail("v\(version) catalog missing \(missingKey) must fail closed")
                }
            }
        }
    }

    func testVirtualCopyFieldsSurviveRoundTrip() throws {
        let original = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/roll/b.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile,
            storageGroupName: "roll"
        )
        let copy = original.makeVirtualCopy(copyNumber: 2)

        let record = LibraryFrameRecord(frame: copy)
        let data = try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog(frames: [record])))
        let decoded = try XCTUnwrap(
            LibraryCatalogFile.load(from: writeTemp(data))
        )
        let restored = decoded.frames[0].makeFrame(presets: [])

        XCTAssertEqual(restored.sourceFrameID, original.id)
        XCTAssertEqual(restored.virtualCopyNumber, 2)
        XCTAssertEqual(restored.storageGroupName, "roll")
        XCTAssertTrue(restored.isVirtualCopy)
    }

    func testFrameSourceStorageKeyRoundTrip() {
        for source in [FrameSource.scannerTIFF, .importedFile] {
            XCTAssertEqual(FrameSource(storageKey: source.storageKey), source)
        }
        XCTAssertNil(FrameSource(storageKey: "unknown"))
    }

    func testCorruptPrimaryLoadsLastValidBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-catalog-backup-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = LibraryCatalog(folders: ["/first"], frames: [])
        let second = LibraryCatalog(folders: ["/second"], frames: [])
        XCTAssertTrue(LibraryCatalogFile.write(try XCTUnwrap(LibraryCatalogFile.encode(first)), to: url))
        XCTAssertTrue(LibraryCatalogFile.write(try XCTUnwrap(LibraryCatalogFile.encode(second)), to: url))
        try Data("{broken".utf8).write(to: url, options: .atomic)

        let recovered = try XCTUnwrap(LibraryCatalogFile.load(from: url))
        XCTAssertEqual(recovered.folders, ["/first"])
    }

    func testUnsupportedCatalogVersionIsRejected() throws {
        var catalog = LibraryCatalog()
        catalog.version = LibraryCatalog.currentVersion + 1
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-catalog-future-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(LibraryCatalogFile.encode(catalog)).write(to: url)

        XCTAssertNil(LibraryCatalogFile.load(from: url))
    }

    func testKnownCatalogSchemasRequireExactMinimumReaderVersions() throws {
        XCTAssertEqual(LibraryCatalog.currentVersion, 6)
        XCTAssertEqual(LibraryCatalog.oldestReaderVersion, 6)

        let versionSixData = try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog()))
        guard case let .loaded(versionSix, versionSixSource) =
                LibraryCatalogFile.decodeResult(versionSixData) else {
            return XCTFail("v6 catalog with minimum reader v6 must load")
        }
        XCTAssertEqual(versionSixSource, 6)
        XCTAssertEqual(versionSix.minimumReaderVersion, 6)
        for incorrectMinimum in [5, 7] {
            let malformed = try rewriteVersion(
                versionSixData,
                version: 6,
                minimumReaderVersion: incorrectMinimum
            )
            guard case .invalid = LibraryCatalogFile.decodeResult(malformed) else {
                return XCTFail("v6 catalog with minimum reader v\(incorrectMinimum) must be invalid")
            }
        }

        let versionFiveData = try makeVersionFiveData(LibraryCatalog())
        guard case let .loaded(versionFive, versionFiveSource) =
                LibraryCatalogFile.decodeResult(versionFiveData) else {
            return XCTFail("v5 catalog with minimum reader v5 must migrate")
        }
        XCTAssertEqual(versionFiveSource, 5)
        XCTAssertEqual(versionFive.minimumReaderVersion, 6)
        XCTAssertTrue(versionFive.stacks.isEmpty)
        for incorrectMinimum in [4, 6] {
            let malformed = try rewriteVersion(
                versionFiveData,
                version: 5,
                minimumReaderVersion: incorrectMinimum
            )
            guard case .invalid = LibraryCatalogFile.decodeResult(malformed) else {
                return XCTFail("v5 catalog with minimum reader v\(incorrectMinimum) must be invalid")
            }
        }

        let versionFourData = try makeVersionFourData(LibraryCatalog())
        guard case let .loaded(versionFour, versionFourSource) =
                LibraryCatalogFile.decodeResult(versionFourData) else {
            return XCTFail("v4 catalog with minimum reader v4 must load")
        }
        XCTAssertEqual(versionFourSource, 4)
        XCTAssertEqual(versionFour.minimumReaderVersion, 6)
        for incorrectMinimum in [3, 5] {
            let malformed = try rewriteVersion(
                versionFourData,
                version: 4,
                minimumReaderVersion: incorrectMinimum
            )
            guard case .invalid = LibraryCatalogFile.decodeResult(malformed) else {
                return XCTFail("v4 catalog with minimum reader v\(incorrectMinimum) must be invalid")
            }
        }

        let versionThreeData = try makeVersionThreeData(LibraryCatalog())
        guard case let .loaded(versionThree, versionThreeSource) =
                LibraryCatalogFile.decodeResult(versionThreeData) else {
            return XCTFail("v3 catalog with minimum reader v3 must migrate")
        }
        XCTAssertEqual(versionThreeSource, 3)
        XCTAssertEqual(versionThree.minimumReaderVersion, 6)
        for incorrectMinimum in [2, 4] {
            let malformed = try rewriteVersion(
                versionThreeData,
                version: 3,
                minimumReaderVersion: incorrectMinimum
            )
            guard case .invalid = LibraryCatalogFile.decodeResult(malformed) else {
                return XCTFail("v3 catalog with minimum reader v\(incorrectMinimum) must be invalid")
            }
        }

        let versionTwoData = try makeVersionTwoData(LibraryCatalog())
        guard case let .loaded(_, versionTwoSource) =
                LibraryCatalogFile.decodeResult(versionTwoData) else {
            return XCTFail("v2 catalog with minimum reader v2 must migrate")
        }
        XCTAssertEqual(versionTwoSource, 2)
        for incorrectMinimum in [1, 3] {
            let malformed = try rewriteVersion(
                versionTwoData,
                version: 2,
                minimumReaderVersion: incorrectMinimum
            )
            guard case .invalid = LibraryCatalogFile.decodeResult(malformed) else {
                return XCTFail("v2 catalog with minimum reader v\(incorrectMinimum) must be invalid")
            }
        }
    }

    func testVersionSixRequiresCollectionFrameTrackingAndStackKeys() throws {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/v5-required.tiff"),
            filmType: .colorNegative
        )
        let data = try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog(
            frames: [LibraryFrameRecord(frame: frame)]
        )))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        for key in ["manualCollections", "smartCollections", "savedSearches", "stacks"] {
            var malformed = object
            malformed.removeValue(forKey: key)
            let malformedData = try JSONSerialization.data(withJSONObject: malformed)
            guard case .invalid = LibraryCatalogFile.decodeResult(malformedData) else {
                return XCTFail("v6 catalog missing \(key) must fail closed")
            }
        }

        for key in ["userEditTracking", "exportTracking", "defectReviewTracking"] {
            var malformed = object
            var frames = try XCTUnwrap(malformed["frames"] as? [[String: Any]])
            frames[0].removeValue(forKey: key)
            malformed["frames"] = frames
            let malformedData = try JSONSerialization.data(withJSONObject: malformed)
            guard case .invalid = LibraryCatalogFile.decodeResult(malformedData) else {
                return XCTFail("v6 frame missing \(key) must fail closed")
            }
        }
    }

    func testVersionFourFixtureMigratesEveryFieldToVersionFiveWithoutInferringTracking() throws {
        let original = try makeFullyPopulatedVersionThreeCatalog()
        let versionFourData = try makeVersionFourData(original)
        let versionFourObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: versionFourData) as? [String: Any]
        )
        let versionFourFrames = try XCTUnwrap(
            versionFourObject["frames"] as? [[String: Any]]
        )
        let versionFourFrame = try XCTUnwrap(versionFourFrames.first)

        XCTAssertEqual(Set(versionFourObject.keys), Self.versionFourCatalogFieldKeys)
        XCTAssertEqual(Set(versionFourFrame.keys), Self.versionFourFrameFieldKeys)
        XCTAssertNotNil(versionFourFrame["sourceMetadata"])

        guard case let .loaded(migrated, sourceVersion) =
                LibraryCatalogFile.decodeResult(versionFourData) else {
            return XCTFail("v4 fixture가 v5로 마이그레이션되지 않았습니다")
        }

        XCTAssertEqual(sourceVersion, 4)
        XCTAssertEqual(migrated.version, 6)
        XCTAssertEqual(migrated.minimumReaderVersion, 6)
        XCTAssertEqual(migrated.folders, original.folders)
        XCTAssertEqual(migrated.rolls, original.rolls)
        XCTAssertEqual(migrated.activeRollID, original.activeRollID)
        XCTAssertEqual(migrated.scanSessions, original.scanSessions)
        XCTAssertEqual(migrated.scanRollAssignments, original.scanRollAssignments)
        XCTAssertEqual(migrated.frames.first?.sourceMetadata, original.frames.first?.sourceMetadata)
        XCTAssertEqual(migrated.frames.first?.userEditTracking.coverage, .legacyUnknown)
        XCTAssertNil(migrated.frames.first?.userEditTracking.ingestRecipeSHA256)
        XCTAssertNotNil(migrated.frames.first?.userEditTracking.currentRecipeSHA256)
        XCTAssertEqual(migrated.frames.first?.exportTracking, .legacyUnknown)
        XCTAssertEqual(migrated.frames.first?.defectReviewTracking, .legacyUnknown)
        XCTAssertTrue(migrated.manualCollections.isEmpty)
        XCTAssertTrue(migrated.smartCollections.isEmpty)
        XCTAssertTrue(migrated.savedSearches.isEmpty)
        XCTAssertTrue(migrated.stacks.isEmpty)

        let migratedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: XCTUnwrap(LibraryCatalogFile.encode(migrated))
            ) as? [String: Any]
        )
        let migratedFrames = try XCTUnwrap(migratedObject["frames"] as? [[String: Any]])
        let migratedFrame = try XCTUnwrap(migratedFrames.first)
        XCTAssertEqual(
            NSDictionary(dictionary: migratedFrame.filter {
                Self.versionFourFrameFieldKeys.contains($0.key)
            }),
            NSDictionary(dictionary: versionFourFrame),
            "v4의 모든 frame 필드는 값 변화 없이 v5로 이동해야 합니다"
        )
    }

    func testVersionFiveRoundTripPreservesCollectionsTrackingAndStoredSearches() throws {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/v5-roundtrip.tiff"),
            filmType: .colorNegative
        )
        var record = LibraryFrameRecord(frame: frame)
        let recipeHash = try LibraryDevelopRecipeFingerprint.sha256(
            filmType: frame.filmType,
            presetID: frame.preset?.id,
            params: frame.params,
            imageTransform: frame.imageTransform
        )
        record.userEditTracking = LibraryUserEditTracking(
            coverage: .tracked,
            ingestRecipeSHA256: recipeHash,
            currentRecipeSHA256: recipeHash,
            revision: 0
        )
        let event = LibraryExportEvent(
            id: UUID(),
            completedAt: Date(timeIntervalSince1970: 1_700_500_000),
            primaryOutputPath: "/exports/frame.tiff",
            artifactPaths: ["/exports/frame.tiff", "/exports/frame.xmp"],
            formatRawValue: "tiff16",
            renderKind: .developed,
            developRecipeSHA256: recipeHash,
            defectRecipeSHA256: nil
        )
        record.exportTracking = LibraryExportTracking(
            coverage: .tracked,
            successfulEvents: [event]
        )
        record.defectReviewTracking = LibraryDefectReviewTracking(
            coverage: .tracked,
            currentRecipeRevision: 3,
            currentRecipeSHA256: String(repeating: "a", count: 64),
            currentSourceIdentitySHA256: String(repeating: "b", count: 64),
            reviewedRecipeRevision: 3,
            reviewedRecipeSHA256: String(repeating: "a", count: 64),
            reviewedSourceIdentitySHA256: String(repeating: "b", count: 64)
        )
        let definition = try LibraryStoredSearchEnvelope(definition: LibrarySearchDefinition(
            query: LibraryQuery(conditions: [
                .rating(comparison: .greaterThanOrEqual, value: 4),
            ]),
            sort: LibrarySortDescriptor(key: .rating, ascending: false)
        ))
        let manual = LibraryManualCollection(
            id: UUID(),
            name: "Portfolio",
            frameIDs: [frame.id]
        )
        let smart = LibrarySmartCollection(id: UUID(), name: "Four Stars", definition: definition)
        let saved = LibrarySavedSearch(id: UUID(), name: "Review", definition: definition)
        let catalog = LibraryCatalog(
            frames: [record],
            manualCollections: [manual],
            smartCollections: [smart],
            savedSearches: [saved]
        )

        let decoded = try XCTUnwrap(
            LibraryCatalogFile.decode(XCTUnwrap(LibraryCatalogFile.encode(catalog)))
        )

        XCTAssertEqual(decoded.manualCollections, [manual])
        XCTAssertEqual(decoded.smartCollections, [smart])
        XCTAssertEqual(decoded.savedSearches, [saved])
        XCTAssertEqual(decoded.frames.first?.userEditTracking, record.userEditTracking)
        XCTAssertEqual(decoded.frames.first?.exportTracking, record.exportTracking)
        XCTAssertEqual(decoded.frames.first?.defectReviewTracking, record.defectReviewTracking)
        XCTAssertEqual(decoded.smartCollections.first?.definition.decodedDefinition()?.query,
                       definition.decodedDefinition()?.query)
    }

    func testInvalidStoredSearchPayloadDoesNotInvalidateCatalogAndSurvivesRoundTrip() throws {
        let rawPayload = "{\"version\":1,\"query\":{\"version\":999}}"
        let envelope = LibraryStoredSearchEnvelope(payloadJSON: rawPayload)
        let invalid = LibrarySavedSearch(id: UUID(), name: "Damaged", definition: envelope)
        let catalog = LibraryCatalog(savedSearches: [invalid])

        let firstData = try XCTUnwrap(LibraryCatalogFile.encode(catalog))
        guard case let .loaded(first, sourceVersion) =
                LibraryCatalogFile.decodeResult(firstData) else {
            return XCTFail("invalid inner query must not invalidate outer catalog")
        }
        XCTAssertEqual(sourceVersion, 6)
        XCTAssertNil(first.savedSearches[0].definition.decodedDefinition())
        XCTAssertEqual(first.savedSearches[0].definition.payloadJSON, rawPayload)

        let secondData = try XCTUnwrap(LibraryCatalogFile.encode(first))
        let second = try XCTUnwrap(LibraryCatalogFile.decode(secondData))
        XCTAssertEqual(second.savedSearches[0].definition.payloadJSON, rawPayload)
    }

    func testDevelopRecipeFingerprintIsDeterministicAndTracksEffectiveRecipe() throws {
        var params = DevelopParameters()
        let first = try LibraryDevelopRecipeFingerprint.sha256(
            filmType: .colorNegative,
            presetID: "neutral",
            params: params,
            imageTransform: .identity
        )
        let repeated = try LibraryDevelopRecipeFingerprint.sha256(
            filmType: .colorNegative,
            presetID: "neutral",
            params: params,
            imageTransform: .identity
        )
        params.exposure = 0.5
        let changed = try LibraryDevelopRecipeFingerprint.sha256(
            filmType: .colorNegative,
            presetID: "neutral",
            params: params,
            imageTransform: .identity
        )

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.count, 64)
        XCTAssertNotEqual(first, changed)
    }

    func testVersionThreeFixtureMigratesAllPersistedStateAndEveryFrameFieldToVersionFive() throws {
        let original = try makeFullyPopulatedVersionThreeCatalog()
        let versionThreeData = try makeVersionThreeData(original)
        let versionThreeObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: versionThreeData) as? [String: Any]
        )
        let versionThreeFrames = try XCTUnwrap(versionThreeObject["frames"] as? [[String: Any]])
        let versionThreeFrame = try XCTUnwrap(versionThreeFrames.first)

        XCTAssertEqual(Set(versionThreeObject.keys), Self.versionThreeCatalogFieldKeys)
        XCTAssertEqual(versionThreeFrame.count, 32)
        XCTAssertEqual(Set(versionThreeFrame.keys), Self.versionThreeFrameFieldKeys)
        XCTAssertNil(versionThreeFrame["sourceMetadata"])

        guard case let .loaded(migrated, sourceVersion) =
                LibraryCatalogFile.decodeResult(versionThreeData) else {
            return XCTFail("실제 v3 fixture가 v5로 마이그레이션되지 않았습니다")
        }

        XCTAssertEqual(sourceVersion, 3)
        XCTAssertEqual(migrated.version, 6)
        XCTAssertEqual(migrated.minimumReaderVersion, 6)
        XCTAssertEqual(migrated.folders, original.folders)
        XCTAssertEqual(migrated.rolls, original.rolls)
        XCTAssertEqual(migrated.activeRollID, original.activeRollID)
        XCTAssertEqual(migrated.scanSessions, original.scanSessions)
        XCTAssertEqual(migrated.scanRollAssignments, original.scanRollAssignments)
        XCTAssertEqual(migrated.frames.count, 1)
        XCTAssertNil(migrated.frames[0].sourceMetadata)
        XCTAssertEqual(migrated.frames[0].userEditTracking.coverage, .legacyUnknown)
        XCTAssertEqual(migrated.frames[0].exportTracking, .legacyUnknown)
        XCTAssertEqual(migrated.frames[0].defectReviewTracking, .legacyUnknown)
        XCTAssertTrue(migrated.manualCollections.isEmpty)
        XCTAssertTrue(migrated.smartCollections.isEmpty)
        XCTAssertTrue(migrated.savedSearches.isEmpty)
        XCTAssertTrue(migrated.stacks.isEmpty)

        let migratedData = try XCTUnwrap(LibraryCatalogFile.encode(migrated))
        let migratedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
        )
        let migratedFrames = try XCTUnwrap(migratedObject["frames"] as? [[String: Any]])
        let migratedFrame = try XCTUnwrap(migratedFrames.first)
        XCTAssertEqual(
            NSDictionary(dictionary: migratedFrame.filter {
                Self.versionThreeFrameFieldKeys.contains($0.key)
            }),
            NSDictionary(dictionary: versionThreeFrame),
            "v3의 32개 프레임 필드는 값 변화 없이 v5로 이동해야 합니다"
        )
    }

    func testVersionFiveMetadataRoundTripPreservesEveryMetadataOrigin() throws {
        let metadata = makeSourceMetadataSnapshot()
        let frame = ScanFrame(
            scanIndex: 4,
            rawScanURL: URL(fileURLWithPath: "/tmp/v4-metadata/source.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourcePixelWidth: 6_000,
            sourcePixelHeight: 4_000,
            sourceResolutionDPI: 2_400,
            sourceBitDepth: 16,
            sourceMetadata: metadata,
            scannedAt: Date(timeIntervalSince1970: 1_700_100_000)
        )
        let data = try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog(
            folders: ["/tmp/v4-metadata"],
            frames: [LibraryFrameRecord(frame: frame)]
        )))

        guard case let .loaded(decoded, sourceVersion) = LibraryCatalogFile.decodeResult(data) else {
            return XCTFail("v5 metadata catalog should round-trip")
        }

        XCTAssertEqual(sourceVersion, 6)
        XCTAssertEqual(decoded.version, 6)
        XCTAssertEqual(decoded.minimumReaderVersion, 6)
        XCTAssertEqual(decoded.frames.first?.sourceMetadata, metadata)
        XCTAssertEqual(decoded.frames.first?.makeFrame(presets: []).sourceMetadata, metadata)
    }

    func testVersionOneCatalogMigratesEveryPersistedFieldToVersionFive() throws {
        let frame = ScanFrame(
            scanIndex: 9,
            rawScanURL: URL(fileURLWithPath: "/tmp/legacy/raw.tiff"),
            filmType: .colorNegative,
            infraredScanURL: URL(fileURLWithPath: "/tmp/legacy/ir.tiff"),
            rawScanBookmarkData: Data([1, 2, 3]),
            infraredScanBookmarkData: Data([4, 5, 6]),
            sourceKind: .scannerTIFF,
            sourcePixelWidth: 6400,
            sourcePixelHeight: 4200,
            sourceResolutionDPI: 3600,
            sourceBitDepth: 16,
            sourceFrameID: UUID(),
            sourceFrameDisplayName: "source",
            virtualCopyNumber: 3,
            storageGroupName: "legacy-roll"
        )
        frame.setRating(5)
        frame.pickState = .rejected
        frame.customDisplayName = "legacy frame"
        frame.hasDevelopedOnce = true
        frame.baseRGB = SIMD3(0.75, 0.55, 0.35)
        frame.updateTransform { $0.rotation = .deg90 }
        var record = LibraryFrameRecord(frame: frame)
        record.cleanedRawPath = "/tmp/legacy/cleaned.tiff"
        record.cleanedRawEditCount = 4
        record.hasDefectEdits = true
        record.userEditTracking = .legacyUnknown(
            currentRecipeSHA256: record.userEditTracking.currentRecipeSHA256
        )
        record.exportTracking = .legacyUnknown
        record.defectReviewTracking = .legacyUnknown
        let expected = LibraryCatalog(folders: ["/tmp/legacy"], frames: [record])
        let legacyData = try makeVersionOneData(expected)

        guard case let .loaded(migrated, sourceVersion) = LibraryCatalogFile.decodeResult(legacyData) else {
            return XCTFail("v1 catalog should migrate")
        }

        XCTAssertEqual(sourceVersion, 1)
        XCTAssertEqual(migrated.version, LibraryCatalog.currentVersion)
        XCTAssertEqual(migrated.minimumReaderVersion, LibraryCatalog.oldestReaderVersion)
        XCTAssertTrue(migrated.scanSessions.isEmpty)
        XCTAssertTrue(migrated.scanRollAssignments.isEmpty)
        XCTAssertEqual(
            try jsonObject(try XCTUnwrap(LibraryCatalogFile.encode(migrated))),
            try jsonObject(try XCTUnwrap(LibraryCatalogFile.encode(expected)))
        )
    }

    func testVersionTwoMigrationCreatesOneDeterministicUnassignedRollWithoutInferringFilmType() throws {
        let later = ScanFrame(
            scanIndex: 7,
            rawScanURL: URL(fileURLWithPath: "/tmp/v2/later.tiff"),
            filmType: .colorNegative,
            scannedAt: Date(timeIntervalSince1970: 200)
        )
        let earlier = ScanFrame(
            scanIndex: 2,
            rawScanURL: URL(fileURLWithPath: "/tmp/v2/earlier.tiff"),
            filmType: .bwPositive,
            scannedAt: Date(timeIntervalSince1970: 100)
        )
        let original = LibraryCatalog(
            folders: ["/tmp/v2"],
            frames: [LibraryFrameRecord(frame: later), LibraryFrameRecord(frame: earlier)]
        )
        let legacyData = try makeVersionTwoData(original)

        guard case let .loaded(first, sourceVersion) = LibraryCatalogFile.decodeResult(legacyData),
              case let .loaded(second, _) = LibraryCatalogFile.decodeResult(legacyData) else {
            return XCTFail("v2 catalog should migrate")
        }

        XCTAssertEqual(sourceVersion, 2)
        XCTAssertEqual(
            try jsonObject(try XCTUnwrap(LibraryCatalogFile.encode(first))),
            try jsonObject(try XCTUnwrap(LibraryCatalogFile.encode(second)))
        )
        XCTAssertEqual(first.version, LibraryCatalog.currentVersion)
        XCTAssertEqual(first.minimumReaderVersion, LibraryCatalog.oldestReaderVersion)
        XCTAssertEqual(first.folders, ["/tmp/v2"])
        XCTAssertEqual(first.frames.map(\.id), [later.id, earlier.id])
        XCTAssertEqual(first.rolls.count, 1)
        XCTAssertEqual(first.rolls[0].id, LibraryRoll.unassignedID)
        XCTAssertEqual(first.rolls[0].kind, .unassigned)
        XCTAssertNil(first.rolls[0].name)
        XCTAssertNil(first.rolls[0].filmType)
        XCTAssertEqual(first.rolls[0].createdAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(first.rolls[0].frameIDs, [later.id, earlier.id])
        XCTAssertNil(first.activeRollID)
        XCTAssertTrue(first.scanSessions.isEmpty)
        XCTAssertTrue(first.scanRollAssignments.isEmpty)
        XCTAssertTrue(first.frames.allSatisfy {
            $0.scanSessionID == nil && $0.scanJobID == nil
        })
    }

    func testEmptyLegacyCatalogsDoNotCreateAnUnassignedRoll() throws {
        let empty = LibraryCatalog()
        for data in [try makeVersionOneData(empty), try makeVersionTwoData(empty)] {
            guard case let .loaded(migrated, _) = LibraryCatalogFile.decodeResult(data) else {
                return XCTFail("empty legacy catalog should migrate")
            }
            XCTAssertTrue(migrated.frames.isEmpty)
            XCTAssertTrue(migrated.rolls.isEmpty)
            XCTAssertNil(migrated.activeRollID)
            XCTAssertTrue(migrated.scanSessions.isEmpty)
            XCTAssertTrue(migrated.scanRollAssignments.isEmpty)
        }
    }

    func testCatalogInitializerDistinguishesOmittedRollsFromExplicitEmptyRolls() {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/unassigned.tiff"),
            filmType: .colorNegative,
            scannedAt: Date(timeIntervalSince1970: 25)
        )
        let record = LibraryFrameRecord(frame: frame)

        let compatible = LibraryCatalog(frames: [record])
        let explicitlyEmpty = LibraryCatalog(frames: [record], rolls: [])

        XCTAssertEqual(compatible.rolls.count, 1)
        XCTAssertEqual(compatible.rolls[0].createdAt, frame.scannedAt)
        XCTAssertEqual(compatible.rolls[0].frameIDs, [frame.id])
        XCTAssertTrue(explicitlyEmpty.rolls.isEmpty)
    }

    func testPhysicalRollFactoryRequiresARealNameAndNeverUsesReservedID() {
        XCTAssertNil(LibraryRoll.physical(name: "  ", filmType: .colorNegative))
        XCTAssertNil(LibraryRoll.physical(
            id: LibraryRoll.unassignedID,
            name: "Roll 1",
            filmType: .colorNegative
        ))

        let roll = LibraryRoll.physical(
            name: "Roll 1",
            createdAt: Date(timeIntervalSince1970: 10),
            filmType: .bwNegative
        )
        XCTAssertEqual(roll?.kind, .physical)
        XCTAssertEqual(roll?.name, "Roll 1")
        XCTAssertEqual(roll?.filmType, .bwNegative)
        XCTAssertEqual(roll?.frameIDs, [])
    }

    func testPrepareForUseMigratesOnDiskPreservesV1AndIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-catalog-migration-\(UUID().uuidString)", isDirectory: true)
        let catalogURL = root.appendingPathComponent("library.json")
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/migrate.tiff"),
            filmType: .colorNegative
        )
        let catalog = LibraryCatalog(
            folders: ["/tmp"],
            frames: [LibraryFrameRecord(frame: frame)]
        )
        let legacyData = try makeVersionOneData(catalog)
        try legacyData.write(to: catalogURL, options: .atomic)

        guard case let .loaded(migrated, recovered, sourceVersion, _) = LibraryCatalogFile.prepareForUse(
            at: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups
        ) else {
            return XCTFail("v1 catalog should prepare successfully")
        }
        XCTAssertFalse(recovered)
        XCTAssertEqual(sourceVersion, 1)
        XCTAssertEqual(migrated.frames.map(\.id), [frame.id])
        guard case let .loaded(onDisk, onDiskVersion) = LibraryCatalogFile.read(from: catalogURL) else {
            return XCTFail("migrated primary should be readable")
        }
        XCTAssertEqual(onDiskVersion, LibraryCatalog.currentVersion)
        XCTAssertEqual(onDisk.frames.map(\.id), [frame.id])
        XCTAssertEqual(try Data(contentsOf: LibraryCatalogFile.backupURL(for: catalogURL)), legacyData)
        XCTAssertNotNil(LibraryBackupStore.latestValidSnapshot(in: backups))

        let generationCount = try backupGenerationCount(in: backups)
        guard case let .loaded(_, recoveredAgain, migratedAgain, _) = LibraryCatalogFile.prepareForUse(
            at: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups
        ) else {
            return XCTFail("current catalog should reopen")
        }
        XCTAssertFalse(recoveredAgain)
        XCTAssertNil(migratedAgain)
        XCTAssertEqual(try backupGenerationCount(in: backups), generationCount)
    }

    func testPrepareForUseMigratesVersionTwoOnceAndPreservesItsRawBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-catalog-v2-migration-\(UUID().uuidString)", isDirectory: true)
        let catalogURL = root.appendingPathComponent("library.json")
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/migrate-v2.tiff"),
            filmType: .colorPositive,
            scannedAt: Date(timeIntervalSince1970: 50)
        )
        let legacyData = try makeVersionTwoData(LibraryCatalog(
            folders: ["/tmp/v2"],
            frames: [LibraryFrameRecord(frame: frame)]
        ))
        try legacyData.write(to: catalogURL, options: .atomic)

        guard case let .loaded(migrated, recovered, sourceVersion, _) = LibraryCatalogFile.prepareForUse(
            at: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups
        ) else {
            return XCTFail("v2 catalog should prepare successfully")
        }
        XCTAssertFalse(recovered)
        XCTAssertEqual(sourceVersion, 2)
        XCTAssertEqual(migrated.rolls[0].frameIDs, [frame.id])
        XCTAssertEqual(try Data(contentsOf: LibraryCatalogFile.backupURL(for: catalogURL)), legacyData)
        let generationCount = try backupGenerationCount(in: backups)

        guard case let .loaded(reopened, recoveredAgain, migratedAgain, _) = LibraryCatalogFile.prepareForUse(
            at: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups
        ) else {
            return XCTFail("migrated v5 catalog should reopen")
        }
        XCTAssertFalse(recoveredAgain)
        XCTAssertNil(migratedAgain)
        XCTAssertEqual(reopened.rolls, migrated.rolls)
        XCTAssertEqual(try backupGenerationCount(in: backups), generationCount)
    }

    func testPrepareForUseMigratesVersionThreeOncePreservesRawBytesAndIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-catalog-v3-migration-\(UUID().uuidString)", isDirectory: true)
        let catalogURL = root.appendingPathComponent("library.json")
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let metadata = SourceMetadataSnapshot(
            fileTypeIdentifier: "public.tiff",
            fileSizeBytes: 48_000_000,
            pixelWidth: 6_000,
            pixelHeight: 4_000,
            resolutionDPI: 2_400,
            bitsPerColorSample: 16
        )

        let frame = ScanFrame(
            scanIndex: 3,
            rawScanURL: URL(fileURLWithPath: "/tmp/migrate-v3.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourcePixelWidth: 4_000,
            sourcePixelHeight: 6_000,
            sourceResolutionDPI: 2_400,
            sourceBitDepth: 16,
            sourceMetadata: metadata,
            scannedAt: Date(timeIntervalSince1970: 1_700_200_000)
        )
        let rollID = UUID()
        let roll = try XCTUnwrap(LibraryRoll.physical(
            id: rollID,
            name: "Migrating Roll",
            createdAt: frame.scannedAt,
            filmType: frame.filmType,
            frameIDs: [frame.id]
        ))
        let session = try makeQueuedSession()
        let assignment = LibraryScanRollAssignment(
            sessionID: session.id,
            rollID: rollID,
            draftName: "Migrating Roll",
            filmType: frame.filmType,
            createdAt: session.createdAt
        )
        let legacyData = try makeVersionThreeData(LibraryCatalog(
            folders: ["/tmp"],
            frames: [LibraryFrameRecord(frame: frame)],
            rolls: [roll],
            activeRollID: rollID,
            scanSessions: [session],
            scanRollAssignments: [assignment]
        ))
        try legacyData.write(to: catalogURL, options: .atomic)

        guard case let .loaded(migrated, recovered, sourceVersion, _) = LibraryCatalogFile.prepareForUse(
            at: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups
        ) else {
            return XCTFail("v3 catalog should prepare successfully")
        }
        XCTAssertFalse(recovered)
        XCTAssertEqual(sourceVersion, 3)
        XCTAssertEqual(migrated.version, 6)
        XCTAssertEqual(migrated.minimumReaderVersion, 6)
        XCTAssertEqual(migrated.rolls, [roll])
        XCTAssertEqual(migrated.activeRollID, rollID)
        XCTAssertEqual(migrated.scanSessions, [session])
        XCTAssertEqual(migrated.scanRollAssignments, [assignment])
        XCTAssertNil(migrated.frames.first?.sourceMetadata)
        XCTAssertEqual(
            try Data(contentsOf: LibraryCatalogFile.backupURL(for: catalogURL)),
            legacyData,
            "마이그레이션 직전 v3 원시 바이트를 legacy backup으로 보존해야 합니다"
        )
        guard case let .loaded(onDisk, onDiskVersion) = LibraryCatalogFile.read(
            from: catalogURL
        ) else {
            return XCTFail("migrated v5 primary should be readable")
        }
        XCTAssertEqual(onDiskVersion, 6)
        XCTAssertEqual(onDisk.version, 6)
        XCTAssertNil(onDisk.frames.first?.sourceMetadata)
        XCTAssertNotNil(LibraryBackupStore.latestValidSnapshot(in: backups))

        let migratedPrimaryData = try Data(contentsOf: catalogURL)
        let generationCount = try backupGenerationCount(in: backups)
        guard case let .loaded(reopened, recoveredAgain, migratedAgain, _) =
                LibraryCatalogFile.prepareForUse(
                    at: catalogURL,
                    defectDirectory: defects,
                    backupDirectory: backups
                ) else {
            return XCTFail("migrated v5 catalog should reopen")
        }
        XCTAssertFalse(recoveredAgain)
        XCTAssertNil(migratedAgain)
        XCTAssertEqual(reopened.rolls, migrated.rolls)
        XCTAssertEqual(reopened.scanSessions, migrated.scanSessions)
        XCTAssertEqual(try Data(contentsOf: catalogURL), migratedPrimaryData)
        XCTAssertEqual(try backupGenerationCount(in: backups), generationCount)
        XCTAssertEqual(
            try Data(contentsOf: LibraryCatalogFile.backupURL(for: catalogURL)),
            legacyData
        )
    }

    func testPrepareForUseMigratesVersionFourOncePreservesRawBytesAndIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-catalog-v4-migration-\(UUID().uuidString)", isDirectory: true)
        let catalogURL = root.appendingPathComponent("library.json")
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let metadata = SourceMetadataSnapshot(
            fileTypeIdentifier: "public.tiff",
            fileSizeBytes: 48_000_000,
            pixelWidth: 6_000,
            pixelHeight: 4_000,
            resolutionDPI: 2_400,
            bitsPerColorSample: 16
        )
        let frame = ScanFrame(
            scanIndex: 4,
            rawScanURL: URL(fileURLWithPath: "/offline/migrate-v4.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourcePixelWidth: 6_000,
            sourcePixelHeight: 4_000,
            sourceResolutionDPI: 2_400,
            sourceBitDepth: 16,
            sourceMetadata: metadata,
            scannedAt: Date(timeIntervalSince1970: 1_700_400_000)
        )
        let legacyData = try makeVersionFourData(LibraryCatalog(
            folders: ["/offline"],
            frames: [LibraryFrameRecord(frame: frame)]
        ))
        try legacyData.write(to: catalogURL, options: .atomic)

        guard case let .loaded(migrated, recovered, sourceVersion, _) =
                LibraryCatalogFile.prepareForUse(
                    at: catalogURL,
                    defectDirectory: defects,
                    backupDirectory: backups
                ) else {
            return XCTFail("v4 catalog should prepare successfully")
        }
        XCTAssertFalse(recovered)
        XCTAssertEqual(sourceVersion, 4)
        XCTAssertEqual(migrated.version, 6)
        XCTAssertEqual(migrated.frames.first?.sourceMetadata, frame.sourceMetadata)
        XCTAssertEqual(migrated.frames.first?.userEditTracking.coverage, .legacyUnknown)
        XCTAssertEqual(
            try Data(contentsOf: LibraryCatalogFile.backupURL(for: catalogURL)),
            legacyData
        )
        XCTAssertNotNil(LibraryBackupStore.latestValidSnapshot(in: backups))

        let migratedPrimaryData = try Data(contentsOf: catalogURL)
        let generationCount = try backupGenerationCount(in: backups)
        guard case let .loaded(_, recoveredAgain, migratedAgain, _) =
                LibraryCatalogFile.prepareForUse(
                    at: catalogURL,
                    defectDirectory: defects,
                    backupDirectory: backups
                ) else {
            return XCTFail("migrated v5 catalog should reopen")
        }
        XCTAssertFalse(recoveredAgain)
        XCTAssertNil(migratedAgain)
        XCTAssertEqual(try Data(contentsOf: catalogURL), migratedPrimaryData)
        XCTAssertEqual(try backupGenerationCount(in: backups), generationCount)
        XCTAssertEqual(
            try Data(contentsOf: LibraryCatalogFile.backupURL(for: catalogURL)),
            legacyData
        )
    }

    func testFuturePrimaryDoesNotFallBackToOlderBackupOrChangeBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-future-catalog-\(UUID().uuidString)", isDirectory: true)
        let catalogURL = root.appendingPathComponent("library.json")
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let currentData = try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog(folders: ["/older"])))
        let futureVersion = LibraryCatalog.currentVersion + 1
        let futureData = try rewriteVersion(
            currentData,
            version: futureVersion,
            minimumReaderVersion: futureVersion
        )
        try futureData.write(to: catalogURL, options: .atomic)
        try currentData.write(to: LibraryCatalogFile.backupURL(for: catalogURL), options: .atomic)

        XCTAssertNil(LibraryCatalogFile.load(from: catalogURL))
        XCTAssertEqual(try Data(contentsOf: catalogURL), futureData)
        guard case let .blocked(reason) = LibraryCatalogFile.prepareForUse(
            at: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups
        ) else {
            return XCTFail("future catalog should block startup")
        }
        XCTAssertEqual(reason, .unsupportedVersion(futureVersion))
        XCTAssertEqual(try Data(contentsOf: catalogURL), futureData)
        XCTAssertEqual(
            try Data(contentsOf: LibraryCatalogFile.backupURL(for: catalogURL)),
            currentData
        )
    }

    func testCorruptPrimaryWithoutRecoveryFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-corrupt-catalog-\(UUID().uuidString)", isDirectory: true)
        let catalogURL = root.appendingPathComponent("library.json")
        let broken = Data("{broken".utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try broken.write(to: catalogURL, options: .atomic)

        guard case let .blocked(reason) = LibraryCatalogFile.prepareForUse(
            at: catalogURL,
            defectDirectory: root.appendingPathComponent("defects"),
            backupDirectory: root.appendingPathComponent("Backups")
        ) else {
            return XCTFail("corrupt catalog should block startup")
        }
        XCTAssertEqual(reason, .corrupt)
        XCTAssertEqual(try Data(contentsOf: catalogURL), broken)
    }

    func testMissingCatalogWithAuthoritativeArtifactsIsNotTreatedAsNewLibrary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-missing-catalog-\(UUID().uuidString)", isDirectory: true)
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: defects, withIntermediateDirectories: true)
        try Data([1]).write(to: defects.appendingPathComponent("orphan.plist"))

        guard case let .blocked(reason) = LibraryCatalogFile.prepareForUse(
            at: root.appendingPathComponent("library.json"),
            defectDirectory: defects,
            backupDirectory: root.appendingPathComponent("Backups")
        ) else {
            return XCTFail("orphaned authoritative data should block a new empty catalog")
        }
        XCTAssertEqual(reason, .missingAuthoritativeData)
    }

    func testAppModelLeavesFutureCatalogPersistenceDisabled() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-future-app-model-\(UUID().uuidString)", isDirectory: true)
        let catalogURL = root.appendingPathComponent("library.json")
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let futureVersion = LibraryCatalog.currentVersion + 1
        let currentData = try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog()))
        let futureData = try rewriteVersion(
            currentData,
            version: futureVersion,
            minimumReaderVersion: futureVersion
        )
        try futureData.write(to: catalogURL, options: .atomic)
        let model = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defects,
            libraryBackupDirectoryURL: backups
        )

        await model.restoreLibraryOnLaunch()
        defer {
            model.librarySaveTask?.cancel()
            model.librarySaveTask = nil
        }

        XCTAssertFalse(model.libraryPersistenceEnabled)
        XCTAssertEqual(model.libraryCatalogBlockReason, .unsupportedVersion(futureVersion))
        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        XCTAssertFalse(model.allowsLibraryMutation)
        XCTAssertFalse(model.saveLibrary(synchronous: true))
        XCTAssertEqual(try Data(contentsOf: catalogURL), futureData)
    }

    private func writeTemp(_ data: Data) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-catalog-\(UUID().uuidString).json")
        LibraryCatalogFile.write(data, to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writeTargetURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-catalog-commit-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    private static let legacyFrameFieldKeys: Set<String> = [
        "id",
        "scanIndex",
        "rawScanPath",
        "infraredScanPath",
        "rawScanBookmarkData",
        "infraredScanBookmarkData",
        "sourceKind",
        "storageGroup",
        "sourcePixelWidth",
        "sourcePixelHeight",
        "sourceResolutionDPI",
        "sourceBitDepth",
        "scannedAt",
        "filmType",
        "presetID",
        "params",
        "imageTransform",
        "baseRGB",
        "rating",
        "pickState",
        "customDisplayName",
        "hasDevelopedOnce",
        "developHistory",
        "developSnapshots",
        "sourceFrameID",
        "sourceFrameDisplayName",
        "virtualCopyNumber",
        "cleanedRawPath",
        "cleanedRawEditCount",
        "hasDefectEdits",
    ]

    private static let versionThreeFrameFieldKeys = legacyFrameFieldKeys.union([
        "scanSessionID",
        "scanJobID",
    ])

    private static let versionFourFrameFieldKeys = versionThreeFrameFieldKeys.union([
        "sourceMetadata",
    ])

    private static let versionThreeCatalogFieldKeys: Set<String> = [
        "version",
        "minimumReaderVersion",
        "folders",
        "frames",
        "rolls",
        "activeRollID",
        "scanSessions",
        "scanRollAssignments",
    ]

    private static let versionFourCatalogFieldKeys = versionThreeCatalogFieldKeys

    private func makeVersionFiveData(_ catalog: LibraryCatalog) throws -> Data {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: XCTUnwrap(LibraryCatalogFile.encode(catalog))
            ) as? [String: Any]
        )
        object["version"] = 5
        object["minimumReaderVersion"] = 5
        object.removeValue(forKey: "stacks")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func makeVersionOneData(_ catalog: LibraryCatalog) throws -> Data {
        try makeLegacyData(catalog, version: 1, minimumReaderVersion: nil)
    }

    private func makeVersionTwoData(_ catalog: LibraryCatalog) throws -> Data {
        try makeLegacyData(catalog, version: 2, minimumReaderVersion: 2)
    }

    private func makeVersionThreeData(_ catalog: LibraryCatalog) throws -> Data {
        let current = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: XCTUnwrap(LibraryCatalogFile.encode(catalog))
            ) as? [String: Any]
        )
        let currentFrames = try XCTUnwrap(current["frames"] as? [[String: Any]])
        let versionThreeFrames = currentFrames.map { frame in
            frame.filter { Self.versionThreeFrameFieldKeys.contains($0.key) }
        }
        var versionThree: [String: Any] = [
            "version": 3,
            "minimumReaderVersion": 3,
            "folders": try XCTUnwrap(current["folders"]),
            "frames": versionThreeFrames,
            "rolls": try XCTUnwrap(current["rolls"]),
            "scanSessions": try XCTUnwrap(current["scanSessions"]),
            "scanRollAssignments": try XCTUnwrap(current["scanRollAssignments"]),
        ]
        if let activeRollID = current["activeRollID"] {
            versionThree["activeRollID"] = activeRollID
        }
        return try JSONSerialization.data(
            withJSONObject: versionThree,
            options: [.sortedKeys]
        )
    }

    private func makeVersionFourData(_ catalog: LibraryCatalog) throws -> Data {
        let current = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: XCTUnwrap(LibraryCatalogFile.encode(catalog))
            ) as? [String: Any]
        )
        let currentFrames = try XCTUnwrap(current["frames"] as? [[String: Any]])
        let versionFourFrames = currentFrames.map { frame in
            frame.filter { Self.versionFourFrameFieldKeys.contains($0.key) }
        }
        var versionFour: [String: Any] = [
            "version": 4,
            "minimumReaderVersion": 4,
            "folders": try XCTUnwrap(current["folders"]),
            "frames": versionFourFrames,
            "rolls": try XCTUnwrap(current["rolls"]),
            "scanSessions": try XCTUnwrap(current["scanSessions"]),
            "scanRollAssignments": try XCTUnwrap(current["scanRollAssignments"]),
        ]
        if let activeRollID = current["activeRollID"] {
            versionFour["activeRollID"] = activeRollID
        }
        return try JSONSerialization.data(
            withJSONObject: versionFour,
            options: [.sortedKeys]
        )
    }

    private func makeLegacyData(
        _ catalog: LibraryCatalog,
        version: Int,
        minimumReaderVersion: Int?
    ) throws -> Data {
        let current = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: XCTUnwrap(LibraryCatalogFile.encode(catalog))
            ) as? [String: Any]
        )
        let currentFrames = try XCTUnwrap(current["frames"] as? [[String: Any]])
        let legacyFrames = currentFrames.map { frame in
            frame.filter { Self.legacyFrameFieldKeys.contains($0.key) }
        }
        var legacy: [String: Any] = [
            "version": version,
            "folders": try XCTUnwrap(current["folders"]),
            "frames": legacyFrames,
        ]
        if let minimumReaderVersion {
            legacy["minimumReaderVersion"] = minimumReaderVersion
        }
        return try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
    }

    private func makeFullyPopulatedVersionThreeCatalog() throws -> LibraryCatalog {
        let frameID = UUID()
        let sourceFrameID = UUID()
        let sessionID = UUID()
        let jobID = UUID()
        let rollID = UUID()
        let scannedAt = Date(timeIntervalSince1970: 1_700_300_000)
        let transform = ImageTransform(
            rotation: .deg90,
            flipHorizontal: true,
            flipVertical: true,
            cropRect: SIMD4(0.1, 0.2, 0.7, 0.6),
            straightenAngle: 1.25,
            cropAspect: 1.5
        )
        var params = DevelopParameters()
        params.exposure = 0.75
        params.contrast = 0.2
        params.imageTransform = transform
        let history = DevelopHistoryEntry(
            id: UUID(),
            label: "v3 history",
            createdAt: scannedAt.addingTimeInterval(10),
            params: params,
            presetID: "preset-v3"
        )
        let snapshot = DevelopSnapshot(
            id: UUID(),
            name: "v3 snapshot",
            createdAt: scannedAt.addingTimeInterval(20),
            params: params,
            presetID: "preset-v3"
        )
        let record = LibraryFrameRecord(
            id: frameID,
            scanIndex: 17,
            rawScanPath: "/archive/v3/raw-017.tiff",
            infraredScanPath: "/archive/v3/ir-017.tiff",
            rawScanBookmarkData: Data([0x01, 0x02, 0x03]),
            infraredScanBookmarkData: Data([0x04, 0x05, 0x06]),
            sourceKind: FrameSource.scannerTIFF.storageKey,
            storageGroup: "V3 Roll",
            sourcePixelWidth: 6_400,
            sourcePixelHeight: 4_200,
            sourceResolutionDPI: 3_600,
            sourceBitDepth: 16,
            sourceMetadata: makeSourceMetadataSnapshot(),
            scanSessionID: sessionID,
            scanJobID: jobID,
            scannedAt: scannedAt,
            filmType: .colorNegative,
            presetID: "preset-v3",
            params: params,
            imageTransform: transform,
            baseRGB: [0.81, 0.62, 0.43],
            rating: 5,
            pickState: .picked,
            customDisplayName: "Frame 17",
            hasDevelopedOnce: true,
            developHistory: [history],
            developSnapshots: [snapshot],
            sourceFrameID: sourceFrameID,
            sourceFrameDisplayName: "Source Frame",
            virtualCopyNumber: 2,
            cleanedRawPath: "/cache/v3/cleaned-017.tiff",
            cleanedRawEditCount: 7,
            hasDefectEdits: true
        )
        let roll = try XCTUnwrap(LibraryRoll.physical(
            id: rollID,
            name: "V3 Roll",
            createdAt: scannedAt,
            filmType: .colorNegative,
            frameIDs: [frameID]
        ))
        let session = try makeQueuedSession(id: sessionID, jobID: jobID)
        let assignment = LibraryScanRollAssignment(
            sessionID: sessionID,
            rollID: rollID,
            draftName: "V3 Roll",
            filmType: .colorNegative,
            createdAt: session.createdAt
        )
        return LibraryCatalog(
            folders: ["/archive/v3"],
            frames: [record],
            rolls: [roll],
            activeRollID: rollID,
            scanSessions: [session],
            scanRollAssignments: [assignment]
        )
    }

    private func makeSourceMetadataSnapshot() -> SourceMetadataSnapshot {
        SourceMetadataSnapshot(
            version: SourceMetadataSnapshot.currentVersion,
            fileTypeIdentifier: "public.tiff",
            fileSizeBytes: 48_000_000,
            imageIndex: 0,
            imageCount: 1,
            pixelWidth: 6_000,
            pixelHeight: 4_000,
            dpiWidth: 2_400,
            dpiHeight: 2_400,
            resolutionDPI: 2_400,
            bitsPerColorSample: 16,
            orientation: 1,
            colorModel: "RGB",
            colorProfileName: "Adobe RGB (1998)",
            namedColorSpace: "Adobe RGB (1998)",
            exif: SourceEXIFMetadata(
                dateTimeOriginalRaw: "2024:02:29 10:20:30",
                offsetTimeOriginalRaw: "+09:00",
                subsecondTimeOriginalRaw: "125",
                cameraMake: "Nikon",
                cameraModel: "F3",
                lensModel: "NIKKOR 50mm f/1.4",
                exposureTimeSeconds: 0.008,
                fNumber: 5.6,
                isoSpeedRatings: [100, 200],
                focalLengthMM: 50
            ),
            iptc: SourceIPTCMetadata(
                title: "Archive title",
                headline: "Archive headline",
                caption: "Archive caption",
                creators: ["Photographer"],
                credit: "Archive credit",
                copyrightNotice: "Copyright 2024",
                rightsUsageTerms: "Editorial use",
                source: "Film archive",
                jobIdentifier: "JOB-42",
                keywords: ["film", "negative"],
                city: "Seoul",
                stateProvince: "Seoul",
                country: "South Korea",
                countryCode: "KOR",
                sublocation: "Jongno"
            ),
            imageMetadataXMPView: SourceXMPMetadata(
                createDateRaw: "2024-02-29T10:20:30+09:00",
                dateCreatedRaw: "2024-02-29T10:20:30+09:00",
                title: SourceLocalizedText(valuesByLanguage: [
                    "en-US": "Image title",
                    "x-default": "Image title",
                ]),
                description: SourceLocalizedText(valuesByLanguage: [
                    "x-default": "Image description",
                ]),
                creators: ["Image creator"],
                rights: SourceLocalizedText(valuesByLanguage: [
                    "x-default": "Image rights",
                ]),
                usageTerms: SourceLocalizedText(valuesByLanguage: [
                    "x-default": "Image usage",
                ]),
                headline: "Image headline",
                credit: "Image credit",
                jobIdentifier: "IMAGE-42",
                keywords: ["image-xmp"],
                city: "Seoul",
                stateProvince: "Seoul",
                country: "South Korea",
                sublocation: "Jongno",
                rating: 4.5,
                label: "Green"
            ),
            sidecarXMP: SourceXMPMetadata(
                createDateRaw: "2024-03-01T08:00:00Z",
                dateCreatedRaw: "2024-02-29T10:20:30+09:00",
                title: SourceLocalizedText(valuesByLanguage: [
                    "ko-KR": "사이드카 제목",
                    "x-default": "Sidecar title",
                ]),
                description: SourceLocalizedText(valuesByLanguage: [
                    "x-default": "Sidecar description",
                ]),
                creators: ["Sidecar creator"],
                rights: SourceLocalizedText(valuesByLanguage: [
                    "x-default": "Sidecar rights",
                ]),
                usageTerms: SourceLocalizedText(valuesByLanguage: [
                    "x-default": "Sidecar usage",
                ]),
                headline: "Sidecar headline",
                credit: "Sidecar credit",
                jobIdentifier: "SIDECAR-42",
                keywords: ["sidecar", "catalog"],
                city: "Busan",
                stateProvince: "Busan",
                country: "South Korea",
                sublocation: "Haeundae",
                rating: -1,
                label: "Red"
            ),
            sidecarXMPState: .loaded,
            containsStandardGPSMetadata: true,
            discardedOversizedValues: true,
            discardedInvalidValues: true
        )
    }

    private func rewriteVersion(
        _ data: Data,
        version: Int,
        minimumReaderVersion: Int?
    ) throws -> Data {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["version"] = version
        object["minimumReaderVersion"] = minimumReaderVersion
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func jsonObject(_ data: Data) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private func backupGenerationCount(in directory: URL) throws -> Int {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.lastPathComponent.hasPrefix("backup-") }.count
    }

    private func makeQueuedSession(
        id: UUID = UUID(),
        jobID: UUID = UUID()
    ) throws -> ScanSession {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let scannerID = "plugin:test-plugin:device-1"
        var options = ScanOptions.strongDefault(scannerID: scannerID)
        options.requestID = jobID
        options.temporaryOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-job-\(jobID.uuidString).tiff")
        let job = try ScanJob(
            id: jobID,
            sessionID: id,
            ordinal: 1,
            kind: .full,
            requestedOptions: options,
            framePublication: try ScanFramePublicationSnapshot(
                frameID: jobID,
                scanIndex: 1,
                initialTransform: .identity,
                developTarget: .main,
                storageGroupName: "TestScanner"
            ),
            createdAt: createdAt
        )
        return try ScanSession(
            id: id,
            createdAt: createdAt,
            device: ScannerDescriptor(
                id: scannerID,
                displayName: "Test Scanner",
                vendor: "Test Vendor",
                model: "Test Model",
                backendType: .plugin
            ),
            backend: ScanBackendSnapshot(
                type: .plugin,
                identifier: "external-json",
                pluginIdentifier: "test-plugin"
            ),
            environment: ScanEnvironmentSnapshot(
                applicationName: "negaflow",
                applicationVersion: "1.0",
                operatingSystem: "macOS",
                operatingSystemVersion: "15.0",
                architecture: "arm64"
            ),
            jobs: [job]
        )
    }
}
