import Foundation

// MARK: - 국소 기준선과 광학 밀도
//
// IR 평면에는 결함만 있는 게 아니다. 컬러 네거티브의 시안 층은 근적외까지 흡수해서, 짙게
// 노광된 곳(= 포지티브로 보면 흰 부분)이 IR 에서도 어둡게 찍힌다. 실측(GT-X900, 컬러 네거티브)
// 에서 이 "장면 고스트"는 전역 기준선 대비 컷에 따라 2~7% 였다 — 결함 문턱과 같은 크기다.
// 고스트를 남기면 사진의 밝은 부분이 결함으로 잡히고, 나눗셈 보정이 그 자리를 더 밝게 만든다.
//
// 고스트를 log(red) 회귀로 빼는 방법은 컷을 탄다(실측: 어떤 컷은 남고 어떤 컷은 지워졌다).
// 대신 **기준선을 국소로** 잡는다: 결함은 좁고 고스트는 넓으므로, 구조요소보다 좁은 어두운 것만
// 메우는 그레이스케일 closing 이 결함은 지우고 고스트는 그대로 남긴 기준선을 준다. 회귀도,
// 채널 가정도, 필름별 상수도 필요 없다.
//
// 값은 투과율이 아니라 **광학 밀도** log(기준선/값)로 쓴다. 가림은 곱셈이라 밀도에서 덧셈이
// 되고, 그래서 "IR 밀도 × 배율 = 가시광 밀도" 라는 한 줄짜리 모델이 성립한다.
extension InfraredDefectRemoval {

    /// 결함을 메운 국소 기준선. radius 는 구조요소 반지름(px).
    static func localBaseline(_ plane: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        guard radius > 0 else { return plane }
        return DefectMorphology.closing(plane, width: width, height: height, radius: radius)
    }

    /// density[i] = log(baseline[i] / plane[i]) — 기준선보다 어두울 때만 양수.
    /// baseline 은 closing 결과라 항상 plane 이상이므로 음수는 수치 오차뿐이다.
    static func opticalDensity(plane: [Float], baseline: [Float], count: Int) -> [Float] {
        var density = [Float](repeating: 0, count: count)
        let floorValue: Float = 1e-5
        for i in 0..<count {
            let value = max(plane[i], floorValue)
            let base = max(baseline[i], floorValue)
            density[i] = base > value ? log(base / value) : 0
        }
        return density
    }

    /// 스캔 자신의 분포에서 세운 잡음 바닥과 검출 문턱.
    ///
    /// closing 기준선은 창 안의 최대값이라 잡음만 있어도 바닥이 0 이 아니라 양수로 뜬다.
    /// 그 바닥(중앙값)과 잡음 폭(중앙값~p99)을 재서 문턱을 세운다 — 필름·스캐너·해상도가
    /// 바뀌면 두 값이 같이 움직이므로 상수를 박을 필요가 없다.
    struct SignalStatistics {
        /// 깨끗한 필름의 밀도 바닥(중앙값). closing 기준선이 창 안의 최대값이라 0 이 아니다.
        let floor: Float
        /// 깨끗한 필름의 밀도 산포 1σ.
        let sigma: Float
        /// 결함 후보 문턱.
        let threshold: Float
        /// 자락을 끊는 선. 이 아래는 결함인지 필름 잡음인지 구분할 수 없다.
        var skirtFloor: Float { floor + 3 * sigma }
    }

    static func signalStatistics(_ density: [Float], excluded: [Bool],
                                 sensitivity: Double) -> SignalStatistics {
        let stride = max(1, density.count / 200_000)
        var samples: [Float] = []
        samples.reserveCapacity(density.count / stride + 1)
        var index = 0
        while index < density.count {
            if !excluded[index] { samples.append(density[index]) }
            index += stride
        }
        guard samples.count > 256 else {
            return SignalStatistics(floor: 0, sigma: 0, threshold: .greatestFiniteMagnitude)
        }
        samples.sort()
        func quantile(_ q: Double) -> Float {
            samples[min(samples.count - 1, max(0, Int(q * Double(samples.count - 1))))]
        }
        let floor = quantile(0.5)
        // 산포는 **사분위**에서 잰다. 상위 분위(p99 등)를 쓰면 결함이 많은 스캔에서 결함 자신이
        // 그 분위를 차지해 문턱이 같이 올라가고, 결국 아무것도 검출되지 않는다(실측: 프레임의
        // 21% 가 결함인 입력에서 검출 0). 사분위는 결함이 25% 를 넘지 않는 한 깨끗한 필름만 본다.
        // 0.6745 = 정규분포에서 중앙값~3사분위 거리(σ 환산 상수).
        let sigma = max((quantile(0.75) - floor) / 0.6745, 0)
        // 민감도 0 → 보수적, 1 → 옅은 것까지. 배수는 확률적 여유폭이지 필름·스캐너 상수가 아니다.
        let multiplier = Float(19.0 - 11.0 * min(max(sensitivity, 0), 1))
        // 산포가 정확히 0 인 입력(완전 합성 평면)에서는 문턱이 바닥과 같아져 프레임 전체가
        // 후보가 된다. 그때는 "0 보다 크면 결함"이 맞으므로 아주 작은 여유만 남긴다.
        return SignalStatistics(floor: floor, sigma: sigma,
                                threshold: max(floor + multiplier * sigma, floor + 1e-3))
    }

    /// 기준선 구조요소 반지름. 해상도에 비례한다 — 같은 0.5mm 먼지가 2400dpi 에서 지름 47px,
    /// 6400dpi 에서 126px 로 찍히므로, 물리 크기가 같으면 픽셀 반지름은 dpi 에 비례해야 한다.
    ///
    /// 크기는 위아래 양쪽에서 눌린다:
    ///   • 결함보다 작으면 결함 한가운데가 **자기 자신을 기준선으로 삼아** 밀도가 축소된다.
    ///     실측(GT-X900 2400dpi): 반지름 11 로는 좁은쪽 반지름 12px 이상 먼지의 밀도가 진짜의
    ///     43~65% 로 줄고, 18px 이상은 아예 검출되지 않아 **보정량 0** 이었다.
    ///   • 장면 고스트(시안 염료의 근적외 흡수)보다 크면 기준선이 넓은 창의 최대값이 되어
    ///     사진의 어두운 부분이 통째로 결함이 된다(실측: 반지름 71 에서 잡음 폭 40배).
    /// 짧은 변의 1/100 은 35mm 기준 약 0.24mm 반지름 — 실제 먼지의 상한이고 장면보다는 훨씬 좁다.
    static func baselineRadius(width: Int, height: Int) -> Int {
        max(4, min(96, min(width, height) / 100))
    }
}
