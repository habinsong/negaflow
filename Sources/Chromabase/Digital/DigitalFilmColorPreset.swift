import Foundation

// MARK: - DigitalFilmColorPreset (디지털 소스 전용 스톡 색 프리셋)
//
// 가상 현상은 밀도와 대비를 만들지만, 그것만으로는 스톡이 서로 구별되지 않는다. 측정해 보면
// 필름 간 차이가 "채도 크기" 하나로 수렴했다 — 빨강 패치에서 R 값만 0.63→1.66 으로 늘어나고
// 색상 방향은 전 스톡이 같았다. ColorPlus 200 과 Fujicolor C200 의 빨강이 0.754 대 0.760 으로
// 사실상 구별되지 않았는데, 실제로는 하나는 따뜻하고 하나는 빨강을 억제하는 정반대 필름이다.
//
// 그래서 스톡마다 **색상 방향**을 따로 준다. 밝기대별 색조(그레이딩 3영역), 색상별 채도·색조
// (HSL 8밴드), 원색 축(캘리브레이션) 세 가지로 표현하며, 각각 이 저장소가 이미 쓰는
// `ColorGradingStage` / `ColorMixerStage` / `CalibrationStage` 를 그대로 태운다.
//
// 값의 성격을 분명히 해 둔다. 이 계수들은 데이터시트에서 읽은 수치가 아니라, 제조사 기술 문서와
// 공개된 비교 촬영·리뷰에서 **반복적으로 확인되는 정성적 서술**을 색 축으로 옮긴 것이다.
// 스캐너와 현상소가 색에 크게 개입하므로 절대값을 주장할 수 없고, 스톡 사이의 상대적인 방향만
// 재현한다.
//
// 근거로 삼은 서술:
//   • Ektar 100 — 저노출 섀도우가 블루-시안으로 기울고, 체리 레드와 마젠타가 강조되며,
//     컬러 네거티브 중 가장 정확한 시안을 낸다. 스킨은 붉은-주황으로 치우친다.
//   • ColorPlus 200 — 따뜻한 쪽. 빨강·노랑이 풍부하고 스킨이 금빛으로 돌며 명부에 붉은 기가 있다.
//   • Fujicolor C200 — 쿨한 쪽. 초록과 파랑을 강조하고 빨강은 눌리며, 섀도우에 초록이 낀다.
//   • PRO 400H — 네 번째 시안 감광층 때문에 초록에 파랑이 섞인다(Kodak 계열의 노랑기 도는
//     초록과 반대). 중간톤을 중립으로 맞춰도 이 성향이 남는다.
//   • UltraMax 400 — 전반적으로 색이 정직하되 명부 스킨에 빨강이 실린다.
//   • Portra 160/400/800 — 160 은 가장 절제되고, 400 은 따뜻한 스킨에 명부가 파스텔로 가며,
//     800 은 채도가 한 단계 높고 노랑기가 있어 흰색이 누렇게 돈다.
//   • E100 — 중립~쿨. 파랑으로 기우는 성향이 뚜렷하고 섀도우에 초록이 비친다.
//   • Provia 100F — Velvia 계보를 절제한 팔레트. 슬라이드 중 스킨톤이 가장 자연스럽다.
//   • Velvia 50 — 최고 채도에 따뜻한 렌디션. 초록과 파랑·보라가 특히 강하다.

/// 스톡 하나의 색 방향. 세 축 모두 표시 도메인(0…1)에서 동작한다.
public struct DigitalFilmColorPreset: Sendable {
    public var grading: ColorGrading
    public var mixer: ColorMixer
    public var calibration: CalibrationAdjust

    public var isIdentity: Bool {
        grading.isIdentity && mixer.isIdentity && calibration.isIdentity
    }
}

// MARK: - 빌더

/// 프리셋을 읽기 쉽게 쓰기 위한 최소 도우미. 밴드 순서는 `MixerBand` 와 같다
/// (빨강·주황·노랑·초록·바다색·파랑·자주·자홍).
private struct PresetBuilder {
    var grading = ColorGrading()
    var mixer = ColorMixer()
    var calibration = CalibrationAdjust()

