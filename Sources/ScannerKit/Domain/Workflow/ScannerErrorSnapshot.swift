import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

public struct ScannerErrorSnapshot: Codable, Sendable, Equatable {
    public let code: ScannerError.Code
    public let message: String
    public let recordedAt: Date

    public init(code: ScannerError.Code, message: String = "", recordedAt: Date) {
        self.code = code
        self.message = message
        self.recordedAt = recordedAt
    }

    public init(_ error: ScannerError, recordedAt: Date) {
        self.init(code: error.code, message: error.message, recordedAt: recordedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case recordedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawCode = try container.decode(String.self, forKey: .code)
        guard let code = ScannerError.Code(rawValue: rawCode) else {
            throw DecodingError.dataCorruptedError(
                forKey: .code,
                in: container,
                debugDescription: "지원하지 않는 ScannerError 코드: \(rawCode)"
            )
        }
        self.code = code
        self.message = try container.decode(String.self, forKey: .message)
        self.recordedAt = try container.decode(Date.self, forKey: .recordedAt)
        guard recordedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: .recordedAt,
                in: container,
                debugDescription: "recordedAt이 유효한 날짜가 아닙니다"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code.rawValue, forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encode(recordedAt, forKey: .recordedAt)
    }
}
