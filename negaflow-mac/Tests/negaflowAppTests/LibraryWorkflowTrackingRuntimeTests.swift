import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class LibraryWorkflowTrackingRuntimeTests: XCTestCase {
    func testNewFrameStartsWithTrackedUneditedWorkflowState() throws {
        let frame = makeFrame(index: 1)

        let record = LibraryFrameRecord(frame: frame)
        let recipe = try LibraryDevelopRecipeFingerprint.sha256(
            filmType: frame.filmType,
            presetID: frame.preset?.id,
            params: frame.params,
            imageTransform: frame.imageTransform
        )

        XCTAssertEqual(record.userEditTracking.coverage, .tracked)
        XCTAssertEqual(record.userEditTracking.ingestRecipeSHA256, recipe)
        XCTAssertEqual(record.userEditTracking.currentRecipeSHA256, recipe)
        XCTAssertEqual(record.userEditTracking.revision, 0)
        XCTAssertEqual(record.exportTracking.coverage, .tracked)
        XCTAssertTrue(record.exportTracking.successfulEvents.isEmpty)
        XCTAssertEqual(record.defectReviewTracking.coverage, .tracked)
    }

    func testAutomaticImportDefaultsBecomeBaselineBeforeFirstUserEdit() throws {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                "tracking-auto-\(UUID().uuidString).tiff"
            ),
            filmType: .colorNegative
        )
        XCTAssertNil(frame.libraryWorkflowTrackingState)
        frame.preset = try XCTUnwrap(PresetRegistry.load(named: "neutral"))
        frame.updateParams {
            $0.filmType = .colorNegative
            $0.developTarget = .print
            $0.scannerProfileID = "automatic-profile"
        }
        frame.establishLibraryWorkflowBaselineIfNeeded()

        let initial = LibraryFrameRecord(frame: frame)
        let baselineSHA256 = try LibraryDevelopRecipeFingerprint.sha256(
            filmType: frame.filmType,
            presetID: frame.preset?.id,
            params: frame.params,
            imageTransform: frame.imageTransform
        )
        XCTAssertEqual(initial.userEditTracking.coverage, .tracked)
        XCTAssertEqual(initial.userEditTracking.ingestRecipeSHA256, baselineSHA256)
        XCTAssertEqual(initial.userEditTracking.currentRecipeSHA256, baselineSHA256)
        XCTAssertEqual(initial.userEditTracking.revision, 0)

        frame.updateParams { $0.exposure = 0.5 }
        let edited = LibraryFrameRecord(frame: frame)
        XCTAssertEqual(edited.userEditTracking.ingestRecipeSHA256, baselineSHA256)
        XCTAssertNotEqual(edited.userEditTracking.currentRecipeSHA256, baselineSHA256)
        XCTAssertEqual(edited.userEditTracking.revision, 1)
    }

    func testAppModelRestoreAndSavePreservesTrackedFrameState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-tracking-runtime-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let frame = makeFrame(index: 1, root: root)
        var record = LibraryFrameRecord(frame: frame)
        let recipe = try XCTUnwrap(record.userEditTracking.currentRecipeSHA256)
        record.userEditTracking = LibraryUserEditTracking(
            coverage: .tracked,
            ingestRecipeSHA256: recipe,
            currentRecipeSHA256: recipe,
            revision: 0
        )
        let event = LibraryExportEvent(
            id: UUID(),
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            primaryOutputPath: "/exports/frame.tiff",
            artifactPaths: ["/exports/frame.tiff"],
            formatRawValue: "tiff16",
            renderKind: .developed,
            developRecipeSHA256: recipe,
            defectRecipeSHA256: nil
        )
        record.exportTracking = LibraryExportTracking(
            coverage: .tracked,
            successfulEvents: [event]
        )
        record.defectReviewTracking = LibraryDefectReviewTracking(
            coverage: .tracked,
            currentRecipeRevision: nil,
            currentRecipeSHA256: nil,
            currentSourceIdentitySHA256: nil,
            reviewedRecipeRevision: nil,
            reviewedRecipeSHA256: nil,
            reviewedSourceIdentitySHA256: nil
        )
        let catalogURL = root.appendingPathComponent("library.json")
        try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog(
            frames: [record],
            rolls: [LibraryRoll.unassigned(
                createdAt: frame.scannedAt,
                frameIDs: [frame.id]
            )]
        ))).write(to: catalogURL, options: .atomic)
        let model = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )

        await model.restoreLibraryOnLaunch()
        XCTAssertTrue(model.saveLibrary(synchronous: true))

        let saved = try XCTUnwrap(
            LibraryCatalogFile.decode(Data(contentsOf: catalogURL))?.frames.first
        )
        XCTAssertEqual(saved.userEditTracking, record.userEditTracking)
        XCTAssertEqual(saved.exportTracking, record.exportTracking)
        XCTAssertEqual(saved.defectReviewTracking, record.defectReviewTracking)
    }

    func testFirstEditAfterLegacyRestoreTransitionsWithoutInventingIngestHistory() throws {
        let frame = makeFrame(index: 1)
        var legacyRecord = LibraryFrameRecord(frame: frame)
        let ingestRecipe = try XCTUnwrap(legacyRecord.userEditTracking.currentRecipeSHA256)
        legacyRecord.userEditTracking = .legacyUnknown(currentRecipeSHA256: ingestRecipe)
        legacyRecord.exportTracking = .legacyUnknown
        legacyRecord.defectReviewTracking = .legacyUnknown
        let restored = legacyRecord.makeFrame(presets: [])

        restored.updateParams { $0.exposure = 0.75 }
        let firstSave = LibraryFrameRecord(frame: restored)
        let secondSave = LibraryFrameRecord(frame: restored)

        XCTAssertEqual(firstSave.userEditTracking.coverage, .tracked)
        XCTAssertEqual(firstSave.userEditTracking.ingestRecipeSHA256, ingestRecipe)
        XCTAssertNotEqual(firstSave.userEditTracking.currentRecipeSHA256, ingestRecipe)
        XCTAssertEqual(firstSave.userEditTracking.revision, 1)
        XCTAssertEqual(secondSave.userEditTracking, firstSave.userEditTracking)
        XCTAssertEqual(firstSave.exportTracking, .legacyUnknown)
        XCTAssertEqual(firstSave.defectReviewTracking, .legacyUnknown)
    }

    func testVirtualCopyStartsWithIndependentWorkflowBaseline() throws {
        let source = makeFrame(index: 1)
        source.updateParams { $0.exposure = 0.75 }
        _ = LibraryFrameRecord(frame: source)
        var sourceTracking = try XCTUnwrap(source.libraryWorkflowTrackingState)
        let sourceRecipeSHA256 = try XCTUnwrap(
            sourceTracking.userEditTracking.currentRecipeSHA256
        )
        sourceTracking.exportTracking.successfulEvents = [LibraryExportEvent(
            id: UUID(),
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            primaryOutputPath: "/exports/source.tiff",
            artifactPaths: ["/exports/source.tiff"],
            formatRawValue: "tiff16",
            renderKind: .developed,
            developRecipeSHA256: sourceRecipeSHA256,
            defectRecipeSHA256: nil
        )]
        sourceTracking.defectReviewTracking = LibraryDefectReviewTracking(
            coverage: .tracked,
            currentRecipeRevision: 3,
            currentRecipeSHA256: String(repeating: "a", count: 64),
            currentSourceIdentitySHA256: String(repeating: "b", count: 64),
            reviewedRecipeRevision: 3,
            reviewedRecipeSHA256: String(repeating: "a", count: 64),
            reviewedSourceIdentitySHA256: String(repeating: "b", count: 64)
        )
        source.libraryWorkflowTrackingState = sourceTracking

        let copy = source.makeVirtualCopy(copyNumber: 1)
        let record = LibraryFrameRecord(frame: copy)
        let copyRecipeSHA256 = try LibraryDevelopRecipeFingerprint.sha256(
            filmType: copy.filmType,
            presetID: copy.preset?.id,
            params: copy.params,
            imageTransform: copy.imageTransform
        )

        XCTAssertEqual(record.userEditTracking.coverage, .tracked)
        XCTAssertEqual(record.userEditTracking.ingestRecipeSHA256, copyRecipeSHA256)
        XCTAssertEqual(record.userEditTracking.currentRecipeSHA256, copyRecipeSHA256)
        XCTAssertEqual(record.userEditTracking.revision, 0)
        XCTAssertEqual(record.exportTracking.coverage, .tracked)
        XCTAssertTrue(record.exportTracking.successfulEvents.isEmpty)
        XCTAssertEqual(record.defectReviewTracking.coverage, .tracked)
        XCTAssertNil(record.defectReviewTracking.currentRecipeRevision)
        XCTAssertNil(record.defectReviewTracking.reviewedRecipeRevision)
    }

    private func makeFrame(
        index: Int,
        root: URL = FileManager.default.temporaryDirectory
    ) -> ScanFrame {
        let frame = ScanFrame(
            scanIndex: index,
            rawScanURL: root.appendingPathComponent("tracking-\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
        frame.establishLibraryWorkflowBaselineIfNeeded()
        return frame
    }
}