    /// 밝기대별 색조. hue 는 색상환 각도(0=빨강, 60=노랑, 120=초록, 180=시안, 240=파랑, 300=자홍).
    mutating func shadows(hue: Double, sat: Double, lum: Double = 0) {
        grading.shadows.hue = hue
        grading.shadows.saturation = sat
        grading.shadows.luminance = lum
    }

    mutating func midtones(hue: Double, sat: Double, lum: Double = 0) {
        grading.midtones.hue = hue
        grading.midtones.saturation = sat
        grading.midtones.luminance = lum
    }

    mutating func highlights(hue: Double, sat: Double, lum: Double = 0) {
        grading.highlights.hue = hue
        grading.highlights.saturation = sat
        grading.highlights.luminance = lum
    }

    mutating func band(_ band: MixerBand, hue: Double = 0, sat: Double = 0, lum: Double = 0) {
        mixer.hue[band.rawValue] = hue
        mixer.saturation[band.rawValue] = sat
        mixer.luminance[band.rawValue] = lum
    }

    mutating func primaries(redHue: Double = 0, redSat: Double = 0,
                            greenHue: Double = 0, greenSat: Double = 0,
                            blueHue: Double = 0, blueSat: Double = 0) {
        calibration.redHue = redHue
        calibration.redSat = redSat
        calibration.greenHue = greenHue
        calibration.greenSat = greenSat
        calibration.blueHue = blueHue
        calibration.blueSat = blueSat
    }

    var preset: DigitalFilmColorPreset {
        DigitalFilmColorPreset(grading: grading, mixer: mixer, calibration: calibration)
    }
}

public extension DigitalFilmColorPreset {

