import Foundation
import Chromabase

/// 대칭 범위(±maximum)에서 손잡이 위치(−1…1)를 거듭제곱 눈금으로 쓰는 변환.
/// 값 = maximum·sign(p)·|p|^exponent. 값 글자·직접 입력·키보드 증분은 그대로 저장값 단위다.
/// Windows `InspectorSliderValue.PositionFromValue` / `ValueFromPosition` 과 같은 식.
struct SliderPositionScale: Equatable {
    let maximum: Double
    let exponent: Double

    /// 온도·틴트 — ±4 범위에서 예전 끝값(±1)이 손잡이 40% 지점에 오고 가운데가 더 세밀하다.
    static let whiteBalance = SliderPositionScale(
        maximum: WhiteBalanceGains.maximum,
        exponent: log(1 / WhiteBalanceGains.maximum) / log(0.4)
    )

    func position(for value: Double) -> Double {
        let unit = min(max(value.isFinite ? value / maximum : 0, -1), 1)
        return unit.sign == .minus ? -pow(-unit, 1 / exponent) : pow(unit, 1 / exponent)
    }

    func value(for position: Double) -> Double {
        let unit = min(max(position.isFinite ? position : 0, -1), 1)
        return maximum * (unit.sign == .minus ? -pow(-unit, exponent) : pow(unit, exponent))
    }
}
