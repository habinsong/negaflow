import Foundation

/// GrainMend 민감도 슬라이더 계약.
///
/// 자동과 가이드는 **서로 다른 도구**다 — 범위도, 기본값도, 검출기 민감도 매핑도 공유하지 않는다.
///  - 자동: 사용자가 위치를 지목하지 않은 전체 프레임 검출. 검출기 민감도 0~1.
///  - 가이드: 사용자가 ROI 로 범위를 지목한 검출. 자동의 1.5배까지 올라간다.
///
/// 1 을 넘는 민감도는 검출 임계·SNR 게이트를 낮추지 않는다(그레인 안전선은 검출기 안에서 s≤1 로
/// clamp 된다). 넘는 만큼은 형태 게이트(면적/aspect/길이/두께)만 완화한다 — 사용자가 결함 위치를
/// 지목한 가이드에서만 그렇게 풀어도 되는 이유다.
enum GrainMendSensitivity {
    static let automaticRange: ClosedRange<Double> = 0.7...6.0
    static let guidedRange: ClosedRange<Double> = 0.7...9.0

    /// 가이드가 슬라이더 최대에서 검출기에 전달하는 민감도(= 자동 최대의 1.5배).
    static let guidedMaximumDetectorSensitivity = 1.5

    static func range(automatic: Bool) -> ClosedRange<Double> {
        automatic ? automaticRange : guidedRange
    }

    /// 기본값은 두 모드 모두 슬라이더 최대.
    static func defaultValue(automatic: Bool) -> Double {
        range(automatic: automatic).upperBound
    }

    /// 슬라이더 값 → 검출기 민감도(자동 0~1, 가이드 0~1.5).
    static func detectorSensitivity(_ value: Double, automatic: Bool) -> Double {
        let bounds = range(automatic: automatic)
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return 0 }
        let normalized = max(0, min(1, (value - bounds.lowerBound) / span))
        return automatic ? normalized : normalized * guidedMaximumDetectorSensitivity
    }

    /// 검출기 민감도 상한 — 스크래치 민감도 보정(+0.1)이 모드 상한을 넘지 않게 clamp 할 때 쓴다.
    static func maximumDetectorSensitivity(automatic: Bool) -> Double {
        automatic ? 1.0 : guidedMaximumDetectorSensitivity
    }
}
