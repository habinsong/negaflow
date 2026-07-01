import Foundation
import CoreImage
import CoreGraphics

// MARK: - FilmEmulation (슬라이드 필름 특성 시뮬레이션)
//
// 현상 결과는 log/raw 처럼 플랫한 positive 다. 이 스테이지는 그 위에 **특정 슬라이드 필름의
// 물리적 색·톤 응답**을 재현한다. 대충 룩만 흉내내는 게 아니라, 공식 데이터시트의 채널별
// 특성곡선·분광 염료밀도·MTF 와 컬러 필름 화학(inter-image effect)을 모델로 옮겨, 밝기·장면이
// 달라도 같은 필름 응답이 일관되게 나오도록 한다.
//
// 근거 데이터시트:
//   • Kodak EKTACHROME Film E100 (Pub. E-4000) — CHARACTERISTIC/SPECTRAL/MTF 그래프
//   • Kodak EKTACHROME 100D 5294 (Pub. H-1-5294) — 동일 계열 시네 버전
//   • FUJICHROME Velvia 50 [RVP50] (Ref. AF3-0221E2) — 전 그래프
//
// 모델 3축(각 데이터시트 개념에 대응):
//   1) 채널별 특성곡선 T_r/T_g/T_b (D-logE)  → 대비 + 밝기대별 색 크로스오버(섀도우/하이라이트 캐스트).
//      채널마다 toe/gamma/shoulder/pivot 이 달라, 어느 밝기에서도 그 필름의 톤·색 응답이 재현된다.
//   2) 분광 유도 색 매트릭스 M (행합=1)        → 염료 순도/불요흡수에서 오는 고유 hue 회전 + 기본 채도.
//   3) inter-image effect(IIE) 채도            → DIR 커플러의 노출 의존 채도("빛이 많을수록 채도↑").
//      고정 LUT 가 못 살리는 "필름의 생명" 을 밝기·채도 가중 채도로 근사한다.
//   + MTF acutance                             → 엣지 강조(Velvia 는 MTF 100% 초과 → 강함).
//
// 위 모델로 절차적 3D LUT(CIColorCubeWithColorSpace, sRGB 공간)를 생성·캐시한다. 특정 컷에
// 오버핏하지 않도록 모든 계수는 hue/휘도 일반 규칙으로만 동작한다.

public enum FilmEmulation: String, Codable, Sendable, CaseIterable, Identifiable {
    case none
    case ektachromeE100
    case velvia50

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none:           return "None"
        case .ektachromeE100: return "Kodak Ektachrome E100"
        case .velvia50:       return "Fujichrome Velvia 50"
        }
    }
}

// MARK: - Stage

public enum FilmEmulationStage {
    /// 필름 룩을 적용한다. `.none` 이거나 intensity≈0 이면 입력을 그대로 통과.
    public static func apply(to image: CIImage, emulation: FilmEmulation, intensity: Double) -> CIImage {
        guard emulation != .none else { return image }
        let strength = min(max(intensity, 0), 1)
        guard strength > 1e-3 else { return image }

        let extent = image.extent
        let cube = FilmEmulationLUT.cube(for: emulation, intensity: strength)
        var img = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": cube.dimension,
            "inputCubeData": cube.data,
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])

        // MTF(acutance): 데이터시트 R/G/B modulation transfer 를 엣지 강조로 근사. 스캔 노이즈
        // 증폭을 막으려 약하게, intensity 로 스케일. uniform 영역엔 영향 없음.
        let acutance = FilmEmulationProfile.of(emulation).acutance
        if acutance.intensity > 1e-3 {
            img = img.applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius": acutance.radius,
                "inputIntensity": acutance.intensity * strength,
            ])
        }
        return img.cropped(to: extent)
    }
}

// MARK: - Profile (데이터시트 유도 파라미터)

