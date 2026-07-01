import Foundation

// 톤 정규화 대비 필드 (sRGB 감마 도메인).
//
// 입력 rgba는 sRGB 감마(디스플레이) 값이다. 감마가 이미 지각 균일에 가까워, 감마
// 위에서의 국소 대비(top-hat / 중심선-양옆 차)는 암부·중간톤·명부에서 비슷한
// 진폭을 갖는다 — 절대 임계 하나로 톤 전반을 다룰 수 있다. (선형+log 도메인은 암부
// 노이즈를 증폭해 암부 결함을 오히려 놓쳤다.) 결함은 양극성(밝거나 어두움)이다.
struct ICEContrastField {
    let width: Int
    let height: Int
    /// 스크래치 ridge 프로파일용 감마 채널 최대값. 한 염료층만 파인(한 채널만 밝은)
    /// 스크래치도 luma처럼 희석되지 않고 그대로 드러난다(채널 OR).
    let bright: [Float]
    /// 먼지용 양극성 top-hat 크기(채널 OR, ≥0). 감마 대비 단위. 멀티스케일(4/8/12)이라 뚱뚱한
    /// 먼지까지 잡지만, 밀집 곡선 사이의 "골"도 채워 가는 곡선을 큰 blob 으로 오인할 수 있다.
    let dustMag: [Float]
    /// 가는 구조 전용 top-hat(작은 SE radius 4 only). 곡선 간격(>SE)보다 작아 곡선 사이를 채우지
    /// 않으므로, 꼬불꼬불 머리카락·가는 스크래치의 선 자체만 잡는다 — dustMag 의 곡선-사이-채움 문제를
    /// 피해 가는 결함을 "가는 선"으로 보존한다.
    let thinMag: [Float]
    /// 국소 텍스처(그레인) 대비 수준. 임계를 국소 통계로 끌어올린다(a contrario 정신).
    let noiseScale: [Float]
    /// 처리 가능 영역. 클리핑된 흰 명부/순흑 경계의 "넓은 평탄" 영역만 제외.
    let valid: [Bool]

    init(rgba: [Float], width: Int, height: Int) {
        self.width = width
        self.height = height
        let n = width * height
        let clipHigh: Float = 0.985   // 넓은 near-white 면 = 클리핑 명부 → 비대상
        let clipLow: Float = 0.020    // 넓은 near-black 면 = 필름 베이스/레터박스 → 비대상

        var ch = [[Float]](repeating: [Float](repeating: 0, count: n), count: 3)
        var luma = [Float](repeating: 0, count: n)
        var bright = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let o = i * 4
            let r = rgba[o], g = rgba[o + 1], b = rgba[o + 2]
            ch[0][i] = r; ch[1][i] = g; ch[2][i] = b
            luma[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
            bright[i] = max(r, max(g, b))
        }
        self.bright = bright

        // valid: "넓은 평탄" 극단 영역만 제외. opening은 넓은 밝은 면을, closing은 넓은
        // 어두운 면을 보존한다. 작은 먼지·스크래치(고립 극값)는 제거되므로 valid로 남는다.
        let lumaOpen = ICEMorphology.opening(luma, width: width, height: height, radius: 4)
        let lumaClose = ICEMorphology.closing(luma, width: width, height: height, radius: 4)
        var valid = [Bool](repeating: false, count: n)
        for i in 0..<n {
            valid[i] = lumaOpen[i] < clipHigh && lumaClose[i] > clipLow
        }
        self.valid = valid

        // 채널별 양극성 top-hat. SE보다 큰 영역(하늘/넓은 면)은 opening/closing이
        // 보존하므로 top-hat≈0, SE보다 얇은 먼지/스크래치만 남는다.
        // 여러 스케일로 본다 — radius 4는 작은 먼지·얇은 스크래치, 8/12는 짧고 두꺼운(뚱뚱한)
        // 먼지를. 큰 SE일수록 흐릿하고 넓은(저대비) 먼지의 약한 신호를 더 많이 모은다. 어느
        // 스케일에서도 SE보다 큰 정상 면은 top-hat≈0이라 보존된다.
        var mag = [Float](repeating: 0, count: n)
        var thin = [Float](repeating: 0, count: n)   // radius 4 전용(가는 구조)
        for radius in [4, 8, 12] {
            for c in 0..<3 {
                let opened = ICEMorphology.opening(ch[c], width: width, height: height, radius: radius)
                let closed = ICEMorphology.closing(ch[c], width: width, height: height, radius: radius)
                for i in 0..<n {
                    let d = max(ch[c][i] - opened[i], closed[i] - ch[c][i])
                    if d > mag[i] { mag[i] = max(0, d) }
                    if radius == 4, d > thin[i] { thin[i] = max(0, d) }
                }
            }
        }
        self.dustMag = mag
        self.thinMag = thin
        self.noiseScale = ICEMorphology.boxMean(mag, width: width, height: height, radius: 12)
    }
}
