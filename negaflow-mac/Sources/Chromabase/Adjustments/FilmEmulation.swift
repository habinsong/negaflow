import Foundation
import CoreImage
import CoreGraphics

// MARK: - FilmEmulation (필름 특성 시뮬레이션)
//
// 현상 결과는 log/raw 처럼 플랫한 positive 다. 이 스테이지는 그 위에 **특정 필름의 색·톤 응답**을
// 재현한다. 대충 룩만 흉내내는 게 아니라, 공식 데이터시트의 채널별 특성곡선·분광 염료밀도·MTF 와
// 컬러 필름 화학(inter-image effect)을 모델로 옮겨, 밝기·장면이 달라도 같은 필름 응답이 일관되게
// 나오도록 한다.
//
// 슬라이드(E-6)는 관측 대상이 필름 자체라 데이터시트 곡선이 곧 최종 응답이다. 네거티브(C-41)는
// 필름 자체가 최종 결과물이 아니므로, 데이터시트 특성(대비·관용도·염료 특성)에 그 필름이 인화/
// 스캔되어 **렌더된 뒤의** 응답을 합쳐 모델링한다. 그래서 네거티브 프로파일은 전반적으로 대비가
// 낮고 토우가 들려 있다(긴 toe = 넓은 섀도우 관용도).
//
// 근거 자료(제조사 데이터시트 우선, 정성 서술은 제조사 문구 기준):
//   • Kodak EKTACHROME Film E100 (Pub. E-4000), EKTACHROME 100D 5294 (H-1-5294)
//   • FUJICHROME Velvia 50 [RVP50] (Ref. AF3-0221E2)
//   • FUJICHROME PROVIA 100F Professional [RDPIII] (Ref. AF3-036E) — RMS 8, 초고선예도
//   • KODAK PROFESSIONAL PORTRA 160 (E-4051) / 400 (E-4050) / 800 (E-4040)
//   • KODAK PROFESSIONAL EKTAR 100 (E-4046) — "world's finest grain", 고채도
//   • KODAK ULTRAMAX 400 (E-7023) — T-GRAIN, 넓은 관용도, 선명한 채도
//   • FUJICOLOR PRO 400H (Ref. AF3-176E) — 4번째 감광층, 중립 그레이·연조
//   • FUJICOLOR C200 (Ref. AF3-0249E) — Superia 200 계열, 소비자용
//   • Kodak ColorPlus 200 — 제조사 기술 데이터시트가 없어 제품 정보 수준만 반영
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
//
// 이 스테이지는 현상 프로세스(FilmType)를 입력으로 받지 않는다. 즉 어떤 프로세스로 현상했든
// 결과 positive 위에 동일하게 적용된다 — 필름 프리셋은 소스가 아니라 룩이기 때문이다.

public enum FilmEmulation: String, Codable, Sendable, CaseIterable, Identifiable {
    case none
    // 슬라이드(E-6)
    case ektachromeE100
    case provia100F
    case velvia50
    // 네거티브(C-41)
    case portra160
    case portra400
    case portra800
    case ektar100
    case ultramax400
    case colorPlus200
    case fujicolorC200
    case pro400H

    public enum Kind: Sendable {
        case slide
        case negative
    }

    public var id: String { rawValue }

    /// `.none` 은 어느 그룹에도 속하지 않는다(목록 맨 위 단독 항목).
    public var kind: Kind? {
        switch self {
        case .none:
            return nil
        case .ektachromeE100, .provia100F, .velvia50:
            return .slide
        case .portra160, .portra400, .portra800, .ektar100,
             .ultramax400, .colorPlus200, .fujicolorC200, .pro400H:
            return .negative
        }
    }

    public static func films(of kind: Kind) -> [FilmEmulation] {
        allCases.filter { $0.kind == kind }
    }

    /// 필름 상표는 그 실물 필름을 지목하기 위한 지시적(nominative) 사용이다. TRADEMARKS.md 참고.
    public var displayName: String {
        switch self {
        case .none:           return "None"
        case .ektachromeE100: return "Kodak Ektachrome E100"
        case .provia100F:     return "Fujichrome Provia 100F"
        case .velvia50:       return "Fujichrome Velvia 50"
        case .portra160:      return "Kodak Portra 160"
        case .portra400:      return "Kodak Portra 400"
        case .portra800:      return "Kodak Portra 800"
        case .ektar100:       return "Kodak Ektar 100"
        case .ultramax400:    return "Kodak UltraMax 400"
        case .colorPlus200:   return "Kodak ColorPlus 200"
        case .fujicolorC200:  return "Fujicolor C200"
        case .pro400H:        return "Fujicolor Pro 400H"
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

// MARK: - 절차적 3D LUT 빌더 + 캐시

enum FilmEmulationLUT {
    struct Cube {
        let dimension: Int
        let data: Data
    }

    private static let dimension = 33
    private final class CacheState: @unchecked Sendable {
        let lock = NSLock()
        var cubes: [String: Cube] = [:]
    }
    private static let cache = CacheState()

    /// (필름, intensity)별 큐브. intensity 는 5% 단위로 양자화해 슬라이더 드래그 중 재빌드를 제한.
    static func cube(for emulation: FilmEmulation, intensity: Double) -> Cube {
        let q = Int((min(max(intensity, 0), 1) * 20).rounded())   // 0...20 (5% 스텝)
        let key = "\(emulation.rawValue)-\(q)"
        cache.lock.lock()
        if let cached = cache.cubes[key] {
            cache.lock.unlock()
            return cached
        }
        cache.lock.unlock()

        let built = build(emulation: emulation, intensity: Double(q) / 20.0)
        cache.lock.lock()
        cache.cubes[key] = built
        cache.lock.unlock()
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
