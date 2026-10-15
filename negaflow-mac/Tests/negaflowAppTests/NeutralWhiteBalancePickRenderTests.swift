import XCTest
import CoreGraphics
import CoreImage
import Chromabase
@testable import negaflowApp

/// 중립 스포이드의 앱 경로: 렌더러가 화면 현상과 같은 입력·베이스·측정에서 잰 값으로 풀면, 찍은 점이
/// 화면 현상본에서 중립이 된다(크롭·룩 프리셋·톤 조정이 걸린 상태 포함). 합성 픽스처만 쓴다.
final class NeutralWhiteBalancePickRenderTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private let maskBase = SIMD3<Double>(0.80, 0.55, 0.35)
    private let width = 480, height = 320

    func testPickedPointBecomesNeutralInDisplayedDevelop() throws {
        let input = try makeNegative()
        let preset = try warmPreset()
        var params = DevelopParameters()
        params.filmType = .colorNegative
        params.baseEstimationMode = .manual
        params.manualBaseRGB = maskBase * SIMD3(1.0, 0.95, 0.86)   // 틀린 베이스 → 반전 뒤 캐스트
        params.exposure = 0.5
        params.contrast = 0.3
        params.curveLights = 0.4
        params.warmth = -1.2
        var transform = ImageTransform()
        transform.cropRect = SIMD4(0.1, 0.1, 0.8, 0.8)
        let point = CGPoint(x: 0.55, y: 0.5)

        let sampled = try XCTUnwrap(DevelopFrameRenderer.whiteBalanceInputSample(
            snapshot(input: input, params: params, preset: preset, transform: transform), atBaseUnit: point))
        let solved = try XCTUnwrap(NeutralWhiteBalancePicker.solve(sampled))
        let user = AppModel.userWhiteBalance(solved: solved, preset: preset)
        XCTAssertNotEqual(user.warmth, solved.warmth, accuracy: 1e-6, "프리셋 몫을 빼지 않았다")
        params.warmth = user.warmth
        params.tint = user.tint

        let developed = try DevelopFrameRenderer.render(
            snapshot(input: input, params: params, preset: preset, transform: transform)).developedBase
        let reading = try XCTUnwrap(PixelSampler.sample(developed, at: point, rgbColorSpace: linear)).rgb
        XCTAssertEqual(log2(reading.x / reading.z), 0, accuracy: 0.03, "R/B \(reading)")
        XCTAssertEqual(log2(reading.y / (reading.x * reading.z).squareRoot()), 0, accuracy: 0.03, "G \(reading)")
    }

    private func snapshot(input: CGImage, params: DevelopParameters, preset: LookPreset?,
                          transform: ImageTransform) -> DevelopFrameSnapshot {
        DevelopFrameSnapshot(
            rawScanURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("neutral-pick-\(UUID().uuidString).tif"),
            preloadedRaw: input,
            cleanedRawURL: nil,
            filmType: .colorNegative,
            params: params,
            preset: preset,
            imageTransform: transform,
            cachedBase: nil,
            baseKey: FilmBaseCacheKey(
                filmType: .colorNegative,
                mode: params.baseEstimationMode,
                manualBaseRGB: params.manualBaseRGB,
                filmStockDminID: nil,
                imageTransform: transform
            ),
            needsRawPreview: false,
            needsNeutralPreview: false,
            needsDebugPreviews: false,
            proxyMaxDimension: 240,
            needsThumbnail: false
        )
    }

    /// 가로로 밀도가 변하는 중립 네거티브(오렌지 마스크).
    private func makeNegative() throws -> CGImage {
        var px = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let density = 0.1 + 1.3 * Double(x) / Double(width)
                let v = maskBase * pow(10, -density)
                let i = (y * width + x) * 4
                px[i] = Float(v.x); px[i + 1] = Float(v.y); px[i + 2] = Float(v.z); px[i + 3] = 1
            }
        }
        let image = CIImage(bitmapData: px.withUnsafeBufferPointer { Data(buffer: $0) },
                            bytesPerRow: width * 16, size: CGSize(width: width, height: height),
                            format: .RGBAf, colorSpace: linear)
        return try XCTUnwrap(CIContext(options: [.workingColorSpace: linear]).createCGImage(
            image, from: image.extent, format: .RGBAh, colorSpace: linear))
    }

    private func warmPreset() throws -> LookPreset {
        let json = """
        {"name": "Warm", "version": 1, "filmTypes": ["colorNegative"],
         "tone": {"exposure": 0, "density": 0, "contrast": 0, "highlightRollOff": 0, "blackSoftness": 0},
         "color": {"warmth": 0.6, "tint": -0.3, "colorDepth": 0, "saturation": 0},
         "texture": {"grain": 0, "sharpness": 0, "halation": 0}}
        """
        return try JSONDecoder().decode(LookPreset.self, from: Data(json.utf8))
    }
}
