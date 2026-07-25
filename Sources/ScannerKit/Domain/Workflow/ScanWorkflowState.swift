import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

// MARK: - Workflow states and errors

/// 한 작업이 프리뷰 캡처인지 본스캔인지 영속적으로 구분한다.
public enum ScanJobKind: String, Codable, Sendable, Equatable {
    case preview
    case full
}
/// 재시도 가능한 스캔 작업의 영속 상태.
public enum ScanJobState: String, Codable, Sendable, Equatable {
    case queued
    case running
    case finalizing
    case succeeded
    case failed
    case cancelled
}

public enum ScanWorkflowValidationError: Error, LocalizedError, Sendable, Equatable {
    case invalidValue(String)
    case invariantViolation(String)
    case illegalTransition(from: ScanJobState, to: ScanJobState)

    public var errorDescription: String? {
        switch self {
        case .invalidValue(let message), .invariantViolation(let message):
            return message
        case .illegalTransition(let from, let to):
            return "허용되지 않는 스캔 작업 상태 전이: \(from.rawValue) -> \(to.rawValue)"
        }
    }
}
