import Foundation

public enum DevelopKeyboardNudge {
    public enum Direction: Sendable {
        case decrease
        case increase
    }

    public static let fineStep = 0.01
    public static let coarseStep = 0.10

    public static func adjustedValue(
        _ value: Double,
        range: ClosedRange<Double>,
        direction: Direction,
        coarse: Bool
    ) -> Double {
        let step = coarse ? coarseStep : fineStep
        let delta = direction == .increase ? step : -step
        let rounded = ((value + delta) * 100).rounded() / 100
        return min(max(rounded, range.lowerBound), range.upperBound)
    }
}
