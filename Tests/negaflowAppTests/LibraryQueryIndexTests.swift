import AppKit
import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class LibraryQueryIndexTests: XCTestCase {
    func testFrameObservationInvalidatesQueryRelevantValues() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: fixture.source,
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourceMetadata: SourceMetadataSnapshot(fileSizeBytes: 1)
        )
        _ = LibraryFrameRecord(frame: frame)
        model.frames = [frame]
        let initialGeneration = model.libraryQueryGeneration

        frame.thumbnailImage = NSImage(size: NSSize(width: 8, height: 8))
        XCTAssertEqual(model.libraryQueryGeneration, initialGeneration)
        frame.updateParams { $0.exposure = 0.5 }
        XCTAssertGreaterThan(model.libraryQueryGeneration, initialGeneration)
        XCTAssertEqual(
            model.makeLibraryQueryContext().factsByFrameID[frame.id]?.userEditState,
            .edited
        )

        let beforeDirectParameterMutation = model.libraryQueryGeneration
        frame.params.tint = 0.25
        XCTAssertGreaterThan(
            model.libraryQueryGeneration,
            beforeDirectParameterMutation
        )

        let beforePreset = model.libraryQueryGeneration
        frame.preset = try XCTUnwrap(PresetRegistry.load(named: "neutral"))
        XCTAssertGreaterThan(model.libraryQueryGeneration, beforePreset)

        let beforeTransform = model.libraryQueryGeneration
        frame.updateTransform { $0.flipHorizontal.toggle() }
        XCTAssertGreaterThan(model.libraryQueryGeneration, beforeTransform)

        frame.setRating(4)
        let ratingGeneration = model.libraryQueryGeneration
        XCTAssertGreaterThan(ratingGeneration, initialGeneration)
        XCTAssertEqual(
            model.makeLibraryQueryContext().factsByFrameID[frame.id]?.rating,
            4
        )

        frame.pickState = .picked
        XCTAssertGreaterThan(model.libraryQueryGeneration, ratingGeneration)
        XCTAssertEqual(
            model.makeLibraryQueryContext().factsByFrameID[frame.id]?.pickState,
            .picked
        )

        let beforeParams = model.libraryQueryGeneration
        frame.updateParams { $0.scannerProfileID = "missing-profile" }
        XCTAssertGreaterThan(model.libraryQueryGeneration, beforeParams)
        XCTAssertEqual(
            model.makeLibraryQueryContext().factsByFrameID[frame.id]?.scannerProfileState,
            .missing
        )

        let beforeCalibration = model.libraryQueryGeneration
        frame.updateParams { $0.redPrimary = 0.2 }
        XCTAssertGreaterThan(model.libraryQueryGeneration, beforeCalibration)

        let defect = DefectEditItem(
            edit: .brush([]),
            title: "test",
            summary: "",
            preview: [],
            baseSize: nil
        )
        let beforeDefect = model.libraryQueryGeneration
        frame.defectEdits = [defect]
        XCTAssertGreaterThan(model.libraryQueryGeneration, beforeDefect)
        let withDefect = model.libraryQueryGeneration
        frame.defectEdits = []
        XCTAssertGreaterThan(model.libraryQueryGeneration, withDefect)
    }

    func testWorkflowTrackingStatesDriveContextAndInvalidateLive() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: fixture.source,
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        _ = LibraryFrameRecord(frame: frame)
        model.frames = [frame]

        var facts = try XCTUnwrap(model.makeLibraryQueryContext().factsByFrameID[frame.id])
        XCTAssertEqual(facts.exportState, .never)
        XCTAssertEqual(facts.userEditState, .unedited)
        XCTAssertEqual(facts.defectReviewState, .notRequired)

        var tracking = try XCTUnwrap(frame.libraryWorkflowTrackingState)
        let recipeSHA256 = try XCTUnwrap(tracking.userEditTracking.currentRecipeSHA256)
        tracking.exportTracking.successfulEvents = [LibraryExportEvent(
            id: UUID(),
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            primaryOutputPath: "/exports/frame.tiff",
            artifactPaths: ["/exports/frame.tiff"],
            formatRawValue: "tiff16",
            renderKind: .developed,
            developRecipeSHA256: recipeSHA256,
            defectRecipeSHA256: nil
        )]
        let beforeExport = model.libraryQueryGeneration
        frame.libraryWorkflowTrackingState = tracking
        XCTAssertGreaterThan(model.libraryQueryGeneration, beforeExport)
        facts = try XCTUnwrap(model.makeLibraryQueryContext().factsByFrameID[frame.id])
        XCTAssertEqual(facts.exportState, .succeeded)

        frame.defectEdits = [DefectEditItem(
            edit: .brush([]),
            title: "test",
            summary: "",
            preview: [],
            baseSize: nil
        )]
        facts = try XCTUnwrap(model.makeLibraryQueryContext().factsByFrameID[frame.id])
        XCTAssertEqual(facts.defectReviewState, .unknown)

        let defectRecipeSHA256 = String(repeating: "a", count: 64)
        let sourceIdentitySHA256 = String(repeating: "b", count: 64)
        tracking.defectReviewTracking = LibraryDefectReviewTracking(
            coverage: .tracked,
            currentRecipeRevision: 1,
            currentRecipeSHA256: defectRecipeSHA256,
            currentSourceIdentitySHA256: sourceIdentitySHA256,
            reviewedRecipeRevision: nil,
            reviewedRecipeSHA256: nil,
            reviewedSourceIdentitySHA256: nil
        )
        frame.libraryWorkflowTrackingState = tracking
        facts = try XCTUnwrap(model.makeLibraryQueryContext().factsByFrameID[frame.id])
        XCTAssertEqual(facts.defectReviewState, .needsReview)

        tracking.defectReviewTracking.reviewedRecipeRevision = 1
        tracking.defectReviewTracking.reviewedRecipeSHA256 = defectRecipeSHA256
        tracking.defectReviewTracking.reviewedSourceIdentitySHA256 = sourceIdentitySHA256
        frame.libraryWorkflowTrackingState = tracking
        facts = try XCTUnwrap(model.makeLibraryQueryContext().factsByFrameID[frame.id])
        XCTAssertEqual(facts.defectReviewState, .reviewed)

        tracking.defectReviewTracking.reviewedRecipeSHA256 = String(repeating: "c", count: 64)
        frame.libraryWorkflowTrackingState = tracking
        facts = try XCTUnwrap(model.makeLibraryQueryContext().factsByFrameID[frame.id])
        XCTAssertEqual(facts.defectReviewState, .unknown)

        tracking.userEditTracking = .legacyUnknown(currentRecipeSHA256: recipeSHA256)
        tracking.exportTracking = .legacyUnknown
        tracking.defectReviewTracking = .legacyUnknown
        frame.libraryWorkflowTrackingState = tracking
        facts = try XCTUnwrap(model.makeLibraryQueryContext().factsByFrameID[frame.id])
        XCTAssertEqual(facts.exportState, .unknown)
        XCTAssertEqual(facts.userEditState, .unknown)
        XCTAssertEqual(facts.defectReviewState, .unknown)
    }

    func testRemovedFramesStopInvalidatingAndUndoStyleRestoreResubscribes() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: fixture.source,
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        model.frames = [frame]
        model.frames = []
        let removedGeneration = model.libraryQueryGeneration

        frame.setRating(2)
        XCTAssertEqual(model.libraryQueryGeneration, removedGeneration)

        model.frames = [frame]
        let restoredGeneration = model.libraryQueryGeneration
        frame.setRating(3)
        XCTAssertGreaterThan(model.libraryQueryGeneration, restoredGeneration)
    }

    func testSelectionAndInteractionScopeDoNotInvalidateQueryIndex() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: fixture.source,
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        model.frames = [frame]
        let generation = model.libraryQueryGeneration

        model.selectedFrameID = frame.id
        model.updateInteractionScope([frame.id])
        model.clearFrameSelection()

        XCTAssertEqual(model.libraryQueryGeneration, generation)
    }

    func testUnrelatedModelPublishKeepsFrameAndFolderProjectionCaches() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: fixture.source,
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        model.frames = [frame]
        let sections = model.makeLibraryFolderTreeSections(orderedFrameIDs: [frame.id])
        let revision = model.libraryFolderProjectionRevision
        let frameIDs = model.libraryFrameIDsSnapshot
        let cachedFrame = model.uniqueLibraryFramesByID()[frame.id]

        model.statusMessage = "query cache unrelated status"

        let reused = model.makeLibraryFolderTreeSections(orderedFrameIDs: [frame.id])
        XCTAssertEqual(model.libraryFolderProjectionRevision, revision)
        XCTAssertEqual(model.libraryFrameIDsSnapshot, frameIDs)
        XCTAssertTrue(model.uniqueLibraryFramesByID()[frame.id] === cachedFrame)
        XCTAssertEqual(reused.map(\.id), sections.map(\.id))
        XCTAssertEqual(reused.flatMap(\.frames).map(\.id), [frame.id])
    }

    func testFrameIdentityCacheFailsClosedForDuplicateIDsAndRefreshesOnListChange() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = AppModel()
        let duplicateID = UUID()
        let first = ScanFrame(
            scanIndex: 1,
            rawScanURL: fixture.source,
            filmType: .colorNegative,
            sourceKind: .importedFile,
            id: duplicateID
        )
        let second = ScanFrame(
            scanIndex: 2,
            rawScanURL: fixture.directory.appendingPathComponent("second.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile,
            id: duplicateID
        )

        model.frames = [first, second]
        XCTAssertEqual(model.libraryFrameIDsSnapshot, [duplicateID, duplicateID])
        XCTAssertNil(model.uniqueLibraryFramesByID()[duplicateID])
        XCTAssertTrue(model.makeLibraryQueryContext().factsByFrameID.isEmpty)

        model.frames = [first]
        XCTAssertEqual(model.libraryFrameIDsSnapshot, [duplicateID])
        XCTAssertTrue(model.uniqueLibraryFramesByID()[duplicateID] === first)
        XCTAssertEqual(Set(model.makeLibraryQueryContext().factsByFrameID.keys), [duplicateID])
    }

    func testAvailabilitySnapshotIsReusedUntilExplicitRefresh() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: fixture.source,
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        model.frames = [frame]

        let first = model.makeLibraryQueryContext()
        XCTAssertEqual(first.factsByFrameID[frame.id]?.availability, .online)
        try FileManager.default.removeItem(at: fixture.source)

        let cached = model.makeLibraryQueryContext()
        XCTAssertEqual(cached.generation, first.generation)
        XCTAssertEqual(cached.factsByFrameID[frame.id]?.availability, .online)

        model.refreshSourceAvailability()
        let refreshed = model.makeLibraryQueryContext()
        XCTAssertGreaterThan(refreshed.generation, cached.generation)
        XCTAssertEqual(refreshed.factsByFrameID[frame.id]?.availability, .offline)
    }

    func testSourceRelinkInvalidatesMetadataAndAvailabilityTogether() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = AppModel()
        let missing = fixture.directory.appendingPathComponent("missing.tiff")
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: missing,
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        model.frames = [frame]
        let before = model.makeLibraryQueryContext()
        XCTAssertEqual(before.factsByFrameID[frame.id]?.availability, .offline)
        XCTAssertEqual(
            before.factsByFrameID[frame.id]?.metadataPresenceByField[.snapshot],
            .unknown
        )

        frame.updateSourceLocation(
            rawURL: fixture.source,
            infraredURL: nil,
            sourceMetadata: SourceMetadataSnapshot(fileSizeBytes: 1)
        )
        let after = model.makeLibraryQueryContext()

        XCTAssertGreaterThan(after.generation, before.generation)
        XCTAssertEqual(after.factsByFrameID[frame.id]?.availability, .online)
        XCTAssertEqual(
            after.factsByFrameID[frame.id]?.metadataPresenceByField[.snapshot],
            .present
        )
    }

    private func makeFixture() throws -> (directory: URL, source: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-query-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.tiff")
        try Data([1]).write(to: source)
        return (directory, source)
    }
}
