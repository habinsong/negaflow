import Foundation

// 먼지/이물 후보: 톤 정규화 대비가 국소 텍스처를 충분히 넘는 작은 양극성 결함.
// 형태(면적) 판정은 DefectComponentMask 가 맡는다.
enum DefectDustDetector {
    /// strongMag 절대 면제의 컨텍스트 배수(strong 레벨 전용). 면제는 "고립된 강한 결함"(뚱뚱 먼지의
    /// 자기억제 구제) 전용이다 — 원거리 텍스처(farTexture)보다 이만큼 두드러질 때만 허용해, busy
    /// 텍스처/디테일 섬·구조물 격자(창문 등)·긴 구조 띠(도로선/파이프)의 강한 정상 대비가 SNR 게이트를
    /// 우회해 strong 코어를 만드는 것을 막는다(구조물 오탐·칠 면적 와이프의 원인). 고립 먼지는 far
    /// 박스(반경 36)에서 자기 기여가 ~10% 수준으로 희석돼 면제가 유지된다.
    ///
    /// 중요: 이 게이트는 weak(soft) 레벨에는 적용하지 않는다 — soft 는 기존 규칙 그대로 두어 텍스처
    /// 카펫이 한 덩어리로 "연결"된 채 면적/aspect 게이트에서 통째로 기각되게 한다. 픽셀 단위로
    /// 지우면 카펫이 조각나 파편들이 컴팩트 게이트를 개별 통과한다(와이프 재발).
    /// 임계·SNR 배수는 불변 — 구조(컨텍스트) 가드다.
    private static let kFarContext: Float = 6.0

    /// soft(연결성) 판정: 기존 규칙 — SNR 통과 또는 절대 강도 면제.
    @inline(__always)
    private static func passesSoft(_ m: Float, kNoise: Float, noise: Float, strongMag: Float) -> Bool {
        m > kNoise * noise || m > strongMag
    }

    /// hard(코어) 판정: 절대 강도 면제에 farTexture 컨텍스트 게이트를 더한다.
    @inline(__always)
    private static func passesHard(_ m: Float, kNoise: Float, noise: Float,
                                   strongMag: Float, far: Float) -> Bool {
        m > kNoise * noise || (m > strongMag && m > kFarContext * far)
    }

    /// - region: nil이면 전역. 주어지면 그 영역(브러시) 안에서만 후보를 낸다(공간 제한).
    /// - aggressive: true면 사용자가 결함 위치를 칠로 보증한 브러시 모드 — 임계·노이즈 게이트를
    ///   낮춰 흐릿한 저대비 먼지까지 잡는다. false(자동·Region)면 "주변과 크게 다른" 먼지만
    ///   보수적으로 잡아, 넓은 평탄/그라데이션·그레인을 결함으로 오검출하지 않는다.
    ///   공격성은 공간 범위(region)와 독립이다 — 영역 결함 제거는 범위를 좁혀도 보수적이어야 한다.
    static func candidates(_ field: DefectContrastField, sensitivity: Double,
                           region: [Bool]? = nil, aggressive: Bool = false) -> [Bool] {
        let n = field.width * field.height
        // 임계(그레인 안전선)는 절대 1 초과로 못 낮춘다 — 실제 1px chromatic 필름 그레인이 폭발하기
        // 때문. 슬라이더가 1.5 까지 올라가도(형태 게이트 완화용) 임계 계산은 s≤1 로 clamp 한다.
        let s = min(1.0, sensitivity)
        // 감마 대비 임계. 자동/Region은 보수적, 브러시는 사용자가 결함을 지목했으므로 더 낮춘다.
        let absThreshold = Float((aggressive ? 0.055 : 0.14) - s * (aggressive ? 0.05 : 0.08))
        // 국소 텍스처(그레인) 대비 k배 이상이어야 통과(a contrario 정신). 브러시 모드에선 완화.
        let kNoise = Float((aggressive ? 1.9 : 4.5) - s * (aggressive ? 0.8 : 1.5))
        // 절대 대비가 큰 신호는 noiseScale(국소 grain) 게이트를 면제한다. 뚱뚱한 먼지는 top-hat 이
        // 덩어리 전체(특히 중앙)에 퍼져 자기 국소평균(noiseScale)을 끌어올려 자기억제되므로 절대 강도로
        // 구제한다. 면제선은 민감도에 연동 — 강도↑일수록 낮춰(×2) 뚱뚱한 먼지 전체를 살리고, 강도↓에선
        // 높여(×5) 보수적으로 둔다. grain 은 절대값이 작아(≪ strongMag) 어느 강도에서도 면제되지 않는다.
        let strongMag = absThreshold * Float(5 - s * 3)

        var cand = [Bool](repeating: false, count: n)
        for i in 0..<n
        where field.valid[i]
            && (region?[i] ?? true)
            && field.dustMag[i] > absThreshold
            && passesSoft(field.dustMag[i], kNoise: kNoise, noise: field.noiseScale[i], strongMag: strongMag) {
            cand[i] = true
        }
        return cand
    }

