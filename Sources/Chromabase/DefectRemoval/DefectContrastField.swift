import Foundation

// 톤 정규화 대비 필드 (sRGB 감마 도메인).
//
// 입력 rgba는 sRGB 감마(디스플레이) 값이다. 감마가 이미 지각 균일에 가까워, 감마
// 위에서의 국소 대비(top-hat / 중심선-양옆 차)는 암부·중간톤·명부에서 비슷한
// 진폭을 갖는다 — 절대 임계 하나로 톤 전반을 다룰 수 있다. (선형+log 도메인은 암부
// 노이즈를 증폭해 암부 결함을 오히려 놓쳤다.) 결함은 양극성(밝거나 어두움)이다.
struct DefectContrastField {
    /// 큰 이물의 내부까지 주변 정상 톤과 비교하는 고정 문맥 반경. ROI 크기에 따라 창이 바뀌면
    /// 같은 결함의 타일/비타일 결과가 달라지므로 물리 픽셀 크기로 고정한다.
    private static let largeDustContextRadius = 80
    /// opening/closing(radius 12)의 유효 지지 반경 24px + far-texture 36px(60px)와 큰 이물
    /// 문맥 중 더 큰 값. 큰 ROI 타일 halo는 최소 이 값을 확보해야 단일 ROI와 결과가 같아진다.
    static let maximumDetectionSupportRadius = largeDustContextRadius

    let width: Int
    let height: Int
    /// 스크래치 ridge 프로파일용 감마 채널 최대값. 한 염료층만 파인(한 채널만 밝은)
    /// 스크래치도 luma처럼 희석되지 않고 그대로 드러난다(채널 OR).
    let bright: [Float]
    /// 먼지용 양극성 top-hat 크기(채널 OR, ≥0). 감마 대비 단위. 멀티스케일(4/8/12)이라 뚱뚱한
    /// 먼지까지 잡지만, 밀집 곡선 사이의 "골"도 채워 가는 곡선을 큰 blob 으로 오인할 수 있다.
    let dustMag: [Float]
    /// 아주 작고 약한 이물용 작은 스케일 top-hat. 기존 thinMag(radius 4)를 재사용해 별도
    /// morphology 비용 없이 보수 임계 아래의 미세 먼지를 검출한다.
    let microDustMag: [Float]
    /// 미세 이물 전용 잡음 바닥. 일반 반경 12 통계는 가까운 먼지 여러 개를 서로의 잡음으로 세어
    /// 자기억제하므로 반경 8로 분리한다. 촘촘한 그레인은 이 창에서도 평균이 높아 계속 기각된다.
    let microNoiseScale: [Float]
    /// 큰 먼지·현상 찌꺼기용 luma 국소 편차. 고정 80px box mean으로 폭 24px를 넘는 결함의
    /// 내부까지 후보로 만든다. 일반 dustMag와 분리해 기존 그레인 통계를 오염시키지 않는다.
    let largeDustMag: [Float]
    /// 가는 구조 전용 top-hat(작은 SE radius 4 only). 곡선 간격(>SE)보다 작아 곡선 사이를 채우지
    /// 않으므로, 꼬불꼬불 머리카락·가는 스크래치의 선 자체만 잡는다 — dustMag 의 곡선-사이-채움 문제를
    /// 피해 가는 결함을 "가는 선"으로 보존한다.
    let thinMag: [Float]
    /// 국소 텍스처(그레인) 대비 수준. 임계를 국소 통계로 끌어올린다(a contrario 정신).
    let noiseScale: [Float]
    /// 원거리(반경 36) 텍스처 수준. strongMag 절대 면제의 컨텍스트 게이트용 — 고립된 뚱뚱 먼지는
    /// 자기 top-hat 이 원거리 평균에선 희석돼 낮고(면제 허용), busy 텍스처/구조물 지대는 원거리도
    /// 높아 면제가 막힌다(디테일 섬 통째 와이프 방지).
    let farTexture: [Float]
    /// 처리 가능 영역. 클리핑된 흰 명부/순흑 경계의 "넓은 평탄" 영역만 제외.
    let valid: [Bool]

