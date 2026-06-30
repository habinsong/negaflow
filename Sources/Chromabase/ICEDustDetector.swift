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
        // 감마 대비 임계. 자동/Region은 보수적, 브러시는 사용자가 결함을 지목했으므로 더 낮춘다.
        let absThreshold = Float((aggressive ? 0.055 : 0.14) - sensitivity * (aggressive ? 0.05 : 0.08))
        // 국소 텍스처(그레인) 대비 k배 이상이어야 통과(a contrario 정신). 브러시 모드에선 완화.
        let kNoise = Float((aggressive ? 1.9 : 4.5) - sensitivity * (aggressive ? 0.8 : 1.5))
        // 절대 대비가 큰 신호는 noiseScale(국소 grain) 게이트를 면제한다. 뚱뚱한 먼지는 top-hat 이
        // 덩어리 전체(특히 중앙)에 퍼져 자기 국소평균(noiseScale)을 끌어올려 자기억제되므로 절대 강도로
        // 구제한다. 면제선은 민감도에 연동 — 강도↑일수록 낮춰(×2) 뚱뚱한 먼지 전체를 살리고, 강도↓에선
        // 높여(×5) 보수적으로 둔다. grain 은 절대값이 작아(≪ strongMag) 어느 강도에서도 면제되지 않는다.
        let strongMag = absThreshold * Float(5 - sensitivity * 3)

        var cand = [Bool](repeating: false, count: n)
        for i in 0..<n
        where field.valid[i]
            && (region?[i] ?? true)
            && field.dustMag[i] > absThreshold
            && (field.dustMag[i] > kNoise * field.noiseScale[i] || field.dustMag[i] > strongMag) {
            cand[i] = true
        }
        return cand
    }
}