/// 채널 특성곡선 파라미터. sRGB-감마 0..1 도메인에서 동작(감마≈로그라 D-logE 형태를 잘 근사).
struct ToneCurveParams {
    var contrast: Double   // S-커브 강도(0 = 없음). 데이터시트 straight-line gamma.
    var black: Double      // toe. +면 딥 블랙(크러시), -면 섀도우 리프트.
    var white: Double      // shoulder(<1 이면 하이라이트 압축).
    var lift: Double       // 채널 수직 오프셋 → 밝기대별 색 캐스트(크로스오버).
    var pivot: Double      // S 변곡점 위치(중간톤 밝기/색 편향).
}

struct FilmEmulationProfile {
    var toneR: ToneCurveParams
    var toneG: ToneCurveParams
    var toneB: ToneCurveParams
    // 색 매트릭스(행합=1 → 무채색 보존). 대각=채도, 비대각=염료 불요흡수/IIE 색보정(hue 회전).
    var mR: SIMD3<Double>
    var mG: SIMD3<Double>
    var mB: SIMD3<Double>
    // 밝기대별 색 크로스오버(휘도 가중 틴트). 톤커브가 아니라 여기서 명시적으로 제어한다.
    //   Velvia = 쿨 섀도우 + 웜 하이라이트. E100 = 거의 중립(미세 쿨).
    var shadowTint: SIMD3<Double>
    var highlightTint: SIMD3<Double>
    // inter-image effect: 노출·채도 가중 채도 부스트.
    var iie: Double
    var iieHue: [Double]   // 6색 앵커(R,Y,G,C,B,M) 추가 가중
    // MTF acutance
    var acutance: (radius: Double, intensity: Double)

    static func of(_ emulation: FilmEmulation) -> FilmEmulationProfile {
        switch emulation {
        case .none:
            return FilmEmulationProfile(
                toneR: ToneCurveParams(contrast: 0, black: 0, white: 1, lift: 0, pivot: 0.5),
                toneG: ToneCurveParams(contrast: 0, black: 0, white: 1, lift: 0, pivot: 0.5),
                toneB: ToneCurveParams(contrast: 0, black: 0, white: 1, lift: 0, pivot: 0.5),
                mR: SIMD3(1, 0, 0), mG: SIMD3(0, 1, 0), mB: SIMD3(0, 0, 1),
                shadowTint: .zero, highlightTint: .zero,
                iie: 0, iieHue: [0, 0, 0, 0, 0, 0], acutance: (1.0, 0)
            )

        case .ektachromeE100:
            // E100(E-4000): "low contrast tonal scale", "matched color records for a neutral tone
            // scale", "consistent gray scale rendition throughout the tonal range", "moderately
            // enhanced color saturation", "pleasing natural skin". 저대비·넓은 관용도·중립.
            //   - 톤: 낮은 대비, 채널 균등(전 계조 뉴트럴). 섀도우 살짝 리프트(관용도).
            //   - 매트릭스: 절제된 채도(대각 ~1.055). 스킨 보호 위해 R 은 특히 약하게.
            //   - 크로스오버: 미세 쿨(전 계조에서 아주 옅게). E100 의 "약간 쿨/클린".
            //   - IIE: 약하게. acutance: 선명하되 깔끔.
            return FilmEmulationProfile(
                toneR: ToneCurveParams(contrast: 0.20, black: -0.014, white: 1.0, lift: 0, pivot: 0.5),
                toneG: ToneCurveParams(contrast: 0.20, black: -0.014, white: 1.0, lift: 0, pivot: 0.5),
                toneB: ToneCurveParams(contrast: 0.21, black: -0.012, white: 1.0, lift: 0, pivot: 0.5),
                mR: SIMD3( 1.055, -0.030, -0.025),
                mG: SIMD3(-0.020,  1.055, -0.035),
                mB: SIMD3(-0.018, -0.032,  1.050),
                shadowTint: SIMD3(-0.004, 0.000, 0.009),
                highlightTint: SIMD3(-0.003, 0.000, 0.005),
                iie: 0.08,
                //        R     Y     G     C     B     M
                iieHue: [0.00, 0.00, 0.03, 0.05, 0.05, 0.00],
                acutance: (1.0, 0.12)
            )

        case .velvia50:
            // Velvia 50(RVP50): "world's highest color saturation", 고대비·딥 섀도우, 그린·레드
            // 강조 + 블루 극대화 + 마젠타 부가, 스킨 마젠타 경향, 섀도우 쿨. MTF 100% 초과.
            //   - 톤: 강한 대비, 딥 블랙. 채널 대비는 균등에 가깝게(색 크로스오버는 톤이 아니라 아래
            //     틴트로 제어). 블루만 아주 살짝 대비↑.
            //   - 매트릭스: 강한 채도(대각 ~1.20~1.22) + hue 회전. G 는 블루를 더 빼 옐로-그린(시그니처),
            //     B 는 그린을 더 빼 퓨어/딥 블루, R 은 딥 레드.
            //   - 크로스오버: 쿨 섀도우 + 웜 하이라이트(Velvia 시그니처).
            //   - IIE: 강하게(밝고 채도 있는 곳에서 색이 산다). acutance: 강함.
            return FilmEmulationProfile(
                toneR: ToneCurveParams(contrast: 0.50, black: 0.034, white: 0.99,  lift: 0, pivot: 0.5),
                toneG: ToneCurveParams(contrast: 0.50, black: 0.034, white: 0.99,  lift: 0, pivot: 0.5),
                toneB: ToneCurveParams(contrast: 0.53, black: 0.036, white: 0.985, lift: 0, pivot: 0.5),
                mR: SIMD3( 1.220, -0.120, -0.100),
                mG: SIMD3(-0.080,  1.205, -0.125),
                mB: SIMD3(-0.055, -0.165,  1.220),
                shadowTint: SIMD3(-0.012, -0.004, 0.020),
                highlightTint: SIMD3(0.016, 0.004, -0.012),
                iie: 0.32,
                //        R     Y     G     C     B     M
                iieHue: [0.12, 0.00, 0.20, 0.06, 0.24, 0.14],
                acutance: (1.2, 0.22)
            )
        }
    }
}