    static func of(_ emulation: FilmEmulation) -> DigitalFilmColorPreset? {
        switch emulation {
        case .none:           return nil
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

    // MARK: 반전(E-6)

    /// E100 — 중립을 지향하되 파랑으로 기운다. 차가운 장면에서 특히 드러나고 섀도우에 초록이
    /// 비친다. 채도를 더 얹지 않는 것이 이 필름의 성격이다.
    static let ektachromeE100: DigitalFilmColorPreset = {
        var b = PresetBuilder()
        b.shadows(hue: 150, sat: 0.055)          // 섀도우의 옅은 초록
        b.midtones(hue: 215, sat: 0.030)
        b.highlights(hue: 220, sat: 0.045)       // 명부가 서늘하게
        b.band(.blue, sat: 0.10)
        b.band(.aqua, sat: 0.06)
        b.band(.orange, sat: -0.06, lum: 0.02)   // 스킨이 과하게 익지 않도록
        b.band(.green, hue: 0.04, sat: -0.02)
        b.primaries(blueHue: 0.06, blueSat: 0.05)
        return b.preset
    }()

    /// Provia 100F — Velvia 팔레트를 절제한 중간 지점. 슬라이드 중 스킨이 가장 자연스럽다는
    /// 평이 일관되므로 주황 밴드를 살리고 초록·파랑은 적당히 둔다.
    static let provia100F: DigitalFilmColorPreset = {
        var b = PresetBuilder()
        b.midtones(hue: 35, sat: 0.035)          // 따뜻한 중간톤
        b.highlights(hue: 205, sat: 0.030)
        b.band(.orange, sat: 0.07, lum: 0.03)    // 스킨
        b.band(.red, sat: 0.05)
        b.band(.green, hue: 0.03, sat: 0.06)
        b.band(.blue, sat: 0.08)
        b.primaries(greenSat: 0.04, blueSat: 0.04)
        return b.preset
    }()

    /// Velvia 50 — 채도가 가장 높고 렌디션이 따뜻하다. 초록과 파랑·보라가 특히 강하다.
    /// 가상 현상이 이미 대비와 채도를 크게 올리므로, 여기서는 **방향**만 준다.
    static let velvia50: DigitalFilmColorPreset = {
        var b = PresetBuilder()
        b.midtones(hue: 25, sat: 0.030)
        b.highlights(hue: 30, sat: 0.040)        // 따뜻한 명부
        b.shadows(hue: 250, sat: 0.045)          // 깊은 그림자는 푸르게
        b.band(.green, hue: -0.04, sat: 0.10)    // 채도 높은 초록
        b.band(.blue, sat: 0.10)
        b.band(.purple, sat: 0.10)
        b.band(.magenta, sat: 0.06)
        b.band(.red, sat: -0.03)                 // 밀도 곡선이 이미 포화 직전까지 올린다
        b.primaries(greenSat: 0.05, blueSat: 0.06)
        return b.preset
    }()

    // MARK: 네거티브(C-41)

    /// Portra 160 — 셋 중 가장 절제된 색과 낮은 대비. 색을 더하기보다 덜어낸다.
    static let portra160: DigitalFilmColorPreset = {
        var b = PresetBuilder()
        b.shadows(hue: 215, sat: 0.042)          // 필름 크로스오버 — 어두운 쪽이 서늘하게
        b.midtones(hue: 40, sat: 0.020)
        b.highlights(hue: 45, sat: 0.030)
        b.band(.orange, sat: 0.03, lum: 0.03)
        b.band(.red, sat: -0.04)
        b.band(.green, hue: 0.03, sat: -0.03)
        b.band(.blue, sat: -0.02)
        return b.preset
    }()

    /// Portra 400 — 따뜻한 스킨, 명부가 파스텔로 뜨는 성향.
    static let portra400: DigitalFilmColorPreset = {
        var b = PresetBuilder()
        b.shadows(hue: 212, sat: 0.050)                // 크로스오버 — 서늘한 그림자
        b.midtones(hue: 38, sat: 0.030)
        b.highlights(hue: 42, sat: 0.055, lum: 0.02)   // 파스텔로 뜨는 명부
        b.band(.orange, sat: 0.05, lum: 0.03)
        b.band(.red, sat: -0.02)
        b.band(.green, hue: 0.04, sat: -0.02)          // 초록이 노랑 쪽으로(코닥 계열)
        b.band(.blue, sat: 0.02)
        b.primaries(redHue: 0.03)
        return b.preset
    }()

    /// Portra 800 — 400 보다 한 단계 짙고 노랑기가 있어 흰색이 누렇게 돈다.
    static let portra800: DigitalFilmColorPreset = {
        var b = PresetBuilder()
        b.shadows(hue: 218, sat: 0.052)                // 크로스오버 — 명부 노랑기와 대비되는 그림자
        b.midtones(hue: 45, sat: 0.034)
        b.highlights(hue: 55, sat: 0.076)              // 누렇게 도는 흰색
        b.band(.yellow, sat: 0.09)
        b.band(.orange, sat: 0.07, lum: 0.02)
        b.band(.red, sat: 0.04)
        b.band(.green, hue: 0.05)
        b.primaries(redHue: 0.04, redSat: 0.04)
        return b.preset
    }()

    /// Ektar 100 — 저노출 섀도우가 블루-시안으로 무너지는 것이 이 필름의 서명이다.
    /// 시안이 정확하고 체리 레드·마젠타가 강조된다.
    static let ektar100: DigitalFilmColorPreset = {
        var b = PresetBuilder()
        b.shadows(hue: 197, sat: 0.105, lum: -0.02)    // 수영장 같다는 블루-시안 섀도우
        b.midtones(hue: 20, sat: 0.025)
        b.highlights(hue: 25, sat: 0.030)
        b.band(.aqua, sat: 0.13)
        b.band(.blue, sat: 0.11)
        b.band(.red, hue: -0.05, sat: 0.11)            // 체리 쪽으로 기운 빨강
        b.band(.magenta, sat: 0.09)
        b.band(.orange, sat: 0.05)                     // 붉은-주황 스킨
        b.band(.green, sat: 0.05)
        b.primaries(redHue: -0.05, redSat: 0.07, blueSat: 0.06)
        return b.preset
    }()

    /// UltraMax 400 — 색은 대체로 정직하고, 명부 스킨에 빨강이 실린다.
    static let ultramax400: DigitalFilmColorPreset = {
        var b = PresetBuilder()
        b.shadows(hue: 205, sat: 0.048)                // 크로스오버
        b.highlights(hue: 15, sat: 0.075)              // 명부에 얹히는 빨강
        b.midtones(hue: 35, sat: 0.025)
        b.band(.red, sat: 0.06)
        b.band(.orange, sat: 0.05, lum: 0.02)
        b.band(.green, hue: 0.03, sat: 0.02)
        b.band(.blue, sat: 0.03)
        b.primaries(redSat: 0.04)
        return b.preset
    }()

    /// ColorPlus 200 — 따뜻한 쪽 끝. 빨강·노랑이 풍부하고 스킨이 금빛으로 돌며 명부에 붉은 기.
    /// 같은 감도의 C200 과 정반대 방향이라, 둘의 대비가 프리셋의 시험대다.
    static let colorPlus200: DigitalFilmColorPreset = {
        var b = PresetBuilder()
        b.shadows(hue: 25, sat: 0.018)                 // 따뜻한 필름이라 그림자만 약하게 남긴다
        b.midtones(hue: 40, sat: 0.055)                // 금빛으로 도는 중간톤
        b.highlights(hue: 22, sat: 0.085)              // 명부의 붉은 기
        b.band(.red, sat: 0.12)
        b.band(.orange, sat: 0.11, lum: 0.03)
        b.band(.yellow, sat: 0.09)
        b.band(.green, hue: 0.06, sat: -0.05)          // 초록이 노랑 쪽으로
        b.band(.blue, sat: -0.07)
        b.band(.aqua, sat: -0.05)
        b.primaries(redSat: 0.08, blueSat: -0.05)
        return b.preset
    }()

    /// Fujicolor C200 — 쿨한 쪽 끝. 초록·파랑을 강조하고 빨강은 눌리며 섀도우에 초록이 낀다.
    static let fujicolorC200: DigitalFilmColorPreset = {
        var b = PresetBuilder()
        b.shadows(hue: 140, sat: 0.090)                // 섀도우에 끼는 초록
        b.midtones(hue: 195, sat: 0.040)
        b.highlights(hue: 200, sat: 0.045)
        b.band(.green, hue: -0.03, sat: 0.13)
        b.band(.aqua, sat: 0.09)
        b.band(.blue, sat: 0.11)
        b.band(.red, sat: -0.11)                       // 눌리는 빨강
        b.band(.orange, sat: -0.07)
        b.band(.yellow, sat: 0.04, lum: 0.02)          // 노랑기 도는 스킨
        b.primaries(redSat: -0.06, greenSat: 0.07, blueSat: 0.06)
        return b.preset
    }()

    /// PRO 400H — 네 번째 시안 감광층이 만드는 "민트빛" 초록이 서명이다. 코닥이 노랑기 도는
    /// 초록을 내는 것과 정반대로, 초록에 파랑이 섞인다. 전반적으로 부드럽고 서늘하다.
    static let pro400H: DigitalFilmColorPreset = {
        var b = PresetBuilder()
        b.shadows(hue: 200, sat: 0.055)
        b.midtones(hue: 190, sat: 0.030)
        b.highlights(hue: 180, sat: 0.050, lum: 0.02)  // 서늘하게 뜨는 파스텔 명부
        b.band(.green, hue: -0.16, sat: 0.05)          // 초록을 파랑 쪽으로 = 민트
        b.band(.aqua, sat: 0.10)
        b.band(.blue, sat: 0.06)
        b.band(.red, sat: -0.06)
        b.band(.orange, sat: -0.04, lum: 0.03)
        b.primaries(greenHue: -0.07, greenSat: 0.05, blueSat: 0.04)
        return b.preset
    }()
}
