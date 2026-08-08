import Foundation

// MARK: - 필름 프로파일 (데이터시트 유도 파라미터)
//
// 실제 계수는 슬라이드/네거티브 파일로 나눠 둔다. 여기에는 자료형과 분기만 둔다.

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
    var shadowTint: SIMD3<Double>
    var highlightTint: SIMD3<Double>
    // inter-image effect: 노출·채도 가중 채도 부스트.
    var iie: Double
    var iieHue: [Double]   // 6색 앵커(R,Y,G,C,B,M) 추가 가중
    // MTF acutance
    var acutance: (radius: Double, intensity: Double)

    static func of(_ emulation: FilmEmulation) -> FilmEmulationProfile {
        switch emulation {
        case .none:           return identity
        case .ektachromeE100: return ektachromeE100
        case .provia100F:     return provia100F
        case .velvia50:       return velvia50
        case .portra160:      return portra160
        case .portra400:      return portra400
        case .portra800:      return portra800
        case .ektar100:       return ektar100
        case .ultramax400:    return ultramax400
        case .colorPlus200:   return colorPlus200
        case .fujicolorC200:  return fujicolorC200
        case .pro400H:        return pro400H
        }
    }

    static let identity = FilmEmulationProfile(
        toneR: ToneCurveParams(contrast: 0, black: 0, white: 1, lift: 0, pivot: 0.5),
        toneG: ToneCurveParams(contrast: 0, black: 0, white: 1, lift: 0, pivot: 0.5),
        toneB: ToneCurveParams(contrast: 0, black: 0, white: 1, lift: 0, pivot: 0.5),
        mR: SIMD3(1, 0, 0), mG: SIMD3(0, 1, 0), mB: SIMD3(0, 0, 1),
        shadowTint: .zero, highlightTint: .zero,
        iie: 0, iieHue: [0, 0, 0, 0, 0, 0], acutance: (1.0, 0)
    )
}