    /// 히스테리시스(이중 임계) 먼지 후보.
    ///  strong(hard): 기존 절대 임계 + farTexture 컨텍스트 게이트 — 컴포넌트 채택의 코어 증거.
    ///  weak(soft): 절대 임계 절반 + 기존 면제 규칙(far 게이트 없음) — 컴포넌트를 새로 만들지 못하고
    ///  (호출측이 strong 코어 포함 컴포넌트만 채택) ① 작은 불규칙 먼지의 흐린 가장자리/조각을 잇고
    ///  ② 텍스처 카펫을 한 덩어리로 연결해 면적/aspect 게이트가 통째로 기각하게 한다.
    ///  SNR 게이트(kNoise·noiseScale)는 두 레벨 공통(그레인 안전선, Canny 이중 임계 정신).
    static func candidatesLeveled(_ field: DefectContrastField, sensitivity: Double,
                                  region: [Bool]? = nil, aggressive: Bool = false)
        -> (strong: [Bool], weak: [Bool], trustedStrong: [Bool]) {
        let n = field.width * field.height
        let s = min(1.0, sensitivity)
        let absBase = Float((aggressive ? 0.055 : 0.14) - s * (aggressive ? 0.05 : 0.08))
        let kNoise = Float((aggressive ? 1.9 : 4.5) - s * (aggressive ? 0.8 : 1.5))
        let strongMag = absBase * Float(5 - s * 3)
        let absWeak = absBase * 0.5
        // 미세 이물은 낮은 절대 임계 대신 동일한 국소 SNR/far-context 게이트를 강제한다.
        // 큰 이물은 별도 대형 국소 편차가 내부까지 잡으므로 일반 후보의 자기억제를 피한다.
        let microBase = Float((aggressive ? 0.04 : 0.06) - s * (aggressive ? 0.03 : 0.04))
        let microWeak = microBase * 0.5
        let microKNoise = Float((aggressive ? 1.7 : 4.5) - s * (aggressive ? 0.7 : 1.5))
        let microStrongMag = microBase * 2.5
        let largeBase = Float((aggressive ? 0.07 : 0.12) - s * (aggressive ? 0.04 : 0.07))
        let largeWeak = largeBase * 0.5
        let largeKNoise = Float((aggressive ? 1.9 : 4.5) - s * (aggressive ? 0.8 : 1.5))
        let largeStrongMag = largeBase * 2.0
        var strong = [Bool](repeating: false, count: n)
        var weak = [Bool](repeating: false, count: n)
        // 기존 보수 검출 또는 큰 이물 검출이 직접 확인한 픽셀. 낮은 임계의 micro-only 후보와
        // 구분해, 밀집 미세 입자는 그레인 퓨즈로 버리면서 실제 고대비 먼지 여러 개는 보존한다.
        var trustedStrong = [Bool](repeating: false, count: n)
        for i in 0..<n where field.valid[i] && (region?[i] ?? true) {
            let noise = field.noiseScale[i]
            let microNoise = field.microNoiseScale[i]
            let far = field.farTexture[i]
            let normal = field.dustMag[i]
            let micro = field.microDustMag[i]
            let large = field.largeDustMag[i]
            let normalWeak = normal > absWeak
                && passesSoft(normal, kNoise: kNoise, noise: noise, strongMag: strongMag)
            let microIsWeak = !aggressive && micro > microWeak
                && passesSoft(micro, kNoise: microKNoise, noise: microNoise, strongMag: microStrongMag)
            let largeIsWeak = !aggressive && large > largeWeak
                && passesSoft(large, kNoise: largeKNoise, noise: noise, strongMag: largeStrongMag)
            guard normalWeak || microIsWeak || largeIsWeak else { continue }
            weak[i] = true
            let normalStrong = normal > absBase
                && passesHard(normal, kNoise: kNoise, noise: noise, strongMag: strongMag, far: far)
            let microIsStrong = !aggressive && micro > microBase
                && passesHard(micro, kNoise: microKNoise, noise: microNoise,
                              strongMag: microStrongMag, far: far)
            let largeIsStrong = !aggressive && large > largeBase
                && passesHard(large, kNoise: largeKNoise, noise: noise, strongMag: largeStrongMag, far: far)
            // 여러 고대비 먼지가 가까우면 서로 farTexture를 높여 normalStrong이 전부 꺼질 수 있다.
            // 기존 dustMag가 보수 임계의 1.5배를 넘는 픽셀은 절대 대비 코어로 인정한다. 컴포넌트
            // 단계의 면적·형태·고립 게이트는 그대로라 큰 정상 구조가 이 규칙만으로 채택되지는 않는다.
            let compactAbsoluteStrong = !aggressive && normal > max(0.16, absBase * 1.5)
            if normalStrong || microIsStrong || largeIsStrong {
                strong[i] = true
            }
            if normalStrong || largeIsStrong || compactAbsoluteStrong { trustedStrong[i] = true }
        }
        return (strong, weak, trustedStrong)
    }

