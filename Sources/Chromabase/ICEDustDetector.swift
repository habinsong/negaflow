import Foundation

// 먼지/이물 후보: 톤 정규화 대비가 국소 텍스처를 충분히 넘는 작은 양극성 결함.
// 형태(면적) 판정은 ICEComponentMask 가 맡는다.
enum ICEDustDetector {
    /// - region: nil이면 전역. 주어지면 그 영역(브러시) 안에서만 후보를 낸다(공간 제한).
    /// - aggressive: true면 사용자가 결함 위치를 칠로 보증한 브러시 모드 — 임계·노이즈 게이트를
    ///   낮춰 흐릿한 저대비 먼지까지 잡는다. false(자동·Region)면 "주변과 크게 다른" 먼지만
    ///   보수적으로 잡아, 넓은 평탄/그라데이션·그레인을 결함으로 오검출하지 않는다.
    ///   공격성은 공간 범위(region)와 독립이다 — Region ICE는 범위를 좁혀도 보수적이어야 한다.
    static func candidates(_ field: ICEContrastField, sensitivity: Double,
                           region: [Bool]? = nil, aggressive: Bool = false) -> [Bool] {
        let n = field.width * field.height
        // 임계(그레인 안전선)는 절대 1 초과로 못 낮춘다 — 실제 1px chromatic 필름 그레인이 폭발하기
        // 때문. 슬라이더가 1.5 까지 올라가도(형태 게이트 완화용) 임계 계산은 s≤1 로 clamp 한다.
        let s = min(1.0, sensitivity)
        // 감마 대비 임계. 자동/Region은 보수적, 브러시는 사용자가 결함을 지목했으므로 더 낮춘다.
        // 단 브러시도 그레인 안전선 아래로는 못 내려간다 — 크로마 그레인/미세 텍스처의 top-hat
        // 진폭(~0.02-0.04)을 하회하면 오검출이 percolation(연결 덩어리화)해 칠 영역이 통째로
        // 마스크가 되고, 복원이 칠 전체를 재합성해 "전체 블러"가 된다.
        let absThreshold = Float((aggressive ? 0.075 : 0.14) - s * (aggressive ? 0.055 : 0.08))
        // 국소 텍스처(그레인) 대비 k배 이상이어야 통과(a contrario 정신). 브러시 모드에선 완화하되
        // 오검출 밀도가 dilate(r2) 페인팅의 병합 한계(~2%) 아래에 머물 수준까지만.
        let kNoise = Float((aggressive ? 3.0 : 4.5) - s * (aggressive ? 0.5 : 1.5))
        // 절대 대비가 큰 신호는 noiseScale(국소 grain) 게이트를 면제한다. 뚱뚱한 먼지는 top-hat 이
        // 덩어리 전체(특히 중앙)에 퍼져 자기 국소평균(noiseScale)을 끌어올려 자기억제되므로 절대 강도로
        // 구제한다. 면제선은 민감도에 연동 — 강도↑일수록 낮춰(×2) 뚱뚱한 먼지 전체를 살리고, 강도↓에선
        // 높여(×5) 보수적으로 둔다. grain 은 절대값이 작아(≪ strongMag) 어느 강도에서도 면제되지 않는다.
        let strongMag = absThreshold * Float(5 - s * 3)
        // 브러시 모드 면제는 "장면 컨텍스트(전영역 중앙값) 대비로도 두드러질 때"만 유효하다.
        // 면제의 목적은 뚱뚱한 먼지의 국소 자기억제 구제이지, 국소대비가 원래 높은 텍스처
        // (나뭇잎/직물/자갈) 면 전체를 통과시키는 것이 아니다 — 텍스처 면에선 중앙값이 높아
        // 면제가 꺼진다(칠 영역 전체 와이프 방지). 매끈한 면에선 중앙값≈0이라 기존과 동일.
        let context = aggressive ? contextFloor(field) : 0

        var cand = [Bool](repeating: false, count: n)
        for i in 0..<n
        where field.valid[i]
            && (region?[i] ?? true)
            && field.dustMag[i] > absThreshold
            && (field.dustMag[i] > kNoise * field.noiseScale[i]
                || (field.dustMag[i] > strongMag && field.dustMag[i] > kNoise * context)) {
            cand[i] = true
        }
        return cand
    }

