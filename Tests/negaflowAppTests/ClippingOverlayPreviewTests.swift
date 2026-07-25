import Chromabase
import CoreGraphics
import CoreImage
import XCTest
@testable import negaflowApp

final class ClippingOverlayPreviewTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    func testPreviewRendererEmitsSeparateOverlayOnlyWhenEnabled() throws {
        let input = try makeInput()
        let enabled = try DevelopFrameRenderer.render(makeSnapshot(input: input, overlayEnabled: true))
        let disabled = try DevelopFrameRenderer.render(makeSnapshot(input: input, overlayEnabled: false))

        let overlay = try XCTUnwrap(enabled.clippingOverlay)
        XCTAssertNotNil(enabled.clippingOverlayBase)
        XCTAssertNil(disabled.clippingOverlay)
        XCTAssertNil(disabled.clippingOverlayBase)
        XCTAssertGreaterThan(maximumAlpha(in: overlay), 127)
        XCTAssertEqual(enabled.developed.width, disabled.developed.width)
        XCTAssertEqual(enabled.developed.height, disabled.developed.height)
    }

    func testPreviewRendererKeepsDestinationGamutWarningSeparateFromChannelClipping() throws {
        let profile = try XCTUnwrap(narrowRGBColorSpace().copyICCData() as Data?)
        let settings = SoftProofSettings(
            isEnabled: true,
            colorSpace: .sRGB,
            iccProfileData: profile
        )
        let input = try makeInput()

        let enabled = try DevelopFrameRenderer.render(makeSnapshot(
            input: input,
            overlayEnabled: false,
            softProof: settings,
            destinationGamutWarningEnabled: true
        ))
        let disabled = try DevelopFrameRenderer.render(makeSnapshot(
            input: input,
            overlayEnabled: false,
            softProof: settings,
            destinationGamutWarningEnabled: false
        ))

        XCTAssertNotNil(enabled.destinationGamutOverlay)
        XCTAssertNotNil(enabled.destinationGamutOverlayBase)
        XCTAssertNil(enabled.clippingOverlay)
        XCTAssertNil(disabled.destinationGamutOverlay)
        XCTAssertNil(disabled.destinationGamutOverlayBase)
    }

    func testSoftProofPixelsNeverLeakIntoGeneratedThumbnail() throws {
        let input = try makeInput()
        let baseline = try DevelopFrameRenderer.render(makeSnapshot(
            input: input,
            overlayEnabled: false,
            needsThumbnail: true
        ))
        let proofed = try DevelopFrameRenderer.render(makeSnapshot(
            input: input,
            overlayEnabled: false,
            softProof: SoftProofSettings(
                isEnabled: true,
                colorSpace: .sRGB,
                simulation: .paperAndBlackInk,
                media: SoftProofMedia(
                    white: SoftProofXYZ(x: 0.78, y: 0.84, z: 0.70),
                    black: SoftProofXYZ(x: 0.04, y: 0.05, z: 0.03)
                )
            ),
            needsThumbnail: true
        ))

        let baselineThumbnail = try XCTUnwrap(baseline.thumbnail)
        let proofedThumbnail = try XCTUnwrap(proofed.thumbnail)
        XCTAssertEqual(pixelBytes(baselineThumbnail), pixelBytes(proofedThumbnail))
        XCTAssertNotEqual(pixelBytes(baseline.developed), pixelBytes(proofed.developed))
        XCTAssertNotNil(proofed.thumbnailBase)
    }

    private func makeSnapshot(
        input: CGImage,
        overlayEnabled: Bool,
        softProof: SoftProofSettings = .disabled,
        destinationGamutWarningEnabled: Bool = false,
        needsThumbnail: Bool = false
    ) -> DevelopFrameSnapshot {
        var params = DevelopParameters()
        params.filmType = .colorPositive
        params.exposure = 4
        return DevelopFrameSnapshot(
            rawScanURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("negaflow-clipping-preview-\(UUID().uuidString).tiff"),
            preloadedRaw: input,
            cleanedRawURL: nil,
            filmType: .colorPositive,
            params: params,
            preset: nil,
            imageTransform: .identity,
            cachedBase: nil,
            baseKey: FilmBaseCacheKey(
                filmType: .colorPositive,
                mode: params.baseEstimationMode,
                manualBaseRGB: nil,
                filmStockDminID: nil
            ),
            needsRawPreview: false,
            needsNeutralPreview: false,
            needsDebugPreviews: false,
            softProof: softProof,
            destinationGamutWarningEnabled: destinationGamutWarningEnabled,
            clippingOverlayEnabled: overlayEnabled,
            proxyMaxDimension: 64,
            needsThumbnail: needsThumbnail
        )
    }

    private func makeInput() throws -> CGImage {
        let color = try XCTUnwrap(
            CIColor(red: 0.75, green: 0.55, blue: 0.35, alpha: 1, colorSpace: linear)
        )
        let image = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let context = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        return try XCTUnwrap(
            context.createCGImage(image, from: image.extent, format: .RGBA16, colorSpace: linear)
        )
    }

    private func maximumAlpha(in image: CGImage) -> UInt8 {
        let ci = CIImage(cgImage: image)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        CIContext().render(
            ci,
            toBitmap: &pixels,
            rowBytes: image.width * 4,
            bounds: ci.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }.max() ?? 0
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

    private func pixelBytes(_ image: CGImage) -> [UInt8] {
        let ci = CIImage(cgImage: image)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        CIContext().render(
            ci,
            toBitmap: &pixels,
            rowBytes: image.width * 4,
            bounds: ci.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return pixels
    }
}
