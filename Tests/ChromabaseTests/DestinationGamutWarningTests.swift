import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

final class DestinationGamutWarningTests: XCTestCase {
    private let linearSRGB = CGColorSpace(name: CGColorSpace.linearSRGB)!

    func testSRGBInteriorAndBoundaryColorsDoNotProduceFalseWarnings() throws {
        let image = makeImage([
            [128, 128, 128, 255],
            [0, 0, 0, 255],
            [255, 255, 255, 255],
            [255, 0, 0, 255],
            [0, 255, 0, 255],
            [0, 0, 255, 255],
        ])
        let settings = SoftProofSettings(isEnabled: true, colorSpace: .sRGB)

        let result = try XCTUnwrap(DestinationGamutWarning.makeOverlay(
            for: image,
            context: makeContext(),
            settings: settings
        ))

        XCTAssertEqual(result.overlay.width, 6)
        XCTAssertEqual(result.overlay.height, 1)
        XCTAssertEqual(result.totalPixelCount, 6)
        XCTAssertEqual(result.warningPixelCount, 0)
        XCTAssertFalse(result.containsWarnings)
    }

    func testNarrowOutputProfileProducesRealColorSyncGamutMask() throws {
        let profile = try XCTUnwrap(narrowRGBColorSpace().copyICCData() as Data?)
        XCTAssertNotNil(SoftProof.rgbOutputColorSpace(fromICCData: profile))
        let image = makeImage([
            [128, 128, 128, 255],
            [254, 1, 1, 255],
            [1, 254, 1, 255],
            [1, 1, 254, 255],
        ])
        let settings = SoftProofSettings(
            isEnabled: true,
            colorSpace: .sRGB,
            iccProfileData: profile
        )

        let result = try XCTUnwrap(DestinationGamutWarning.makeOverlay(
            for: image,
            context: makeContext(),
            settings: settings
        ))

        XCTAssertTrue(DestinationGamutWarning.isSupported(for: settings))
        XCTAssertGreaterThan(result.warningPixelCount, 0)
        XCTAssertLessThanOrEqual(result.warningPixelCount, result.totalPixelCount)
        XCTAssertTrue(result.containsWarnings)
        XCTAssertGreaterThan(maximumAlpha(in: result.overlay), 0)
    }

    func testMalformedOrDisabledProfileFailsClosed() {
        let image = makeImage([[254, 1, 1, 255]])
        let malformed = SoftProofSettings(
            isEnabled: true,
            colorSpace: .sRGB,
            iccProfileData: Data([0, 1, 2])
        )
        let disabled = SoftProofSettings(isEnabled: false, colorSpace: .sRGB)

        XCTAssertNil(DestinationGamutWarning.makeOverlay(
            for: image,
            context: makeContext(),
            settings: malformed
        ))
        XCTAssertFalse(DestinationGamutWarning.isSupported(for: malformed))
        XCTAssertNil(DestinationGamutWarning.makeOverlay(
            for: image,
            context: makeContext(),
            settings: disabled
        ))
    }

    private func makeContext() -> CIContext {
        CIContext(options: [
            .workingColorSpace: linearSRGB,
            .outputColorSpace: linearSRGB,
            .useSoftwareRenderer: true,
        ])
    }

    private func makeImage(_ pixels: [[UInt8]]) -> CIImage {
        let bytes = pixels.flatMap { $0 }
        return CIImage(
            bitmapData: Data(bytes),
            bytesPerRow: pixels.count * 4,
            size: CGSize(width: pixels.count, height: 1),
            format: .RGBA8,
            colorSpace: linearSRGB
        )
    }

    private func narrowRGBColorSpace() -> CGColorSpace {
        CGColorSpace(
            calibratedRGBWhitePoint: [0.95047, 1.0, 1.08883],
            blackPoint: [0.0, 0.0, 0.0],
            gamma: [2.2, 2.2, 2.2],
            matrix: [
                0.36, 0.30, 0.20,
                0.30, 0.36, 0.20,
                0.20, 0.30, 0.36,
            ]
        )!
    }

    private func maximumAlpha(in image: CGImage) -> UInt8 {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ci = CIImage(cgImage: image)
        makeContext().render(
            ci,
            toBitmap: &pixels,
            rowBytes: image.width * 4,
            bounds: ci.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }.max() ?? 0
    }
}
