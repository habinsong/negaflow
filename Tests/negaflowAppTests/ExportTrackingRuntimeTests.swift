import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class ExportTrackingRuntimeTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-tracking-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try await super.tearDown()
    }

    func testSuccessfulExportPublishesOnlyExistingArtifactsAndTransitionsLegacyCoverage() async throws {
        let (model, frame) = try await makeReadyModel(assignFrameToRoll: true)
        var state = try XCTUnwrap(frame.libraryWorkflowTrackingState)
        state.exportTracking = .legacyUnknown
        frame.libraryWorkflowTrackingState = state
        XCTAssertTrue(model.saveLibrary(synchronous: true))

        let outputURL = tempDirectory.appendingPathComponent("published.jpg")
        model.exportFrame(
            frame,
            to: outputURL,
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: true,
            writeOriginalRaw: true
        )
        try await waitForExport(frame)

        let catalog = try XCTUnwrap(LibraryCatalogFile.loadPrimary(from: model.libraryCatalogURL))
        let record = try XCTUnwrap(catalog.frames.first(where: { $0.id == frame.id }))
        XCTAssertEqual(record.exportTracking.coverage, .tracked)
        let event = try XCTUnwrap(record.exportTracking.successfulEvents.only)
        XCTAssertEqual(event.renderKind, .developed)
        XCTAssertEqual(event.formatRawValue, ExportFormat.jpeg.rawValue)
        XCTAssertEqual(
            event.developRecipeSHA256,
            try LibraryDevelopRecipeFingerprint.sha256(
                filmType: frame.filmType,
                presetID: frame.preset?.id,
                params: frame.params,
                imageTransform: frame.imageTransform
            )
        )
        XCTAssertNil(event.defectRecipeSHA256)
        XCTAssertEqual(
            event.sourceIdentity,
            try RenderManifest.sourceIdentity(for: frame.rawScanURL)
        )

        let expectedLayout = ExportArtifactLayout(
            outputURL: outputURL,
            format: .jpeg,
            sourceURL: frame.rawScanURL,
            writeSidecar: true,
            writeMainFlatMaster: true,
            writeOriginalRaw: true
        )
        XCTAssertEqual(
            event.artifactPaths,
            expectedLayout.allURLs.map { $0.standardizedFileURL.path }
        )
        XCTAssertEqual(event.primaryOutputPath, outputURL.standardizedFileURL.path)
        for path in event.artifactPaths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        }
        XCTAssertEqual(frame.libraryWorkflowTrackingState?.exportTracking, record.exportTracking)
    }

    func testRawSourceExportRecordsNoDevelopOrDefectHash() async throws {
        let (model, frame) = try await makeReadyModel(assignFrameToRoll: true)
        let outputURL = tempDirectory.appendingPathComponent("raw-source.tif")

        model.exportFrame(frame, to: outputURL, format: .rawScanTIFF)
        try await waitForExport(frame)

        let catalog = try XCTUnwrap(LibraryCatalogFile.loadPrimary(from: model.libraryCatalogURL))
        let event = try XCTUnwrap(catalog.frames.first?.exportTracking.successfulEvents.only)
        XCTAssertEqual(event.renderKind, .rawSource)
        XCTAssertEqual(event.formatRawValue, ExportFormat.rawScanTIFF.rawValue)
        XCTAssertNil(event.developRecipeSHA256)
        XCTAssertNil(event.defectRecipeSHA256)
        XCTAssertEqual(
            event.sourceIdentity,
            try RenderManifest.sourceIdentity(for: frame.rawScanURL)
        )
        XCTAssertEqual(event.artifactPaths, [outputURL.standardizedFileURL.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testSymlinkSourceCanBeVerifiedAndExported() async throws {
        let model = AppModel(
            libraryCatalogURL: tempDirectory.appendingPathComponent("symlink-library.json"),
            libraryDefectDirectoryURL: tempDirectory.appendingPathComponent("symlink-defects"),
            libraryBackupDirectoryURL: tempDirectory.appendingPathComponent("symlink-backups")
        )
        await model.restoreLibraryOnLaunch()
        let targetURL = tempDirectory.appendingPathComponent("symlink-target.tiff")
        let sourceURL = tempDirectory.appendingPathComponent("symlink-source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: targetURL)
        try FileManager.default.createSymbolicLink(
            at: sourceURL,
            withDestinationURL: targetURL
        )
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: sourceURL,
            filmType: .colorPositive
        )
        _ = LibraryFrameRecord(frame: frame)
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame]))
        let outputURL = tempDirectory.appendingPathComponent("symlink-output.jpg")

        model.exportFrame(frame, to: outputURL, format: .jpeg)
        try await waitForExport(frame)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(
            frame.libraryWorkflowTrackingState?.exportTracking.successfulEvents.count,
            1
        )
    }

    func testCatalogCommitFailureRollsBackEventAndRemovesNewArtifacts() async throws {
        let (model, frame) = try await makeReadyModel(assignFrameToRoll: false)
        let previousTracking = frame.libraryWorkflowTrackingState?.exportTracking
        let outputURL = tempDirectory.appendingPathComponent("uncommitted.jpg")
        let layout = ExportArtifactLayout(
            outputURL: outputURL,
            format: .jpeg,
            sourceURL: frame.rawScanURL,
            writeSidecar: true,
            writeMainFlatMaster: true,
            writeOriginalRaw: true
        )

        model.exportFrame(
            frame,
            to: outputURL,
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: true,
            writeOriginalRaw: true
        )
        try await waitForExport(frame)

        XCTAssertEqual(frame.libraryWorkflowTrackingState?.exportTracking, previousTracking)
        for url in layout.allURLs {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testRollbackFailedCatalogCommitKeepsEventAndBlocksLibrary() async throws {
        let (model, frame) = try await makeReadyModel(assignFrameToRoll: true)
        let trackingIdentity = try XCTUnwrap(
            ExportFrameTrackingIdentity.capture(frame: frame, format: .jpeg)
        )
        let sourceIdentity = try RenderManifest.sourceIdentity(for: frame.rawScanURL)
        let sourceGeneration = ExportFrameSourceGeneration(
            rawScanURL: frame.rawScanURL,
            sourceIdentity: sourceIdentity
        )
        let sourceVerification = try makeSourceVerification(for: frame.rawScanURL)
        let event = try makeEvent(frame: frame, trackingIdentity: trackingIdentity)

        let outcome = model.commitSuccessfulExportEvent(
            event,
            for: frame,
            trackingIdentity: trackingIdentity,
            format: .jpeg,
            sourceGeneration: sourceGeneration,
            sourceVerification: sourceVerification,
            catalogCommit: { .failure(.rollbackFailed) }
        )

        XCTAssertEqual(outcome, .indeterminate)
        XCTAssertEqual(
            frame.libraryWorkflowTrackingState?.exportTracking.successfulEvents,
            [event]
        )
        XCTAssertEqual(model.libraryCatalogBlockReason, .writeFailed)
        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        XCTAssertFalse(model.libraryPersistenceEnabled)
        XCTAssertFalse(model.isAcknowledgedLibraryTransactionActive)
    }

    func testDefiniteCatalogCommitFailureRestoresEventWithoutBlockingLibrary() async throws {
        let (model, frame) = try await makeReadyModel(assignFrameToRoll: true)
        let previousTracking = frame.libraryWorkflowTrackingState?.exportTracking
        let trackingIdentity = try XCTUnwrap(
            ExportFrameTrackingIdentity.capture(frame: frame, format: .jpeg)
        )
        let sourceIdentity = try RenderManifest.sourceIdentity(for: frame.rawScanURL)
        let sourceGeneration = ExportFrameSourceGeneration(
            rawScanURL: frame.rawScanURL,
            sourceIdentity: sourceIdentity
        )
        let sourceVerification = try makeSourceVerification(for: frame.rawScanURL)
        let event = try makeEvent(frame: frame, trackingIdentity: trackingIdentity)

        let outcome = model.commitSuccessfulExportEvent(
            event,
            for: frame,
            trackingIdentity: trackingIdentity,
            format: .jpeg,
            sourceGeneration: sourceGeneration,
            sourceVerification: sourceVerification,
            catalogCommit: { .failure(.readbackFailed) }
        )

        XCTAssertEqual(outcome, .definitelyNotCommitted)
        XCTAssertEqual(frame.libraryWorkflowTrackingState?.exportTracking, previousTracking)
        XCTAssertNil(model.libraryCatalogBlockReason)
        XCTAssertEqual(model.libraryLifecycleState, .ready)
        XCTAssertTrue(model.libraryPersistenceEnabled)
        XCTAssertFalse(model.isAcknowledgedLibraryTransactionActive)
    }

    func testTrackingIdentityRejectsOwnershipDevelopAndDefectChanges() throws {
        let frame = try makeFrame()
        let recipeA = String(repeating: "a", count: 64)
        let sourceA = String(repeating: "b", count: 64)
        var state = try XCTUnwrap(frame.libraryWorkflowTrackingState)
        state.defectReviewTracking = LibraryDefectReviewTracking(
            coverage: .tracked,
            currentRecipeRevision: 1,
            currentRecipeSHA256: recipeA,
            currentSourceIdentitySHA256: sourceA,
            reviewedRecipeRevision: nil,
            reviewedRecipeSHA256: nil,
            reviewedSourceIdentitySHA256: nil
        )
        frame.libraryWorkflowTrackingState = state
        frame.defectEdits = [
            DefectEditItem(
                edit: .brush([]),
                title: "Active",
                summary: "",
                preview: [],
                baseSize: nil
            ),
        ]
        let identity = try XCTUnwrap(
            ExportFrameTrackingIdentity.capture(frame: frame, format: .jpeg)
        )

        XCTAssertFalse(identity.matchesCurrentState(
            of: frame,
            format: .jpeg,
            isOwnedByModel: false
        ))
        XCTAssertTrue(identity.matchesCurrentState(
            of: frame,
            format: .jpeg,
            isOwnedByModel: true
        ))

        frame.updateParams { $0.exposure = 0.5 }
        XCTAssertFalse(identity.matchesCurrentState(
            of: frame,
            format: .jpeg,
            isOwnedByModel: true
        ))
        frame.updateParams { $0.exposure = 0 }
        var changedDefectState = try XCTUnwrap(frame.libraryWorkflowTrackingState)
        changedDefectState.defectReviewTracking.currentRecipeRevision = 2
        changedDefectState.defectReviewTracking.currentRecipeSHA256 = String(
            repeating: "c",
            count: 64
        )
        frame.libraryWorkflowTrackingState = changedDefectState
        XCTAssertFalse(identity.matchesCurrentState(
            of: frame,
            format: .jpeg,
            isOwnedByModel: true
        ))
    }

    func testTrackingIdentityRejectsSourceRelinkAndRelinkBack() throws {
        let frame = try makeFrame()
        let originalURL = frame.rawScanURL
        let identity = try XCTUnwrap(
            ExportFrameTrackingIdentity.capture(frame: frame, format: .jpeg)
        )
        let replacementURL = tempDirectory.appendingPathComponent("replacement-source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: replacementURL)

        frame.updateSourceLocation(
            rawURL: replacementURL,
            infraredURL: nil,
            sourceMetadata: nil
        )
        XCTAssertFalse(identity.matchesCurrentState(
            of: frame,
            format: .jpeg,
            isOwnedByModel: true
        ))

        frame.updateSourceLocation(
            rawURL: originalURL,
            infraredURL: nil,
            sourceMetadata: nil
        )
        XCTAssertFalse(identity.matchesCurrentState(
            of: frame,
            format: .jpeg,
            isOwnedByModel: true
        ))
    }

    func testSourceGenerationRejectsSamePathReplacementAfterVerification() async throws {
        let frame = try makeFrame()
        let trackingIdentity = try XCTUnwrap(
            ExportFrameTrackingIdentity.capture(frame: frame, format: .jpeg)
        )
        let sourceIdentity = try RenderManifest.sourceIdentity(for: frame.rawScanURL)
        let generation = ExportFrameSourceGeneration(
            rawScanURL: frame.rawScanURL,
            sourceIdentity: sourceIdentity
        )
        let capturedVerification = await ExportFrameSourceGeneration.capture(
            at: frame.rawScanURL
        )
        let verification = try XCTUnwrap(capturedVerification)

        try Data("replaced-source".utf8).write(to: frame.rawScanURL, options: .atomic)

        XCTAssertFalse(generation.matchesCurrentState(
            of: frame,
            trackingIdentity: trackingIdentity,
            format: .jpeg,
            isOwnedByModel: true,
            verification: verification
        ))
    }

    func testFilmBaseCacheCommitRejectsRelinkedSource() throws {
        let frame = try makeFrame()
        let trackingIdentity = try XCTUnwrap(
            ExportFrameTrackingIdentity.capture(frame: frame, format: .jpeg)
        )
        let sourceIdentity = try RenderManifest.sourceIdentity(for: frame.rawScanURL)
        let generation = ExportFrameSourceGeneration(
            rawScanURL: frame.rawScanURL,
            sourceIdentity: sourceIdentity
        )
        let sourceVerification = try makeSourceVerification(for: frame.rawScanURL)
        let baseKey = FilmBaseCacheKey(
            filmType: frame.filmType,
            mode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            filmStockDminID: frame.params.filmStockDminID,
            lightSourceProfileID: frame.params.lightSourceProfileID
        )
        let base = FilmBase(rgb: SIMD3(0.8, 0.6, 0.4), source: .auto)
        let replacementURL = tempDirectory.appendingPathComponent("replacement-cache-source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: replacementURL)
        frame.updateSourceLocation(
            rawURL: replacementURL,
            infraredURL: nil,
            sourceMetadata: nil
        )

        XCTAssertFalse(ExportFilmBaseCacheCommitter.apply(
            base,
            baseKey: baseKey,
            to: frame,
            trackingIdentity: trackingIdentity,
            format: .jpeg,
            sourceGeneration: generation,
            sourceVerification: sourceVerification,
            isOwnedByModel: true
        ))
        XCTAssertNil(frame.cachedBaseKey)
        XCTAssertNil(frame.cachedBase)
        XCTAssertNil(frame.baseRGB)
    }

    func testCommittedExportFinalizationFailureBlocksLibrary() async throws {
        let (model, _) = try await makeReadyModel(assignFrameToRoll: true)

        let finalized = await model.finalizeCommittedExport(
            transactionID: UUID(),
            completion: { _ in
                throw ChromabaseError.writeFailed("forced finalization failure")
            }
        )

        XCTAssertFalse(finalized)
        XCTAssertEqual(model.libraryCatalogBlockReason, .writeFailed)
        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        XCTAssertFalse(model.libraryPersistenceEnabled)
    }

    func testCommittedExportAcknowledgementFailureBlocksLibrary() async throws {
        let (model, _) = try await makeReadyModel(assignFrameToRoll: true)

        let acknowledged = model.acknowledgeCommittedExport(transactionID: UUID())

        XCTAssertFalse(acknowledged)
        XCTAssertEqual(model.libraryCatalogBlockReason, .writeFailed)
        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        XCTAssertFalse(model.libraryPersistenceEnabled)
    }

    func testStartupRollsBackIntentWithoutCatalogEvidenceAndOpensLibrary() async throws {
        let transactionID = UUID()
        let stagingDirectory = tempDirectory.appendingPathComponent(
            ".negaflow-export-\(transactionID.uuidString).tmp",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false
        )
        try ExportArtifactCommitJournal.beginPreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory
        )
        let sourceURL = tempDirectory.appendingPathComponent("reconcile-source.tiff")
        try Data("source".utf8).write(to: sourceURL)
        let layout = ExportArtifactLayout(
            outputURL: tempDirectory.appendingPathComponent("reconcile-output.jpg"),
            format: .jpeg,
            sourceURL: sourceURL,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false
        )
        let stagedLayout = layout.staged(in: stagingDirectory)
        try Data("artifact".utf8).write(to: stagedLayout.outputURL)
        try ExportArtifactCommitJournal.promotePreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            stagedLayout: stagedLayout,
            finalLayout: layout
        )
        try ExportArtifactCommitJournal.completePreparation(transactionID: transactionID)
        try ExportArtifactCommitJournal.publish(
            transactionID: transactionID,
            stagedURL: stagedLayout.outputURL,
            finalURL: layout.outputURL
        )
        XCTAssertTrue(ExportArtifactCommitJournal.cleanupOwnedStaging(
            transactionID: transactionID
        ))
        try ExportArtifactCommitJournal.markCatalogCommitIntent(transactionID: transactionID)
        defer {
            ExportArtifactCommitJournal.cancelCatalogCommitIntent(transactionID: transactionID)
        }
        let model = AppModel(
            libraryCatalogURL: tempDirectory.appendingPathComponent("reconcile-library.json"),
            libraryDefectDirectoryURL: tempDirectory.appendingPathComponent("reconcile-defects"),
            libraryBackupDirectoryURL: tempDirectory.appendingPathComponent("reconcile-backups")
        )

        await model.restoreLibraryOnLaunch()

        XCTAssertNil(model.libraryCatalogBlockReason)
        XCTAssertEqual(model.libraryLifecycleState, .ready)
        XCTAssertTrue(model.libraryPersistenceEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.outputURL.path))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: transactionID
        ))
    }

    func testBlockingExportReconciliationStopsLibrary() async throws {
        let (model, _) = try await makeReadyModel(assignFrameToRoll: true)
        let transactionID = UUID()
        let report = ExportArtifactCommitReconciliationReport(
            completedTransactionIDs: [],
            unresolvedTransactionIDs: [transactionID],
            blockingTransactionIDs: [transactionID]
        )

        XCTAssertTrue(model.blockLibraryForInconsistentExportReconciliation(report))
        XCTAssertEqual(model.libraryCatalogBlockReason, .writeFailed)
        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        XCTAssertFalse(model.libraryPersistenceEnabled)
    }

    func testActiveDefectWithoutCompleteIdentityFailsClosed() throws {
        let frame = try makeFrame()
        frame.defectEdits = [
            DefectEditItem(
                edit: .brush([]),
                title: "Unbound",
                summary: "",
                preview: [],
                baseSize: nil
            ),
        ]

        XCTAssertNil(ExportFrameTrackingIdentity.capture(frame: frame, format: .jpeg))
    }

    private func makeReadyModel(
        assignFrameToRoll: Bool
    ) async throws -> (AppModel, ScanFrame) {
        let model = AppModel(
            libraryCatalogURL: tempDirectory.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: tempDirectory.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: tempDirectory.appendingPathComponent("Backups")
        )
        await model.restoreLibraryOnLaunch()
        let frame = try makeFrame()
        model.frames = [frame]
        if assignFrameToRoll {
            XCTAssertTrue(model.assignNewPersistentFrames([frame]))
        }
        return (model, frame)
    }

    private func makeFrame() throws -> ScanFrame {
        let rawURL = tempDirectory.appendingPathComponent("source-\(UUID().uuidString).tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: rawURL)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: rawURL,
            filmType: .colorPositive
        )
        _ = LibraryFrameRecord(frame: frame)
        return frame
    }

    private func makeEvent(
        frame: ScanFrame,
        trackingIdentity: ExportFrameTrackingIdentity
    ) throws -> LibraryExportEvent {
        let outputURL = tempDirectory.appendingPathComponent("event-output.jpg")
        return LibraryExportEvent(
            id: UUID(),
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            primaryOutputPath: outputURL.path,
            artifactPaths: [outputURL.path],
            formatRawValue: ExportFormat.jpeg.rawValue,
            renderKind: .developed,
            developRecipeSHA256: trackingIdentity.developRecipeSHA256,
            defectRecipeSHA256: trackingIdentity.defectRecipeIdentity?.recipeSHA256,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL)
        )
    }

    private func makeSourceVerification(
        for url: URL
    ) throws -> ExportFrameSourceVerification {
        ExportFrameSourceVerification(
            sourceIdentity: try RenderManifest.sourceIdentity(for: url),
            fileIdentity: try XCTUnwrap(
                ExportArtifactFileIdentityInspector.sourceFile(at: url)
            )
        )
    }

    private func waitForExport(
        _ frame: ScanFrame,
        timeoutNanoseconds: UInt64 = 20_000_000_000
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while frame.isDeveloping,
              DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(frame.isDeveloping, "export did not finish before timeout")
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}