// MARK: - 절차적 3D LUT 빌더 + 캐시

enum FilmEmulationLUT {
    struct Cube {
        let dimension: Int
        let data: Data
    }

    private static let dimension = 33
    private static let lock = NSLock()
    private static var cache: [String: Cube] = [:]

    /// (필름, intensity)별 큐브. intensity 는 5% 단위로 양자화해 슬라이더 드래그 중 재빌드를 제한.
    static func cube(for emulation: FilmEmulation, intensity: Double) -> Cube {
        let q = Int((min(max(intensity, 0), 1) * 20).rounded())   // 0...20 (5% 스텝)
        let key = "\(emulation.rawValue)-\(q)"
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let built = build(emulation: emulation, intensity: Double(q) / 20.0)
        lock.lock()
        cache[key] = built
        lock.unlock()
        return built
    }

    private static func build(emulation: FilmEmulation, intensity: Double) -> Cube {
        let dim = dimension
        let p = FilmEmulationProfile.of(emulation)
        var cube = [Float](repeating: 0, count: dim * dim * dim * 4)
        var offset = 0
        let denom = Double(dim - 1)
        for bz in 0..<dim {
            let b = Double(bz) / denom
            for gy in 0..<dim {
                let g = Double(gy) / denom
                for rx in 0..<dim {
                    let r = Double(rx) / denom
                    let src = SIMD3<Double>(r, g, b)
                    var out = mapColor(src, profile: p)
                    // intensity 로 원본↔풀 룩 선형 블렌드.
                    out = src + (out - src) * intensity
                    cube[offset]     = Float(clamp01(out.x))
                    cube[offset + 1] = Float(clamp01(out.y))
                    cube[offset + 2] = Float(clamp01(out.z))
                    cube[offset + 3] = 1
                    offset += 4
                }
            }
        }
        let data = Data(bytes: cube, count: cube.count * MemoryLayout<Float>.size)
        return Cube(dimension: dim, data: data)
    }

    // MARK: 색 변환 모델 (sRGB-감마 0..1 공간)

    private static let lumaW = SIMD3<Double>(0.2126, 0.7152, 0.0722)