    /// 가는 구조 후보(thinMag = 작은 SE top-hat). 꼬불꼬불 머리카락·가는 스크래치를 "선 자체"로 잡되
    /// 밀집 곡선 사이의 골을 채우지 않는다(멀티스케일 dustMag 가 큰 blob 으로 오인하는 문제 회피).
    /// 형태(길이/aspect) 판정은 scratch 게이트가 맡는다 — 이 후보를 scratch 후보에 OR 한다.
    static func thinCandidates(_ field: DefectContrastField, sensitivity: Double,
                               region: [Bool]? = nil, aggressive: Bool = false) -> [Bool] {
        let n = field.width * field.height
        let s = min(1.0, sensitivity)   // 임계는 그레인 안전선까지만(형태 게이트와 독립)
        let absThreshold = Float((aggressive ? 0.055 : 0.14) - s * (aggressive ? 0.05 : 0.08))
        let kNoise = Float((aggressive ? 1.9 : 4.5) - s * (aggressive ? 0.8 : 1.5))
        let strongMag = absThreshold * Float(5 - s * 3)
        var cand = [Bool](repeating: false, count: n)
        for i in 0..<n
        where field.valid[i]
            && (region?[i] ?? true)
            && field.thinMag[i] > absThreshold
            && passesSoft(field.thinMag[i], kNoise: kNoise, noise: field.noiseScale[i], strongMag: strongMag) {
            cand[i] = true
        }
        return cand
    }

    /// 히스테리시스(이중 임계) 가는-구조 후보. strong 은 기존 절대 임계 + far 컨텍스트 게이트,
    /// weak 은 절대 임계만 절반으로 완화(면제 규칙은 기존 그대로 — 연결용). SNR 게이트는 두 레벨
    /// 공통(그레인 안전선). weak 픽셀은 컴포넌트를 새로 만들지 못하고(호출측이 strong 코어 포함
    /// 컴포넌트만 채택) 조각/저대비 gap 을 잇는 역할만 한다.
    static func thinCandidatesLeveled(_ field: DefectContrastField, sensitivity: Double,
                                      region: [Bool]? = nil, aggressive: Bool = false)
        -> (strong: [Bool], weak: [Bool]) {
        let n = field.width * field.height
        let s = min(1.0, sensitivity)
        let absBase = Float((aggressive ? 0.055 : 0.14) - s * (aggressive ? 0.05 : 0.08))
        let kNoise = Float((aggressive ? 1.9 : 4.5) - s * (aggressive ? 0.8 : 1.5))
        let strongMag = absBase * Float(5 - s * 3)
        let absWeak = absBase * 0.5
        var strong = [Bool](repeating: false, count: n)
        var weak = [Bool](repeating: false, count: n)
        for i in 0..<n where field.valid[i] && (region?[i] ?? true) {
            let m = field.thinMag[i]
            guard m > absWeak,
                  passesSoft(m, kNoise: kNoise, noise: field.noiseScale[i], strongMag: strongMag)
            else { continue }
            weak[i] = true
            if m > absBase, passesHard(m, kNoise: kNoise, noise: field.noiseScale[i],
                                       strongMag: strongMag, far: field.farTexture[i]) {
                strong[i] = true
            }
        }
        return (strong, weak)
    }
}
