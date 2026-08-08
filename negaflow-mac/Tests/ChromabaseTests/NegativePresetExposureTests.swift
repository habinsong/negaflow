import XCTest
import CoreImage
import simd
@testable import Chromabase

/// 필름 프리셋 선택 시 노출/광원 로직 검증 — 합성 픽스처 + 수치 측정.
///   • 프리셋 경로가 실측 스케일로 정규화해 노출을 보존한다(고정 dmaxNorm 압축 제거).
///   • 광원 프로파일 선택이 base(WB 앵커)에 실제로 반영된다(효과가 있다).
final class NegativePresetExposureTests: XCTestCase {
    private let base = SIMD3<Double>(0.72, 0.55, 0.40)   // 오렌지 마스크 베이스

    /// 얇은 실스캔 모사: 장면이 필름 밀도 물성역(~2.5D)의 일부만 사용(최대 ~0.9D).
    private func thinNegative(width: Int = 200, height: Int = 200) -> CIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let bx = Int(Double(width) * 0.08)
        func b(_ v: Double) -> UInt8 { UInt8(min(255, max(0, Int(v * 255 + 0.5)))) }
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let isBorder = x < bx || x >= width - bx || y < bx || y >= height - bx
                // 내부: 밀도 0~0.9(얇은 사용역). 베이스는 가장자리(밀도 0).
                let density = isBorder ? 0.0 : 0.9 * Double(x) / Double(width)
                let a = pow(10.0, -density)
                bytes[i] = b(base.x * a); bytes[i + 1] = b(base.y * a); bytes[i + 2] = b(base.z * a); bytes[i + 3] = 255
            }
        }
        let cg = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                           bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        return CIImage(cgImage: cg)
    }

    private func geo(_ v: SIMD3<Double>) -> Double { pow(v.x * v.y * v.z, 1.0 / 3.0) }

    // MARK: 노출 보존

    func testPresetScaleTracksMeasuredNotFixedDatasheet() {
        let img = thinNegative()
        let fb = FilmBase(rgb: base, source: .manual)
        let preset = FilmStockDminRegistry.find("kodak-portra-400")!

        let presetStats = NegativeInversion.presetStats(for: img, base: fb, preset: preset)
        let measured = NegativeInversion.sampleStats(img, base: fb)!

        let presetGeo = geo(presetStats.dmaxNorm)
        let measuredGeo = geo(measured.dmaxNorm)
        let fixedGeo = geo(preset.dmaxNorm)   // 데이터시트 밀도역(~2.5D)

        // 스케일 = 실측(노출 보존). 고정 데이터시트 dmaxNorm 이 아니다.
        XCTAssertEqual(presetGeo, measuredGeo, accuracy: max(0.05, measuredGeo * 0.1),
                       "프리셋 스케일이 실측 스케일을 따라야 함 (preset=\(presetGeo) measured=\(measuredGeo))")
        XCTAssertLessThan(presetGeo, fixedGeo * 0.7,
                          "고정 dmaxNorm(\(fixedGeo)) 압축이 제거되어야 함 (preset=\(presetGeo))")
    }

    func testPresetChannelRatioFollowsPreset() {
        // 채널 비율(염료 분리)은 프리셋을 따른다: dmaxNorm 채널비 ≈ preset.dmaxNorm 채널비.
        let img = thinNegative()
        let fb = FilmBase(rgb: base, source: .manual)
        let preset = FilmStockDminRegistry.find("kodak-portra-400")!
        let stats = NegativeInversion.presetStats(for: img, base: fb, preset: preset)
        let sg = geo(stats.dmaxNorm), pg = geo(preset.dmaxNorm)
        for c in 0..<3 {
            let statsRatio = stats.dmaxNorm[c] / sg
            let presetRatio = preset.dmaxNorm[c] / pg
            XCTAssertEqual(statsRatio, presetRatio, accuracy: 0.02,
                           "채널 \(c) 비율이 프리셋 물성을 따라야 함")
        }
    }

    // MARK: 광원 효과

    func testLightSourceShiftsBaseWhiteBalance() {
        let img = thinNegative()
        let engine = ChromabaseEngine()
        let preset = FilmStockDminRegistry.find("kodak-portra-400")!
        func resolve(_ lightID: String?) -> SIMD3<Double> {
            var p = DevelopParameters()
            p.filmType = .colorNegative
            p.baseEstimationMode = .preset
            p.filmStockDminID = preset.id
            p.lightSourceProfileID = lightID
            return engine.resolveFilmBase(for: img, provided: nil, preset: preset, params: p).rgb
        }
        let neutral = resolve("neutral")
        let halogen = resolve("halogen")   // gain R 1.09, G 1.00, B 0.88 (따뜻)
        let led = resolve("white-led")     // gain R 0.98, G 1.00, B 1.04 (차가움)

        // 같은 base 에 게인만 다르게 적용 → 채널비가 예측 방향으로 이동.
        XCTAssertGreaterThan(halogen.x / halogen.z, neutral.x / neutral.z * 1.05,
                             "할로겐: R/B 비 상승(따뜻)")
        XCTAssertLessThan(led.x / led.z, neutral.x / neutral.z * 0.99,
                          "화이트 LED: R/B 비 하락(차가움)")
        // neutral 은 게인 무변경.
        XCTAssertEqual(neutral.x, resolve(nil).x, accuracy: 1e-9, "neutral == 미선택(무변경)")
    }
}
