import Combine
import XCTest
@testable import negaflowApp

@MainActor
final class ExportAvailabilityStoreTests: XCTestCase {
    func testDevelopmentReadinessRefreshesExportAvailability() {
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-export-availability.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        model.frames = [frame]
        model.updateInteractionScope([frame.id])
        model.selectedFrameID = frame.id

        var emissions = 0
        let observation = model.exportAvailabilityStore.objectWillChange.sink {
            emissions += 1
        }
        defer { observation.cancel() }

        XCTAssertFalse(model.canExportSelection)

        frame.isDeveloping = true
        frame.hasDevelopedOnce = true
        XCTAssertFalse(model.canExportSelection)

        frame.isDeveloping = false

        XCTAssertTrue(model.canExportSelection)
        XCTAssertEqual(emissions, 3)
    }

    func testUnrelatedFrameChangesDoNotRefreshExportAvailability() {
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-export-boundary.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        model.frames = [frame]

        var emissions = 0
        let observation = model.exportAvailabilityStore.objectWillChange.sink {
            emissions += 1
        }
        defer { observation.cancel() }

        frame.updateParams { $0.exposure = 0.5 }

        XCTAssertEqual(emissions, 0)
    }
}