    /// 검출 영역 전체(valid)의 dustMag 중앙값 = "이 장면의 국소대비 기준 수준"(a contrario 컨텍스트).
    /// 텍스처/그레인 면에선 높고 매끈한 면에선 ~0. 히스토그램 근사로 O(N).
    static func contextFloor(_ field: ICEContrastField) -> Float {
        var hist = [Int](repeating: 0, count: 256)
        var total = 0
        for i in 0..<(field.width * field.height) where field.valid[i] {
            hist[min(255, Int(field.dustMag[i] * 512))] += 1   // 0..0.5 → 0..255(상단 포화)
            total += 1
        }
        guard total > 0 else { return 0 }
        var acc = 0
        for b in 0..<256 {
            acc += hist[b]
            if acc * 2 >= total { return Float(b) / 512 }
        }
        return 0.5
    }

    /// 가는 구조 후보(thinMag = 작은 SE top-hat). 꼬불꼬불 머리카락·가는 스크래치를 "선 자체"로 잡되
    /// 밀집 곡선 사이의 골을 채우지 않는다(멀티스케일 dustMag 가 큰 blob 으로 오인하는 문제 회피).
    /// 형태(길이/aspect) 판정은 scratch 게이트가 맡는다 — 이 후보를 scratch 후보에 OR 한다.
    static func thinCandidates(_ field: ICEContrastField, sensitivity: Double,
                               region: [Bool]? = nil, aggressive: Bool = false) -> [Bool] {
        let n = field.width * field.height
        let s = min(1.0, sensitivity)   // 임계는 그레인 안전선까지만(형태 게이트와 독립)
        let absThreshold = Float((aggressive ? 0.075 : 0.14) - s * (aggressive ? 0.055 : 0.08))
        let kNoise = Float((aggressive ? 3.0 : 4.5) - s * (aggressive ? 0.5 : 1.5))
        let strongMag = absThreshold * Float(5 - s * 3)
        let context = aggressive ? contextFloor(field) : 0   // candidates 와 동일한 텍스처 컨텍스트 게이트
        var cand = [Bool](repeating: false, count: n)
        for i in 0..<n
        where field.valid[i]
            && (region?[i] ?? true)
            && field.thinMag[i] > absThreshold
            && (field.thinMag[i] > kNoise * field.noiseScale[i]
                || (field.thinMag[i] > strongMag && field.thinMag[i] > kNoise * context)) {
            cand[i] = true
        }
        return cand
    }

    /// 히스테리시스(이중 임계) 가는-구조 후보. weak 은 **절대 임계만** 완화하고 국소 SNR 게이트
    /// (kNoise·noiseScale — 그레인 안전선)는 strong 과 동일하게 유지한다. weak 픽셀은 컴포넌트를
    /// 새로 만들지 못하고(호출측이 strong 코어 포함 컴포넌트만 채택) 조각/저대비 gap 을 잇는 역할만
    /// 한다 — 그레인은 strong 코어가 없어 컴포넌트가 생기지 않는다.
    static func thinCandidatesLeveled(_ field: ICEContrastField, sensitivity: Double,
                                      region: [Bool]? = nil, aggressive: Bool = false)
        -> (strong: [Bool], weak: [Bool]) {
        let n = field.width * field.height
        let s = min(1.0, sensitivity)
        let absBase = Float((aggressive ? 0.075 : 0.14) - s * (aggressive ? 0.055 : 0.08))
        let kNoise = Float((aggressive ? 3.0 : 4.5) - s * (aggressive ? 0.5 : 1.5))
        let strongMag = absBase * Float(5 - s * 3)
        let context = aggressive ? contextFloor(field) : 0
        let absWeak = absBase * 0.5
        var strong = [Bool](repeating: false, count: n)
        var weak = [Bool](repeating: false, count: n)
        for i in 0..<n where field.valid[i] && (region?[i] ?? true) {
            let m = field.thinMag[i]
            // SNR 게이트는 두 레벨 공통(그레인 안전). 절대 임계만 strong/weak 로 나뉜다.
            guard m > kNoise * field.noiseScale[i] || (m > strongMag && m > kNoise * context) else { continue }
            if m > absBase { strong[i] = true; weak[i] = true }
            else if m > absWeak { weak[i] = true }
        }
        return (strong, weak)
    }
}
