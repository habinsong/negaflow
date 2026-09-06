import Foundation

/// 자동 측정값에 적용하는 배율. 유효한 값만 엔진으로 전달합니다.
public struct FilmBaseScale: Codable, Equatable, Sendable {
    public static let range = 0.5...1.5
    public static let identity = FilmBaseScale(validated: 1)
    public let value: Double

    public init(_ value: Double) throws {
        guard value.isFinite, Self.range.contains(value) else {
            throw ValueError.outOfRange
        }
        self.value = value
    }

    private init(validated value: Double) { self.value = value }

    public enum ValueError: Error { case outOfRange }

    public func applied(to rgb: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            min(max(rgb.x * value, 0), 1),
            min(max(rgb.y * value, 0), 1),
            min(max(rgb.z * value, 0), 1)
        )
    }

    func applied(to base: FilmBase) -> FilmBase {
        guard self != .identity else { return base }
        return FilmBase(rgb: applied(to: base.rgb), source: base.source)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(Double.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
