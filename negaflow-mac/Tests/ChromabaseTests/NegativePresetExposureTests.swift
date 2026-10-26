import XCTest
import CoreImage
import simd
@testable import Chromabase

/// Fixed stock calibration and light-source application; no per-frame range fitting.
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

    func testPresetScaleIsFixedAcrossDifferentDensityDistributions() {
        let preset = FilmStockDminRegistry.find("kodak-portra-400")!
        let fb = FilmBase(rgb: base, source: .manual)
        let thin = thinNegative()
        let dense = thin.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0.3, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0.7, w: 0),
        ])
        let first = NegativeInversion.presetStats(for: thin, base: fb, preset: preset)
        let second = NegativeInversion.presetStats(for: dense, base: fb, preset: preset)
        XCTAssertEqual(first, second)
        XCTAssertEqual(geo(first.dmaxNorm), 1.55, accuracy: 1e-9)
    }

    func testPresetChannelRangeUsesFixedRelativeFactor() throws {
        let img = thinNegative()
        let fb = FilmBase(rgb: base, source: .manual)
        for id in ["kodak-portra-400", "fuji-c200", "vision3-250d"] {
            let preset = try XCTUnwrap(FilmStockDminRegistry.find(id))
            let stats = NegativeInversion.presetStats(for: img, base: fb, preset: preset)
            for c in 0..<3 {
                XCTAssertEqual(stats.dmaxNorm[c] / 1.55, preset.relativeRangeFactor[c], accuracy: 1e-9)
            }
        }
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
