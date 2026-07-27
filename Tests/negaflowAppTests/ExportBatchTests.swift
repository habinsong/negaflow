import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class ExportBatchTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-batch-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try await super.tearDown()
    }

    func testPlannerPreservesInteractionOrderAndResolvesArtifactCollisions() async throws {
        let (model, first, second) = try await makeReadyModel()
        first.customDisplayName = "shared-name"
        second.customDisplayName = "shared-name"
        model.updateInteractionScope([second.id, first.id])
        model.selectedFrameIDs = [first.id, second.id]

        let plans = model.makeExportBatchPlans(
            frames: model.exportSelection,
            root: temporaryDirectory.appendingPathComponent("Exports"),
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: true,
            writeOriginalRaw: true,
            options: .standard
        )

        XCTAssertEqual(plans.map { $0.frame.id }, [second.id, first.id])
        XCTAssertEqual(plans.map { $0.outputURL.lastPathComponent }, [
            "shared-name.jpg",
            "shared-name-1.jpg",
        ])
        let artifactPaths = plans.flatMap { plan in
            ExportArtifactLayout(
                outputURL: plan.outputURL,
                format: plan.format,
                sourceURL: plan.frame.rawScanURL,
                writeSidecar: plan.writeSidecar,
                writeMainFlatMaster: plan.writeMainFlatMaster,
                writeOriginalRaw: plan.writeOriginalRaw
            ).standardizedPaths
        }
        XCTAssertEqual(Set(artifactPaths).count, artifactPaths.count)
    }

    func testSchedulerNeverExceedsConfiguredConcurrency() async {
        var activeCount = 0
        var peakCount = 0

        await ExportBatchScheduler.run(Array(0..<6), maximumConcurrent: 2) { _ in
            activeCount += 1
            peakCount = max(peakCount, activeCount)
            try? await Task.sleep(nanoseconds: 20_000_000)
            activeCount -= 1
        }

        XCTAssertEqual(peakCount, 2)
        XCTAssertEqual(activeCount, 0)
    }

    func testCheckpointReadDistinguishesMissingDecodeValidationAndPermission() async throws {
        let missingURL = temporaryDirectory.appendingPathComponent("missing-checkpoint.json")
        XCTAssertThrowsError(try ExportBatchCheckpoint.read(from: missingURL)) { error in
            XCTAssertEqual(error as? ExportBatchCheckpoint.LoadError, .fileNotFound)
        }

        let malformedURL = temporaryDirectory.appendingPathComponent("malformed-checkpoint.json")
        try Data("{".utf8).write(to: malformedURL)
        XCTAssertThrowsError(try ExportBatchCheckpoint.read(from: malformedURL)) { error in
            XCTAssertEqual(error as? ExportBatchCheckpoint.LoadError, .decodingFailed)
        }

        let (model, first, _) = try await makeReadyModel()
        _ = persistCheckpoint(
            model: model,
            frame: first,
            printerOutputProfile: try ICCOutputProfileTestFixture.snapshot()
        )
        var root = try checkpointJSONObject(at: model.exportBatchCheckpointURL)
        root["version"] = ExportBatchCheckpoint.currentVersion + 1
        try writeCheckpointJSONObject(root, to: model.exportBatchCheckpointURL)
        XCTAssertThrowsError(
            try ExportBatchCheckpoint.read(from: model.exportBatchCheckpointURL)
        ) { error in
            XCTAssertEqual(error as? ExportBatchCheckpoint.LoadError, .validationFailed)
        }

        XCTAssertEqual(
            ExportBatchCheckpoint.loadError(
                for: NSError(
                    domain: NSCocoaErrorDomain,
                    code: CocoaError.Code.fileReadNoPermission.rawValue
                )
            ),
            .permissionDenied
        )
        XCTAssertEqual(
            ExportBatchCheckpoint.loadError(
                for: NSError(domain: NSCocoaErrorDomain, code: Int.max)
            ),
            .readFailed
        )
    }

    func testBatchExportUsesEachFrameSourceAndRecipe() async throws {
        let (model, first, second) = try await makeReadyModel()
        first.updateParams { $0.exposure = -0.25 }
        second.updateParams { $0.exposure = 0.5 }
        _ = LibraryFrameRecord(frame: first)
        _ = LibraryFrameRecord(frame: second)
        first.hasDevelopedOnce = true
        second.hasDevelopedOnce = true
        model.updateInteractionScope([first.id, second.id])
        model.selectedFrameIDs = [first.id, second.id]
        XCTAssertTrue(model.saveLibrary(synchronous: true))

        let plans = model.makeExportBatchPlans(
            frames: model.exportSelection,
            root: temporaryDirectory.appendingPathComponent("Exports"),
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard
        )
        model.exportBatchStore.begin(plans)
        await model.runExportBatch(plans, maximumConcurrent: 2)

        XCTAssertFalse(model.exportBatchStore.isRunning)
        XCTAssertEqual(model.exportBatchStore.completedCount, 2)
        XCTAssertEqual(model.exportBatchStore.failedCount, 0)
        XCTAssertTrue(plans.allSatisfy { FileManager.default.fileExists(atPath: $0.outputURL.path) })

        for frame in [first, second] {
            let event = try XCTUnwrap(
                frame.libraryWorkflowTrackingState?.exportTracking.successfulEvents.last
            )
            XCTAssertEqual(event.sourceIdentity, try RenderManifest.sourceIdentity(for: frame.rawScanURL))
            XCTAssertEqual(event.developRecipeSHA256, frame.currentLibraryDevelopRecipeSHA256())
        }
    }

    func testCheckpointRoundTripPreservesPrinterOutputProfileBytesNameAndSHA() async throws {
        let (model, first, _) = try await makeReadyModel()
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let plan = persistCheckpoint(
            model: model,
            frame: first,
            printerOutputProfile: profile
        )

        let checkpoint = try XCTUnwrap(
            ExportBatchCheckpoint.load(from: model.exportBatchCheckpointURL)
        )
        XCTAssertEqual(checkpoint.version, ExportBatchCheckpoint.currentVersion)
        let storedProfile = try XCTUnwrap(checkpoint.printerOutputProfiles?.only)
        XCTAssertEqual(storedProfile.profileName, profile.profileName)
        XCTAssertEqual(storedProfile.profileSHA256, profile.profileSHA256)
        XCTAssertEqual(storedProfile.iccProfileData, profile.iccProfileData)
        XCTAssertEqual(checkpoint.items.only?.printerOutputProfileSHA256, profile.profileSHA256)

        let restoredModel = makeRestoredModel(frame: first, sourceModel: model)
        restoredModel.restoreExportBatchCheckpoint()

        let restoredPlan = try XCTUnwrap(restoredModel.activeExportBatchPlans.only)
        let restoredProfile = try XCTUnwrap(restoredPlan.printerOutputProfile)
        XCTAssertEqual(restoredPlan.id, plan.id)
        XCTAssertEqual(restoredProfile.profileName, profile.profileName)
        XCTAssertEqual(restoredProfile.profileSHA256, profile.profileSHA256)
        XCTAssertEqual(restoredProfile.iccProfileData, profile.iccProfileData)
    }

    func testCheckpointRejectsTamperedPrinterOutputProfileSHA() async throws {
        let (model, first, _) = try await makeReadyModel()
        let profile = try ICCOutputProfileTestFixture.snapshot()
        _ = persistCheckpoint(
            model: model,
            frame: first,
            printerOutputProfile: profile
        )
        try tamperCheckpointPrinterOutputProfileSHA(at: model.exportBatchCheckpointURL)

        XCTAssertNil(ExportBatchCheckpoint.load(from: model.exportBatchCheckpointURL))
        let restoredModel = makeRestoredModel(frame: first, sourceModel: model)
        restoredModel.restoreExportBatchCheckpoint()
        XCTAssertTrue(restoredModel.activeExportBatchPlans.isEmpty)
        XCTAssertTrue(restoredModel.exportBatchStore.items.isEmpty)
    }

    func testCheckpointRejectsTamperedPrinterOutputProfileBytes() async throws {
        let (model, first, _) = try await makeReadyModel()
        let profile = try ICCOutputProfileTestFixture.snapshot()
        _ = persistCheckpoint(
            model: model,
            frame: first,
            printerOutputProfile: profile
        )
        try tamperCheckpointPrinterOutputProfileBytes(at: model.exportBatchCheckpointURL)

        XCTAssertNil(ExportBatchCheckpoint.load(from: model.exportBatchCheckpointURL))
        let restoredModel = makeRestoredModel(frame: first, sourceModel: model)
        restoredModel.restoreExportBatchCheckpoint()
        XCTAssertTrue(restoredModel.activeExportBatchPlans.isEmpty)
        XCTAssertTrue(restoredModel.exportBatchStore.items.isEmpty)
    }

    func testVersionOneCheckpointWithoutPrinterProfileFieldsStillRestores() async throws {
        let (model, first, _) = try await makeReadyModel()
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let originalPlan = persistCheckpoint(
            model: model,
            frame: first,
            printerOutputProfile: profile
        )
        var root = try checkpointJSONObject(at: model.exportBatchCheckpointURL)
        root["version"] = 1
        root.removeValue(forKey: "printerOutputProfiles")
        var items = try XCTUnwrap(root["items"] as? [[String: Any]])
        items[0].removeValue(forKey: "printerOutputProfileSHA256")
        root["items"] = items
        try writeCheckpointJSONObject(root, to: model.exportBatchCheckpointURL)

        let loaded = try XCTUnwrap(
            ExportBatchCheckpoint.load(from: model.exportBatchCheckpointURL)
        )
        XCTAssertEqual(loaded.version, 1)
        XCTAssertNil(loaded.printerOutputProfiles)
        XCTAssertNil(loaded.items.only?.printerOutputProfileSHA256)

        let restoredModel = makeRestoredModel(frame: first, sourceModel: model)
        restoredModel.restoreExportBatchCheckpoint()

        let restoredPlan = try XCTUnwrap(restoredModel.activeExportBatchPlans.only)
        XCTAssertEqual(restoredPlan.id, originalPlan.id)
        XCTAssertNil(restoredPlan.printerOutputProfile)
    }

    func testVersionOnePrintCheckpointWithoutPrinterProfileDoesNotRestore() async throws {
        let (model, first, _) = try await makeReadyModel()
        first.updateParams { $0.developTarget = .print }
        let profile = try ICCOutputProfileTestFixture.snapshot()
        _ = persistCheckpoint(
            model: model,
            frame: first,
            printerOutputProfile: profile
        )
        var root = try checkpointJSONObject(at: model.exportBatchCheckpointURL)
        root["version"] = 1
        root.removeValue(forKey: "printerOutputProfiles")
        var items = try XCTUnwrap(root["items"] as? [[String: Any]])
        items[0].removeValue(forKey: "printerOutputProfileSHA256")
        root["items"] = items
        try writeCheckpointJSONObject(root, to: model.exportBatchCheckpointURL)

        let loaded = try XCTUnwrap(
            ExportBatchCheckpoint.load(from: model.exportBatchCheckpointURL)
        )
        XCTAssertEqual(loaded.version, 1)
        XCTAssertNil(loaded.printerOutputProfiles)
        XCTAssertNil(loaded.items.only?.printerOutputProfileSHA256)

        let restoredModel = makeRestoredModel(frame: first, sourceModel: model)
        restoredModel.restoreExportBatchCheckpoint()

        XCTAssertTrue(restoredModel.activeExportBatchPlans.isEmpty)
        XCTAssertTrue(restoredModel.exportBatchStore.items.isEmpty)
    }

    func testCheckpointDoesNotOverwriteExistingPlansWhenOneOfMultipleItemsCannotRestore() async throws {
        let (model, first, second) = try await makeReadyModel()
        let checkpointPlans = model.makeExportBatchPlans(
            frames: [first, second],
            root: temporaryDirectory.appendingPathComponent("CheckpointExports"),
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard
        )
        model.activeExportBatchPlans = checkpointPlans
        model.exportBatchStore.begin(checkpointPlans)
        model.persistExportBatchCheckpoint()

        var root = try checkpointJSONObject(at: model.exportBatchCheckpointURL)
        var items = try XCTUnwrap(root["items"] as? [[String: Any]])
        items[1]["format"] = "invalid-format"
        root["items"] = items
        try writeCheckpointJSONObject(root, to: model.exportBatchCheckpointURL)
        let checkpointDataBeforeRestore = try Data(contentsOf: model.exportBatchCheckpointURL)
        XCTAssertEqual(
            ExportBatchCheckpoint.load(from: model.exportBatchCheckpointURL)?.items.count,
            2
        )

        let restoredModel = makeRestoredModel(
            frames: [first, second],
            sourceModel: model
        )
        let existingPlan = restoredModel.makeExportBatchPlans(
            frames: [first],
            root: temporaryDirectory.appendingPathComponent("ExistingExports"),
            format: .tiff16,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard
        )[0]
        restoredModel.activeExportBatchPlans = [existingPlan]
        restoredModel.exportBatchStore.begin([existingPlan])

        restoredModel.restoreExportBatchCheckpoint()

        XCTAssertEqual(restoredModel.activeExportBatchPlans.map(\.id), [existingPlan.id])
        XCTAssertEqual(restoredModel.exportBatchStore.items.map(\.id), [existingPlan.id])
        XCTAssertEqual(restoredModel.exportBatchStore.state(for: existingPlan.id), .queued)
        XCTAssertNil(restoredModel.exportBatchStore.state(for: checkpointPlans[0].id))
        XCTAssertTrue(restoredModel.exportBatchStore.isRunning)
        XCTAssertEqual(
            try Data(contentsOf: model.exportBatchCheckpointURL),
            checkpointDataBeforeRestore
        )
        XCTAssertEqual(
            restoredModel.statusMessage,
            restoredModel.text(
                AppLocalizedPhrase.exportFailedFormat,
                "checkpoint-unrestorable"
            )
        )
    }

    func testCheckpointPersistenceRejectsPartialStoreWithoutReplacingDurableFile() async throws {
        let (model, first, second) = try await makeReadyModel()
        let plans = model.makeExportBatchPlans(
            frames: [first, second],
            root: temporaryDirectory.appendingPathComponent("CheckpointExports"),
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard
        )
        model.activeExportBatchPlans = plans
        model.exportBatchStore.begin(plans)
        XCTAssertTrue(model.persistExportBatchCheckpoint())
        let durableData = try Data(contentsOf: model.exportBatchCheckpointURL)

        model.exportBatchStore.begin([plans[0]])
        XCTAssertFalse(model.persistExportBatchCheckpoint())

        XCTAssertEqual(try Data(contentsOf: model.exportBatchCheckpointURL), durableData)
        XCTAssertEqual(
            model.statusMessage,
            model.text(AppLocalizedPhrase.exportFailedFormat, "checkpoint-state")
        )
    }

    func testBatchDoesNotStartWhenInitialCheckpointCannotBeWritten() async throws {
        let (model, first, _) = try await makeReadyModel()
        first.hasDevelopedOnce = true
        model.updateInteractionScope([first.id])
        model.selectedFrameIDs = [first.id]
        let previousPlan = model.makeExportBatchPlans(
            frames: [first],
            root: temporaryDirectory.appendingPathComponent("PreviousExports"),
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard
        )[0]
        model.activeExportBatchPlans = [previousPlan]
        model.exportBatchStore.begin([previousPlan])
        model.exportBatchStore.finish()
        let checkpointDirectory = model.exportBatchCheckpointURL.deletingLastPathComponent()
        let blocker = Data("not-a-directory".utf8)
        try blocker.write(to: checkpointDirectory)
        let outputRoot = temporaryDirectory.appendingPathComponent("BlockedExports")

        model.startExportBatch(
            root: outputRoot,
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            namingTemplate: ExportNamingTemplate.defaultPattern,
            recipeIdentity: nil
        )

        XCTAssertFalse(model.exportBatchStore.isRunning)
        XCTAssertEqual(model.exportBatchStore.items.map(\.id), [previousPlan.id])
        XCTAssertEqual(model.exportBatchStore.state(for: previousPlan.id), .queued)
        XCTAssertEqual(model.activeExportBatchPlans.map(\.id), [previousPlan.id])
        XCTAssertEqual(try Data(contentsOf: checkpointDirectory), blocker)
        XCTAssertEqual(
            model.statusMessage,
            model.text(AppLocalizedPhrase.exportFailedFormat, "checkpoint-save")
        )
    }

    func testTransientCheckpointFailureIsNotHiddenByLaterSuccessfulWrites() async throws {
        let (model, first, _) = try await makeReadyModel()
        first.hasDevelopedOnce = true
        try MockScannerBackend.writeSyntheticNegative(
            width: 2_048,
            height: 1_536,
            to: first.rawScanURL
        )
        let plan = model.makeExportBatchPlans(
            frames: [first],
            root: temporaryDirectory.appendingPathComponent("TransientFailureExports"),
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard
        )[0]
        model.activeExportBatchPlans = [plan]
        model.exportBatchStore.begin([plan])
        XCTAssertTrue(model.persistExportBatchCheckpoint())
        model.exportBatchStore.requestPause()

        let checkpointDirectory = model.exportBatchCheckpointURL.deletingLastPathComponent()
        try FileManager.default.removeItem(at: checkpointDirectory)
        try Data("not-a-directory".utf8).write(to: checkpointDirectory)
        let task = Task { @MainActor in
            await model.runExportBatch([plan], maximumConcurrent: 1)
        }
        model.exportBatchStore.resume()

        for _ in 0..<1_000 {
            if model.exportBatchStore.state(for: plan.id) == .running { break }
            await Task.yield()
        }
        XCTAssertEqual(model.exportBatchStore.state(for: plan.id), .running)
        try FileManager.default.removeItem(at: checkpointDirectory)
        try FileManager.default.createDirectory(
            at: checkpointDirectory,
            withIntermediateDirectories: true
        )
        await task.value

        XCTAssertEqual(model.exportBatchStore.state(for: plan.id), .succeeded)
        // 재시도할 항목이 없으니 기록은 남기지 않지만, 중간 실패는 상태 메시지로 남아야 한다.
        XCTAssertNil(ExportBatchCheckpoint.load(from: model.exportBatchCheckpointURL))
        XCTAssertEqual(
            model.statusMessage,
            model.text(AppLocalizedPhrase.exportFailedFormat, "checkpoint-save")
        )
    }

    func testRunningCheckpointReconcilesCommittedCatalogEventWithoutDuplicateOutput() async throws {
        let (model, first, _) = try await makeReadyModel()
        first.hasDevelopedOnce = true
        let plan = model.makeExportBatchPlans(
            frames: [first],
            root: temporaryDirectory.appendingPathComponent("CommittedExports"),
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard
        )[0]
        model.activeExportBatchPlans = [plan]
        model.exportBatchStore.begin([plan])
        await model.runExportBatch([plan], maximumConcurrent: 1)
        XCTAssertEqual(model.exportBatchStore.state(for: plan.id), .succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.outputURL.path))

        // 카탈로그 커밋 직후, 다음 체크포인트 기록 전에 프로세스가 멈춘 상황을 재현한다.
        model.exportBatchStore.markRunning(plan.id)
        XCTAssertTrue(model.persistExportBatchCheckpoint())
        XCTAssertEqual(
            ExportBatchCheckpoint.load(from: model.exportBatchCheckpointURL)?.items.only?.state,
            .running
        )

        let restoredModel = makeRestoredModel(frame: first, sourceModel: model)
        restoredModel.restoreExportBatchCheckpoint()

        let restoredPlan = try XCTUnwrap(restoredModel.activeExportBatchPlans.only)
        XCTAssertEqual(restoredPlan.id, plan.id)
        XCTAssertEqual(restoredPlan.outputURL.standardizedFileURL, plan.outputURL.standardizedFileURL)
        XCTAssertEqual(restoredModel.exportBatchStore.state(for: plan.id), .succeeded)
        XCTAssertEqual(restoredModel.exportBatchStore.completedCount, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: plan.outputURL.deletingPathExtension().path + "-1.jpg"
            )
        )
    }

    func testFullySucceededBatchLeavesNoCheckpointBehind() async throws {
        let (model, first, _) = try await makeReadyModel()
        first.hasDevelopedOnce = true
        let plan = model.makeExportBatchPlans(
            frames: [first],
            root: temporaryDirectory.appendingPathComponent("FinishedExports"),
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard
        )[0]
        model.activeExportBatchPlans = [plan]
        model.exportBatchStore.begin([plan])

        await model.runExportBatch([plan], maximumConcurrent: 1)

        XCTAssertEqual(model.exportBatchStore.state(for: plan.id), .succeeded)
        XCTAssertTrue(model.exportBatchStore.retryableItemIDs.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: model.exportBatchCheckpointURL.path)
        )
    }

    func testSucceededCheckpointForDeletedFrameIsDiscardedWithoutReportingFailure() async throws {
        let (model, first, _) = try await makeReadyModel()
        let plan = persistCheckpoint(
            model: model,
            frame: first,
            printerOutputProfile: try ICCOutputProfileTestFixture.snapshot()
        )
        model.exportBatchStore.markFinished(
            plan.id,
            result: .completed(outputURL: plan.outputURL, pairedURLs: [])
        )
        XCTAssertTrue(model.persistExportBatchCheckpoint())

        // 프레임이 라이브러리에서 지워진 뒤 앱을 다시 여는 상황이다.
        let restoredModel = makeRestoredModel(frames: [], sourceModel: model)
        let statusBeforeRestore = restoredModel.statusMessage

        restoredModel.restoreExportBatchCheckpoint()

        XCTAssertTrue(restoredModel.activeExportBatchPlans.isEmpty)
        XCTAssertTrue(restoredModel.exportBatchStore.items.isEmpty)
        XCTAssertEqual(restoredModel.statusMessage, statusBeforeRestore)
        XCTAssertNotEqual(
            restoredModel.statusMessage,
            restoredModel.text(AppLocalizedPhrase.exportFailedFormat, "checkpoint-unrestorable")
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: model.exportBatchCheckpointURL.path)
        )
    }

    private func makeReadyModel() async throws -> (AppModel, ScanFrame, ScanFrame) {
        let model = AppModel(
            libraryCatalogURL: temporaryDirectory.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: temporaryDirectory.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: temporaryDirectory.appendingPathComponent("Backups")
        )
        await model.restoreLibraryOnLaunch()
        let first = try makeFrame(index: 1)
        let second = try makeFrame(index: 2)
        model.frames = [first, second]
        XCTAssertTrue(model.assignNewPersistentFrames([first, second]))
        return (model, first, second)
    }

    private func persistCheckpoint(
        model: AppModel,
        frame: ScanFrame,
        printerOutputProfile: ICCOutputProfileSnapshot
    ) -> ExportBatchPlan {
        let plan = model.makeExportBatchPlans(
            frames: [frame],
            root: temporaryDirectory.appendingPathComponent("CheckpointExports"),
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            printerOutputProfile: printerOutputProfile
        )[0]
        model.activeExportBatchPlans = [plan]
        model.exportBatchStore.begin([plan])
        model.persistExportBatchCheckpoint()
        return plan
    }

    private func makeRestoredModel(frame: ScanFrame, sourceModel: AppModel) -> AppModel {
        makeRestoredModel(frames: [frame], sourceModel: sourceModel)
    }

    private func makeRestoredModel(frames: [ScanFrame], sourceModel: AppModel) -> AppModel {
        let model = AppModel(
            libraryCatalogURL: sourceModel.libraryCatalogURL,
            libraryDefectDirectoryURL: temporaryDirectory.appendingPathComponent("restored-defects"),
            libraryBackupDirectoryURL: temporaryDirectory.appendingPathComponent("restored-backups")
        )
        model.frames = frames
        return model
    }

    private func tamperCheckpointPrinterOutputProfileSHA(at url: URL) throws {
        var root = try checkpointJSONObject(at: url)
        var profiles = try XCTUnwrap(root["printerOutputProfiles"] as? [[String: Any]])
        var items = try XCTUnwrap(root["items"] as? [[String: Any]])
        let tamperedSHA256 = String(repeating: "0", count: 64)
        profiles[0]["profileSHA256"] = tamperedSHA256
        items[0]["printerOutputProfileSHA256"] = tamperedSHA256
        root["printerOutputProfiles"] = profiles
        root["items"] = items
        try writeCheckpointJSONObject(root, to: url)
    }

    private func tamperCheckpointPrinterOutputProfileBytes(at url: URL) throws {
        var root = try checkpointJSONObject(at: url)
        var profiles = try XCTUnwrap(root["printerOutputProfiles"] as? [[String: Any]])
        let encodedProfile = try XCTUnwrap(profiles[0]["iccProfileData"] as? String)
        var profileData = try XCTUnwrap(Data(base64Encoded: encodedProfile))
        let lastIndex = try XCTUnwrap(profileData.indices.last)
        profileData[lastIndex] ^= 0x01
        profiles[0]["iccProfileData"] = profileData.base64EncodedString()
        root["printerOutputProfiles"] = profiles
        try writeCheckpointJSONObject(root, to: url)
    }

    private func checkpointJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func writeCheckpointJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func makeFrame(index: Int) throws -> ScanFrame {
        let sourceURL = temporaryDirectory.appendingPathComponent("source-\(index).tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: sourceURL)
        let frame = ScanFrame(
            scanIndex: index,
            rawScanURL: sourceURL,
            filmType: .colorPositive
        )
        _ = LibraryFrameRecord(frame: frame)
        return frame
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
