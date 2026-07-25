import XCTest
import CoreImage
@testable import Chromabase

/// 히스토그램 양끝(0/255) 진단 도구.
///
/// 실측된 문제(2026-07-18): 컬러/흑백 네거티브에서 다섯 타겟 모두 최암부(빈 0)와
/// 최명부(빈 255)에 픽셀이 폭발적으로 몰림. 물리 밀도 모델(C-41 특성곡선)로 만든
/// 넓은 DR 합성 장면을 각 타겟 기본 파라미터로 현상한 뒤, GUI HistogramSampler 와
/// 같은 도메인(sRGB 8bit)에서 **프레임 내부(보더 제외)** 끝 빈 비율을 측정한다.
/// 합성 장면의 끝 빈 비율은 실제 색·계조 품질의 합격 기준이 아니므로 XCTest 품질 게이트로
/// 사용하지 않는다. 색 검증은 정확한 image/reference 쌍의 IT8 전 패치 보고서가 담당한다.
final class HistogramClippingDiagnosticTests: XCTestCase {

    private let filmBase = SIMD3<Double>(0.72, 0.46, 0.28)
    private let bwBase = SIMD3<Double>(repeating: 0.70)
    private let filmGamma = SIMD3<Double>(0.65, 0.62, 0.60)
    private let bwGamma = SIMD3<Double>(repeating: 0.62)
    private let midDensity = 0.60
    private let borderFraction = 0.08

    private func transmission(
        reflectance: SIMD3<Double>, base: SIMD3<Double>, gamma: SIMD3<Double>
    ) -> SIMD3<Double> {
        var t = SIMD3<Double>()
        for c in 0..<3 {
            let logE = log10(max(reflectance[c], 1e-6) / 0.18)
            let d = max(0.0, midDensity + gamma[c] * logE)
            t[c] = base[c] * pow(10.0, -d)
        }
        return t
    }

    enum Scene: String, CaseIterable {
        case normal      // 하늘 + 미드 + 섀도 램프 + 스펙큘러/딥블랙 패치
        case skyDominant // 스펙큘러 없는 대면적 하늘(전형 야외 스냅)
        case lowKey      // 저조도 실내(얇은 네거)
    }

    /// 장면 반사율(18% 기준 선형). 밴드: 0=상단, 1=중단, 2=하단. u = 밴드 내 가로 위치 0...1.
    private func reflectance(scene: Scene, band: Int, u: Double, monochrome: Bool) -> SIMD3<Double> {
        switch scene {
        case .normal:
            switch band {
            case 0:
                let level = 0.45 + u * 0.50
                return monochrome ? SIMD3(repeating: level)
                                  : SIMD3(level * 0.72, level * 0.86, level)
            case 1:
                var refl = SIMD3<Double>(repeating: 0.10 + u * 0.25)
                if !monochrome {
                    if u > 0.30, u < 0.45 { refl = SIMD3(0.45, 0.10, 0.08) }
                    if u > 0.60, u < 0.75 { refl = SIMD3(0.10, 0.22, 0.07) }
                }
                return refl
            default:
                if u > 0.86 { return SIMD3(repeating: 1.6) }
                if u > 0.72 { return SIMD3(repeating: 0.006) }
                return SIMD3(repeating: 0.015 + u * 0.065)
            }
        case .skyDominant:
            // 상단 2개 밴드 = 하늘 램프(0.5→1.0), 하단 = 그늘 진 전경(0.03→0.2).
            if band < 2 {
                let level = 0.50 + (u * 0.5 + Double(band) * 0.25)
                let clamped = min(level, 1.0)
                return monochrome ? SIMD3(repeating: clamped)
                                  : SIMD3(clamped * 0.72, clamped * 0.86, clamped)
            }
            return SIMD3(repeating: 0.03 + u * 0.17)
        case .lowKey:
            // 실내 저조도: 대부분 −3~−1.5 스탑, 작은 광원 하나.
            if band == 0, u > 0.45, u < 0.55 { return SIMD3(repeating: 1.2) }
            return SIMD3(repeating: 0.022 + u * 0.05 + Double(band) * 0.015)
        }
    }