    private static func mapColor(_ c: SIMD3<Double>, profile p: FilmEmulationProfile) -> SIMD3<Double> {
        // 1) 채널별 특성곡선 → 대비 + 밝기대별 색 크로스오버.
        var v = SIMD3<Double>(
            toneCurve(c.x, p.toneR),
            toneCurve(c.y, p.toneG),
            toneCurve(c.z, p.toneB)
        )

        // 2) 분광 유도 색 매트릭스(행합=1 → 무채색 보존). 하한만 0 으로.
        v = SIMD3(
            max(0, dot(p.mR, v)),
            max(0, dot(p.mG, v)),
            max(0, dot(p.mB, v))
        )

        // 3) 밝기대별 크로스오버(휘도 가중 틴트). 섀도우/하이라이트에 각각 색을 얹는다.
        let yl = clamp01(dot(v, lumaW))
        let shadowW = (1 - yl) * (1 - yl)
        let highW = yl * yl
        v = v + p.shadowTint * shadowW + p.highlightTint * highW

        // 4) inter-image effect: 노출·채도·hue 가중 채도. 밝고 채도 있는 영역일수록 색이 산다.
        let y = dot(v, lumaW)
        let chroma = max(v.x, max(v.y, v.z)) - min(v.x, min(v.y, v.z))
        let expW = smoothstep(0.12, 0.72, y)       // 빛이 많을수록(밝을수록) 강함
        let protectW = smoothstep(0.02, 0.14, chroma)  // 무채색 보호
        let hueW = 1 + hueBandDelta(hueDegrees(v), p.iieHue)
        let sat = 1 + p.iie * expW * protectW * hueW
        v = SIMD3(repeating: y) + (v - SIMD3(repeating: y)) * sat

        return SIMD3(clamp01(v.x), clamp01(v.y), clamp01(v.z))
    }

    /// 채널 특성곡선. pivot 을 0.5 로 옮겨 S 를 적용한 뒤 되돌리고(변곡점 이동), black/white 로
    /// toe/shoulder, lift 로 수직 오프셋(크로스오버)을 준다.
    private static func toneCurve(_ x: Double, _ p: ToneCurveParams) -> Double {
        let s = sCurvePivot(clamp01(x), pivot: p.pivot)
        var y = x + (s - x) * p.contrast
        y = (y - p.black) / max(p.white - p.black, 1e-4)
        y += p.lift
        return clamp01(y)
    }

    /// 변곡점이 pivot 인 S-커브. x^g 로 pivot→0.5 이동 후 smootherstep, 다시 되돌린다.
    private static func sCurvePivot(_ x: Double, pivot: Double) -> Double {
        let pv = (pivot <= 0.001 || pivot >= 0.999) ? 0.5 : pivot
        let g = log(0.5) / log(pv)
        let xg = pow(x, g)
        let s = smootherstep(xg)
        return pow(clamp01(s), 1 / g)
    }

    private static func smootherstep(_ x: Double) -> Double {
        let t = clamp01(x)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    /// Hermite smoothstep — edge0 이하 0, edge1 이상 1.
    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = clamp01((x - edge0) / max(edge1 - edge0, 1e-6))
        return t * t * (3 - 2 * t)
    }

    /// 6색 앵커(R0°,Y60°,G120°,C180°,B240°,M300°) 델타를 hue 원형 선형보간.
    private static func hueBandDelta(_ hue: Double, _ anchors: [Double]) -> Double {
        guard anchors.count == 6 else { return 0 }
        let seg = hue / 60.0
        let i = Int(floor(seg)) % 6
        let j = (i + 1) % 6
        let f = seg - floor(seg)
        return anchors[i] * (1 - f) + anchors[j] * f
    }

    /// RGB → hue(0..360). 무채색이면 0.
    private static func hueDegrees(_ c: SIMD3<Double>) -> Double {
        let maxV = max(c.x, max(c.y, c.z))
        let minV = min(c.x, min(c.y, c.z))
        let d = maxV - minV
        guard d > 1e-6 else { return 0 }
        var h: Double
        if maxV == c.x {
            h = (c.y - c.z) / d
        } else if maxV == c.y {
            h = 2 + (c.z - c.x) / d
        } else {
            h = 4 + (c.x - c.y) / d
        }
        h *= 60
        if h < 0 { h += 360 }
        return h
    }

    private static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    private static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
}
