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

    /// 필름 모드의 채널 범위 = 자동 실측 범위 × 필름 상대 계수(데이터시트에서 믿을 수 있는 필름 사이
    /// 상대 차이). 데이터시트(Status M) 비율로 통째로 바꾸면 스캐너 채널과 어긋나 파랗게 반전됐다.
    func testPresetChannelRangeIsMeasuredTimesFilmRelativeFactor() throws {
        let img = thinNegative()
        let fb = FilmBase(rgb: base, source: .manual)
        let measured = try XCTUnwrap(NegativeInversion.sampleStats(img, base: fb))
        for id in ["kodak-portra-400", "fuji-c200", "vision3-250d"] {
            let preset = try XCTUnwrap(FilmStockDminRegistry.find(id))
            let stats = NegativeInversion.presetStats(for: img, base: fb, preset: preset)
            let factor = preset.relativeRangeFactor
            XCTAssertEqual(geo(factor), 1, accuracy: 1e-9)
            for c in 0..<3 {
                XCTAssertEqual(stats.dmaxNorm[c] / measured.dmaxNorm[c], factor[c], accuracy: 1e-9)
            }
            XCTAssertEqual(stats.blackInput, measured.blackInput)
            XCTAssertEqual(stats.midDensity, measured.midDensity)
        }
        XCTAssertNotEqual(FilmStockDminRegistry.find("fuji-c200")!.relativeRangeFactor,
                          FilmStockDminRegistry.find("vision3-250d")!.relativeRangeFactor,
                          "필름마다 상대 차이가 남아야 한다")
    }

    /// 스캐너 채널의 밀도 범위는 데이터시트와 다르다(실측 B/R 1.23~1.86 vs 1.10). 그래도 필름 모드가
    /// 중립 웨지를 자동 모드만큼 중립으로 반전해야 한다 — 예전엔 b* −2~−13 파랗게 갔다.
    func testFilmModeKeepsNeutralsWhenScannerRangesDifferFromDatasheet() throws {
        let width = 420, height = 120
        let slopes = SIMD3<Double>(0.85, 1.0, 1.30)   // 스캐너형 채널 기울기(파랑 범위가 넓다)
        let image = SyntheticScan.makeImage(width: width, height: height) { x, _ in
            let border = x < 20 || x >= width - 20
            let d = border ? 0.0 : 0.05 + 1.2 * Double(x - 20) / Double(width - 41)
            return SIMD3(base.x * pow(10, -d * slopes.x), base.y * pow(10, -d * slopes.y),
                         base.z * pow(10, -d * slopes.z))
        }
        let engine = ChromabaseEngine()
        func meanRB(_ configure: (inout DevelopParameters) -> Void) -> Double {
            var p = DevelopParameters(); p.filmType = .colorNegative
            configure(&p)
            let out = engine.develop(image: image, base: FilmBase(rgb: base, source: .manual), params: p)
            var bmp = [Float](repeating: 0, count: width * height * 4)
            ChromabaseEngine.sharedLinearRenderContext.render(
                out, toBitmap: &bmp, rowBytes: width * 16, bounds: image.extent, format: .RGBAf,
                colorSpace: SyntheticScan.linear)
            var r = 0.0, b = 0.0
            for x in stride(from: 120, to: 300, by: 4) { let i = (60 * width + x) * 4; r += Double(bmp[i]); b += Double(bmp[i + 2]) }
            return r / b
        }
        let auto = meanRB { _ in }
        let film = meanRB { $0.baseEstimationMode = .preset; $0.filmStockDminID = "kodak-portra-400" }
        XCTAssertEqual(film / auto, 1, accuracy: 0.05, "필름 모드가 중립을 기울였다 auto R/B \(auto) film \(film)")
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
