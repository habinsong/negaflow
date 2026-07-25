import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class ExportBatchControlTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-batch-control-\(UUID().uuidString)",
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

    func testPauseBlocksNewSchedulingUntilResume() async throws {
        let (model, plan) = try makeModelAndPlan()
        model.exportBatchStore.begin([plan])
        model.exportBatchStore.requestPause()
        var permissionWasGranted = false
        let waiter = Task { @MainActor in
            permissionWasGranted = await model.exportBatchStore.awaitSchedulingPermission()
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(permissionWasGranted)
        model.exportBatchStore.resume()
        await waiter.value
        XCTAssertTrue(permissionWasGranted)
    }

    func testCancellationAndRetryOnlyResetRetryableItems() throws {
        let (model, firstPlan) = try makeModelAndPlan(index: 1)
        let secondFrame = try makeFrame(index: 2)
        model.frames.append(secondFrame)
        let secondPlan = model.makeExportBatchPlans(
            frames: [secondFrame],
            root: temporaryDirectory.appendingPathComponent("Exports-2"),
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard
        )[0]
        model.exportBatchStore.begin([firstPlan, secondPlan])
        model.exportBatchStore.markRunning(firstPlan.id)
        model.exportBatchStore.requestCancellation()

        XCTAssertEqual(model.exportBatchStore.state(for: firstPlan.id), .running)
        XCTAssertEqual(model.exportBatchStore.state(for: secondPlan.id), .cancelled)
        model.exportBatchStore.markFinished(
            firstPlan.id,
            result: .failed(message: "fixture failure")
        )
        model.exportBatchStore.finish()
        let retryable = model.exportBatchStore.retryableItemIDs
        XCTAssertEqual(retryable, [firstPlan.id, secondPlan.id])

        model.exportBatchStore.prepareRetry(retryable)
        XCTAssertEqual(model.exportBatchStore.state(for: firstPlan.id), .queued)
        XCTAssertEqual(model.exportBatchStore.state(for: secondPlan.id), .queued)
    }

    func testCheckpointRoundTripRestoresInterruptedWorkWithoutOverwritingCollision() throws {
        let (model, plan) = try makeModelAndPlan()
        model.activeExportBatchPlans = [plan]
        model.exportBatchStore.begin([plan])
        model.exportBatchStore.requestCancellation()
        model.persistExportBatchCheckpoint()

        let checkpoint = try XCTUnwrap(
            ExportBatchCheckpoint.load(from: model.exportBatchCheckpointURL)
        )
        XCTAssertEqual(checkpoint.items.count, 1)
        XCTAssertEqual(checkpoint.items[0].state, .cancelled)
        try Data("preexisting-user-file".utf8).write(to: plan.outputURL)

        let restoredModel = AppModel(
            libraryCatalogURL: model.libraryCatalogURL,
            libraryDefectDirectoryURL: temporaryDirectory.appendingPathComponent("restored-defects"),
            libraryBackupDirectoryURL: temporaryDirectory.appendingPathComponent("restored-backups")
        )
        restoredModel.frames = [plan.frame]
        restoredModel.restoreExportBatchCheckpoint()

        XCTAssertEqual(restoredModel.exportBatchStore.items.count, 1)
        XCTAssertEqual(restoredModel.exportBatchStore.items[0].state, .cancelled)
        XCTAssertEqual(
            restoredModel.activeExportBatchPlans[0].options,
            plan.options
        )
        XCTAssertEqual(
            restoredModel.activeExportBatchPlans[0].printComposition,
            plan.printComposition
        )
        XCTAssertNotEqual(restoredModel.activeExportBatchPlans[0].outputURL, plan.outputURL)
        XCTAssertEqual(try Data(contentsOf: plan.outputURL), Data("preexisting-user-file".utf8))
    }

    private func makeModelAndPlan(index: Int = 1) throws -> (AppModel, ExportBatchPlan) {
        let model = AppModel(
            libraryCatalogURL: temporaryDirectory.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: temporaryDirectory.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: temporaryDirectory.appendingPathComponent("backups")
        )
        let frame = try makeFrame(index: index)
        model.frames = [frame]
        let plan = model.makeExportBatchPlans(
            frames: [frame],
            root: temporaryDirectory.appendingPathComponent("Exports"),
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: ExportOptions(
                jpegQuality: 0.76,
                tiffCompression: .lzw,
                tiffBitDepth: .eight,
                metadataPolicy: .copyrightOnly,
                outputSharpening: 0.45,
                outputSharpeningMedium: .glossyPaper
            ),
            printerOutputProfile: try ICCOutputProfileTestFixture.snapshot(),
            printComposition: PrintCompositionSettings(
                paperSize: .eightByTen,
                orientation: .landscape,
                marginMM: 12,
                dpi: 300,
                perforationStyle: .thirtyFiveMillimeter
            )
        )[0]
        return (model, plan)
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
