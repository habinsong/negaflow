import XCTest
import CoreGraphics
import CoreImage
import Chromabase
@testable import negaflowApp

final class PixelSamplerRenderPipelineTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    func testRendererKeepsUnproofedWorkingBaseOnlyWhenSamplerRequestsIt() throws {
        let input = try makeInput()
        let enabled = try DevelopFrameRenderer.render(snapshot(input: input, needsSampler: true))
        let disabled = try DevelopFrameRenderer.render(snapshot(input: input, needsSampler: false))

        let working = try XCTUnwrap(enabled.workingBase)
        XCTAssertNil(disabled.workingBase)
        let workingReading = try XCTUnwrap(PixelSampler.sample(
            working,
            at: CGPoint(x: 0.5, y: 0.5),
            rgbColorSpace: linear
        ))
        let proofReading = try XCTUnwrap(PixelSampler.sample(
            enabled.developedBase,
            at: CGPoint(x: 0.5, y: 0.5)
        ))
        XCTAssertGreaterThan(abs(workingReading.rgb.x - proofReading.rgb.x), 0.03)
        XCTAssertGreaterThan(abs(workingReading.lab.x - proofReading.lab.x), 1)
    }

    private func snapshot(input: CGImage, needsSampler: Bool) -> DevelopFrameSnapshot {
        var params = DevelopParameters()
        params.filmType = .colorPositive
        return DevelopFrameSnapshot(
            rawScanURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("pixel-sampler-render-\(UUID().uuidString).tif"),
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
            needsRawPreview: true,
            needsNeutralPreview: false,
            needsDebugPreviews: false,
            softProof: SoftProofSettings(
                isEnabled: true,
                colorSpace: .sRGB,
                simulation: .paperAndBlackInk,
                media: SoftProofMedia(
                    white: SoftProofXYZ(x: 0.75, y: 0.78, z: 0.64),
                    black: SoftProofXYZ(x: 0.02, y: 0.02, z: 0.02)
                )
            ),
            needsPixelSamplerBase: needsSampler,
            proxyMaxDimension: 64,
            needsThumbnail: false
        )
    }

    private func makeInput() throws -> CGImage {
        let color = try XCTUnwrap(CIColor(
            red: 0.65,
            green: 0.45,
            blue: 0.25,
            colorSpace: linear
        ))
        let image = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        return try XCTUnwrap(CIContext(options: [.workingColorSpace: linear]).createCGImage(
            image,
            from: image.extent,
            format: .RGBA16,
            colorSpace: linear
        ))
    }
}