    /// - parallel: true면 (반지름×채널) top-hat 9개와 boxMean 2개를 병렬로 계산한다(단일 필드
    ///   경로 — 단일 타일 검출·브러시). 타일 병렬 검출 내부에서는 false 로 넘겨 중첩 병렬(초대형
    ///   스캔의 스레드 과다구독)을 피한다 — 타일 루프가 이미 코어를 채운다. 출력은 두 경로 동일.
    init(rgba: [Float], width: Int, height: Int,
         parallel: Bool = true, extendedDustScales: Bool = false) {
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
        let channels = ch
        let lumaValues = luma
        self.bright = bright

        // valid: "넓은 평탄" 극단 영역만 제외. opening은 넓은 밝은 면을, closing은 넓은
        // 어두운 면을 보존한다. 작은 먼지·스크래치(고립 극값)는 제거되므로 valid로 남는다.
        let lumaOpen = DefectMorphology.opening(lumaValues, width: width, height: height, radius: 4)
        let lumaClose = DefectMorphology.closing(lumaValues, width: width, height: height, radius: 4)
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
        // 채널 3개를 병렬화하고 각 채널 안의 반지름 3개는 순차 처리한다. 기존 9-way 병렬은 각 작업이
        // full-size 임시 배열을 여러 장 할당해 CPU와 메모리 피크를 만들었다. max 결합만 사용하므로
        // 채널별로 먼저 합쳐도 출력은 비트 동일하고, 동시 작업 수와 임시 배열은 1/3 수준으로 줄어든다.
        let combos: [(radius: Int, c: Int)] = [
            (4, 0), (4, 1), (4, 2), (8, 0), (8, 1), (8, 2), (12, 0), (12, 1), (12, 2),
        ]
        @inline(__always) func accumulate(_ radius: Int, _ c: Int, into mag: inout [Float], _ thin: inout [Float]) {
            let chc = ch[c]
            let opened = DefectMorphology.opening(chc, width: width, height: height, radius: radius)
            let closed = DefectMorphology.closing(chc, width: width, height: height, radius: radius)
            for i in 0..<n {
                let d = max(0, max(chc[i] - opened[i], closed[i] - chc[i]))
                if d > mag[i] { mag[i] = d }
                if radius == 4, d > thin[i] { thin[i] = d }
            }
        }
        if parallel {
            let accumulator = DefectContrastAccumulator(count: n)
            DispatchQueue.concurrentPerform(iterations: channels.count) { c in
                let chc = channels[c]
                var localMag = [Float](repeating: 0, count: n)
                var localThin = [Float](repeating: 0, count: n)
                for radius in [4, 8, 12] {
                    let opened = DefectMorphology.opening(chc, width: width, height: height, radius: radius)
                    let closed = DefectMorphology.closing(chc, width: width, height: height, radius: radius)
                    for i in 0..<n {
                        let d = max(0, max(chc[i] - opened[i], closed[i] - chc[i]))
                        if d > localMag[i] { localMag[i] = d }
                        if radius == 4, d > localThin[i] { localThin[i] = d }
                    }
                }
                accumulator.merge(localMag, includeInThin: false)
                accumulator.merge(localThin, includeInThin: true)
            }
            let accumulated = accumulator.snapshot()
            mag = accumulated.magnitude
            thin = accumulated.thinMagnitude
        } else {
            for (radius, c) in combos { accumulate(radius, c, into: &mag, &thin) }
        }
        // 미세 이물은 이미 계산한 radius 4 결과를 낮은 임계로 재사용한다. 큰 이물은 단일 적분영상
        // box mean과의 편차로 본다. 이전 추가 반경 2/4/24/48의 8개 full-buffer opening/closing
        // 단계는 CPU 포화와 프리징을 만들었으므로 제거한다.
        let hasLargeContext = min(width, height) >= 224
        let micro = extendedDustScales ? thin : [Float](repeating: 0, count: n)
        var microNoise = [Float](repeating: 0, count: n)
        var large = [Float](repeating: 0, count: n)
        self.dustMag = mag
        self.microDustMag = micro
        self.thinMag = thin
        // 같은 mag 입력의 반경 12/36은 적분영상을 공유한다. extended 통계까지 포함해 출력 계산은
        // 최대 4-way로 제한하고, 타일 경로(parallel=false)는 전부 순차 실행한다.
        var noise = [Float](); var far = [Float]()
        if parallel {
            let resultCount = extendedDustScales ? (hasLargeContext ? 4 : 3) : 2
            let taskCount = extendedDustScales ? (hasLargeContext ? 3 : 2) : 1
            let boxMeans = ConcurrentResultStore<[Float]>(count: resultCount)
            let magnitude = mag
            let thinMagnitude = thin
            DispatchQueue.concurrentPerform(iterations: taskCount) { k in
                switch k {
                case 0:
                    let paired = DefectMorphology.boxMeans(
                        magnitude, width: width, height: height,
                        radii: [12, 36], parallel: true
                    )
                    boxMeans.set(paired[0], at: 0)
                    boxMeans.set(paired[1], at: 1)
                case 1:
                    boxMeans.set(
                        DefectMorphology.boxMean(thinMagnitude, width: width, height: height, radius: 8),
                        at: 2
                    )
                default:
                    boxMeans.set(
                        DefectMorphology.boxMean(
                            lumaValues, width: width, height: height, radius: Self.largeDustContextRadius
                        ),
                        at: 3
                    )
                }
            }
            let values = boxMeans.snapshot()
            noise = values[0] ?? []
            far = values[1] ?? []
            if extendedDustScales { microNoise = values[2] ?? microNoise }
            if extendedDustScales, hasLargeContext, let background = values[3] {
                for i in 0..<n { large[i] = abs(lumaValues[i] - background[i]) }
            }
        } else {
            let paired = DefectMorphology.boxMeans(
                mag, width: width, height: height, radii: [12, 36]
            )
            noise = paired[0]
            far = paired[1]
            if extendedDustScales {
                microNoise = DefectMorphology.boxMean(thin, width: width, height: height, radius: 8)
                if hasLargeContext {
                    let background = DefectMorphology.boxMean(
                        lumaValues, width: width, height: height, radius: Self.largeDustContextRadius
                    )
                    for i in 0..<n { large[i] = abs(lumaValues[i] - background[i]) }
                }
            }
        }
        self.microNoiseScale = microNoise
        self.largeDustMag = large
        self.noiseScale = noise
        self.farTexture = far
    }
}
