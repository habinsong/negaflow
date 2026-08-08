import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class LocalDodgeBurnVisibilityTests: XCTestCase {
    func testLegacyAdjustmentDefaultsToVisibleAndSidecarRoundTripsVisibility() throws {
        let json = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "mode":"dodge",
          "amount":0.4,
          "mask":{"kind":"radial","center":{"x":0.5,"y":0.5},"radius":0.2,"feather":0.3}
        }
        """
        let legacy = try JSONDecoder().decode(LocalDodgeBurnAdjustment.self, from: Data(json.utf8))
        XCTAssertTrue(legacy.isEnabled)

        var params = DevelopParameters()
        params.localDodgeBurn = [LocalDodgeBurnAdjustment(
            mode: .burn,
            amount: 0.7,
            isEnabled: false,
            mask: .polygon(points: [
                LocalDodgeBurnPoint(x: 0.1, y: 0.1),
                LocalDodgeBurnPoint(x: 0.8, y: 0.1),
                LocalDodgeBurnPoint(x: 0.5, y: 0.8),
            ], feather: 0.2)
        )]
        let decoded = try JSONDecoder().decode(
            Sidecar.self,
            from: JSONEncoder().encode(Sidecar(filmType: .colorPositive, parameters: params))
        )
        XCTAssertEqual(decoded.parameters.localDodgeBurn, params.localDodgeBurn)
        XCTAssertFalse(try XCTUnwrap(decoded.parameters.localDodgeBurn.first).isEnabled)
    }

    func testHiddenAdjustmentIsPixelExactNoop() {
        let image = CIImage(color: CIColor(red: 0.35, green: 0.35, blue: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 24))
        let hidden = LocalDodgeBurnAdjustment(
            mode: .dodge,
            amount: 1,
            isEnabled: false,
            mask: .radial(center: LocalDodgeBurnPoint(x: 0.5, y: 0.5), radius: 0.4, feather: 0.5)
        )
        let output = LocalDodgeBurnStage.apply(to: image, adjustments: [hidden])
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!])
        var original = [UInt8](repeating: 0, count: 32 * 24 * 4)
        var rendered = original
        context.render(image, toBitmap: &original, rowBytes: 32 * 4, bounds: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        context.render(output, toBitmap: &rendered, rowBytes: 32 * 4, bounds: output.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        XCTAssertEqual(rendered, original)
    }
}
