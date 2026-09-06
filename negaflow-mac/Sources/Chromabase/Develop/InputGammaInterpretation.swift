import Foundation

/// nil은 파일의 기존 색관리 해석이며 숫자는 원본 코드 값의 power 곡선입니다.
public struct InputGammaInterpretation: Codable, Equatable, Hashable, Sendable {
    public static let range = 0.10...4.00
    public static let automatic = InputGammaInterpretation(validated: nil)
    public let value: Double?

    public static func power(_ value: Double) throws -> Self {
        guard value.isFinite, range.contains(value) else { throw ValueError.outOfRange }
        return Self(validated: value)
    }

    private init(validated value: Double?) { self.value = value }
    public enum ValueError: Error { case outOfRange }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self), text == "auto" {
            self = .automatic
        } else {
            self = try Self.power(container.decode(Double.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value { try container.encode(value) }
        else { try container.encode("auto") }
    }
}