    private func makeNegative(
        scene: Scene, width: Int, height: Int,
        base: SIMD3<Double>, gamma: SIMD3<Double>, monochrome: Bool
    ) -> CIImage {
        let bx = Int(Double(width) * borderFraction), by = Int(Double(height) * borderFraction)
        var floats = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
                var t = base
                if !isBorder {
                    let u = Double(x - bx) / Double(width - 2 * bx - 1)
                    let innerH = height - 2 * by
                    let band = min((y - by) * 3 / max(innerH, 1), 2)
                    let refl = reflectance(scene: scene, band: band, u: u, monochrome: monochrome)
                    t = transmission(reflectance: refl, base: base, gamma: gamma)
                }
                floats[i] = Float(t.x); floats[i + 1] = Float(t.y)
                floats[i + 2] = Float(t.z); floats[i + 3] = 1
            }
        }
        return CIImage(
            bitmapData: Data(bytes: floats, count: floats.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
    }

    private struct Distribution {
        var shadow: SIMD3<Double>
        var highlight: SIMD3<Double>
        var lumaPercentiles: [Int]   // 8bit: p0.1 p1 p5 p50 p95 p99 p99.9
        var maxShadow: Double { max(shadow.x, max(shadow.y, shadow.z)) }
        var maxHighlight: Double { max(highlight.x, max(highlight.y, highlight.z)) }
    }

    /// 프레임 내부(보더 제외)만 GUI HistogramSampler 도메인(sRGB 8bit)에서 측정.
    private func measureInner(
        _ image: CIImage, width: Int, height: Int
    ) -> Distribution {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: srgb,
        ])
        var out = [UInt8](repeating: 0, count: width * height * 4)
        ctx.render(image, toBitmap: &out, rowBytes: width * 4,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height),
                   format: .RGBA8, colorSpace: srgb)
        let bx = Int(Double(width) * borderFraction) + 1
        let by = Int(Double(height) * borderFraction) + 1
        var s = SIMD3<Double>(), h = SIMD3<Double>()
        var lumas: [Int] = []
        var n = 0.0
        // 렌더 좌표계는 y-플립될 수 있으나 보더가 대칭이라 내부 크롭은 동일하다.
        for y in by..<(height - by) {
            for x in bx..<(width - bx) {
                let i = (y * width + x) * 4
                n += 1
                for c in 0..<3 {
                    if out[i + c] == 0 { s[c] += 1 }
                    if out[i + c] == 255 { h[c] += 1 }
                }
                let luma = 0.2126 * Double(out[i]) + 0.7152 * Double(out[i + 1])
                    + 0.0722 * Double(out[i + 2])
                lumas.append(Int(luma.rounded()))
            }
        }
        lumas.sort()
        func pct(_ p: Double) -> Int {
            lumas[max(0, min(lumas.count - 1, Int(Double(lumas.count) * p)))]
        }
        return Distribution(
            shadow: s / n, highlight: h / n,
            lumaPercentiles: [pct(0.001), pct(0.01), pct(0.05), pct(0.5),
                              pct(0.95), pct(0.99), pct(0.999)]
        )
    }

    private func develop(
        _ image: CIImage, base: SIMD3<Double>,
        target: DevelopTarget, filmType: FilmType
    ) -> CIImage {
        var params = DevelopParameters()
        params.filmType = filmType
        params.developTarget = target
        return ChromabaseEngine().develop(
            image: image, base: FilmBase(rgb: base, source: .border), params: params)
    }

    private let allTargets: [DevelopTarget] = [.main, .print, .noritsu, .sp3000, .f135, .hr, .rescue]

    private func runScene(_ scene: Scene, filmType: FilmType) {
        let width = 320, height = 200
        let mono = filmType == .bwNegative
        let image = makeNegative(
            scene: scene, width: width, height: height,
            base: mono ? bwBase : filmBase, gamma: mono ? bwGamma : filmGamma,
            monochrome: mono)
        for target in allTargets {
            let developed = develop(image, base: mono ? bwBase : filmBase,
                                    target: target, filmType: filmType)
            let d = measureInner(developed, width: width, height: height)
            print(String(
                format: "[hist-diag] %@ %@ %@ shadow0=(%.4f %.4f %.4f) hi255=(%.4f %.4f %.4f) lumaP=%@",
                mono ? "bw" : "color", scene.rawValue, String(describing: target),
                d.shadow.x, d.shadow.y, d.shadow.z,
                d.highlight.x, d.highlight.y, d.highlight.z,
                d.lumaPercentiles.description))
            XCTAssertLessThan(
                d.maxShadow,
                0.01,
                "\(filmType) \(scene.rawValue) \(target): 0 끝 빈 비율 \(d.maxShadow)"
            )
            XCTAssertLessThan(
                d.maxHighlight,
                0.01,
                "\(filmType) \(scene.rawValue) \(target): 255 끝 빈 비율 \(d.maxHighlight)"
            )
        }
    }

    func testColorNegativeEndBins() {
        runScene(.normal, filmType: .colorNegative)
        runScene(.skyDominant, filmType: .colorNegative)
        runScene(.lowKey, filmType: .colorNegative)
    }

    func testBWNegativeEndBins() {
        runScene(.normal, filmType: .bwNegative)
        runScene(.skyDominant, filmType: .bwNegative)
        runScene(.lowKey, filmType: .bwNegative)
    }
}
