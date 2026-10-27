import CoreImage
import Foundation

// MARK: - ChannelRangeCalibration
//
// 자동 밸런스 OFF 의 고정 반전은 세 채널에 같은 밀도 범위(명목 1.55D)를 쓴다. 실제 스캔의 채널 밀도
// 범위는 장치 × 필름이 정한다 — 작성자 카탈로그 실측(2026-10-27, 스캔 묶음 5개·프레임 4~41장,
// 상한 포화 프레임 제외)에서 묶음마다 ln(B/R) 중앙값이 0.23~0.61 로 달랐고, 그 비율을 같게 두면
// 중립 회색이 그만큼 파랗다. 같은 묶음 안에서 프레임마다 잰 값의 흩어짐은 ln(B/R) 의 강건 σ 가
// 0.02~0.11 이라 묶음의 중앙값은 장면 구성에 거의 흔들리지 않는다(묶음 사이의 차이가 훨씬 크다).
//
// 이 교정은 장면을 읽어 노출·톤을 옮기지 않는다. 롤 하나에 대해 한 번 정한 세 수(R·G·B 곱,
// 기하평균 1)가 `DevelopParameters.channelRange` 로 프레임에 실린다. 같은 입력과 같은 교정이면
// 같은 그림이다.
public enum ChannelRangeCalibration {
    /// 채널 곱으로 받아들이는 범위. 이 밖은 측정 실패(예: 한 채널이 클립됨)로 보고 버린다.
    static let allowedMultiplier = 0.5...2.0
    /// 교정을 정하는 데 필요한 최소 프레임 수.
    public static let minimumFrameCount = 3
    /// 프레임 측정에 쓰는 밀도 상한(D). 자동 밸런스가 쓰는 값과 같다.
    static let densityLimit = 1.8
    /// 프레임 측정값의 허용 흩어짐(채널별 ln 의 강건 σ = 1.4826·MAD). 실측 롤 안의 값은
    /// 0.05~0.11 이었고, 서로 다른 필름이 섞인 묶음은 이보다 크게 벌어진다. 실측 최대의 두 배
    /// 안쪽에서 끊는다 — 설계 선택이며 측정으로 검증한 경계는 아니다.
    static let maximumSpread = 0.20

    /// 유한하고 양수이며 허용 범위 안일 때만 돌려주고, 기하평균 1 로 맞춘다.
    public static func sanitized(_ value: SIMD3<Double>) -> SIMD3<Double>? {
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite,
              value.x > 0, value.y > 0, value.z > 0 else { return nil }
        let geometric = pow(value.x * value.y * value.z, 1.0 / 3.0)
        let normalized = value / geometric
        guard allowedMultiplier.contains(normalized.x), allowedMultiplier.contains(normalized.y),
              allowedMultiplier.contains(normalized.z) else { return nil }
        return normalized
    }

    /// 한 프레임의 채널 밀도 범위 모양(기하평균 1). 자동 밸런스가 쓰는 것과 같은 장면 측정
    /// (최농부 p0.2, 1.8D 상한)이다. 어느 채널이든 상한에 닿았으면 그 채널의 진짜 범위는
    /// 더 크므로 모양이 잘려 있다 — 그런 프레임은 쓰지 않는다. 측정할 수 없거나 비정상이면 nil.
    public static func measure(in image: CIImage, base: FilmBase,
                               region: AnalysisRegion? = nil) -> SIMD3<Double>? {
        guard let stats = NegativeInversion.sampleStats(
            image, base: base, filmType: .colorNegative, region: region, densityLimit: densityLimit
        ) else { return nil }
        let clamped = densityLimit - 1e-6
        guard stats.dmaxNorm.x < clamped, stats.dmaxNorm.y < clamped,
              stats.dmaxNorm.z < clamped else { return nil }
        return sanitized(stats.dmaxNorm)
    }

    /// 여러 프레임의 측정을 하나로 합친다. 채널별 ln 중앙값이라 한 프레임(하늘 독점 장면 등)이
    /// 끌고 가지 못한다. `minimumFrameCount` 미만이거나 프레임 사이 흩어짐이 `maximumSpread` 를
    /// 넘으면(필름이 섞였을 가능성) nil.
    public static func combine(_ measurements: [SIMD3<Double>]) -> SIMD3<Double>? {
        let valid = measurements.compactMap(sanitized)
        guard valid.count >= minimumFrameCount else { return nil }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            let mid = sorted.count / 2
            return sorted.count % 2 == 0 ? 0.5 * (sorted[mid - 1] + sorted[mid]) : sorted[mid]
        }
        var center = [Double](repeating: 0, count: 3)
        for channel in 0..<3 {
            let logs = valid.map { log($0[channel]) }
            let mid = median(logs)
            let spread = 1.4826 * median(logs.map { abs($0 - mid) })
            guard spread <= maximumSpread else { return nil }
            center[channel] = mid
        }
        return sanitized(SIMD3(exp(center[0]), exp(center[1]), exp(center[2])))
    }
}
