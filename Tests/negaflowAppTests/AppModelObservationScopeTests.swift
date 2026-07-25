import Combine
import XCTest
@testable import negaflowApp

@MainActor
final class AppModelObservationScopeTests: XCTestCase {
    func testDevelopProgressDoesNotInvalidateEntireAppModel() {
        let model = AppModel(scannerPluginTrustStore: nil)
        var invalidations = 0
        let observation = model.objectWillChange.sink { invalidations += 1 }

        model.developController.developBegan()
        model.developController.updateProcessingDetail(
            interactive: true,
            proxyPixels: 2_048,
            isScanning: false
        )
        model.developController.developEnded()

        XCTAssertEqual(invalidations, 0)
        withExtendedLifetime(observation) {}
    }

    func testFrameStoreStillInvalidatesAppModelForExistingConsumers() {
        let model = AppModel(scannerPluginTrustStore: nil)
        var invalidations = 0
        let observation = model.objectWillChange.sink { invalidations += 1 }

        model.frameStore.selectedFrameID = UUID()

        XCTAssertGreaterThan(invalidations, 0)
        withExtendedLifetime(observation) {}
    }
}
