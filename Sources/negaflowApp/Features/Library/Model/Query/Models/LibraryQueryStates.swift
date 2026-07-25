import Foundation
import Chromabase
import ScannerKit

enum LibrarySourceAvailability: String, Codable, CaseIterable, Equatable, Sendable {
    case online
    case offline
    case unknown
}

enum LibraryScannerProfileState: String, Codable, CaseIterable, Equatable, Sendable {
    case unknown
    case none
    case missing
    case draft
    case realOnly
    case pairedSmoke
    case pairedValidated
}

enum LibraryMetadataField: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case snapshot
    case camera
    case lens
    case contentDate
    case title
    case description
    case keywords
    case descriptive
}

enum LibraryMetadataPresence: String, Codable, Equatable, Sendable {
    case unknown
    case present
    case missing
}

/// 성공 export 추적이 시작되지 않은 legacy frame은 `.unknown`이다.
enum LibraryExportState: String, Codable, CaseIterable, Equatable, Sendable {
    case unknown
    case never
    case succeeded
}

/// 자동 초기 현상 완료와 사용자 편집을 분리한다.
enum LibraryUserEditState: String, Codable, CaseIterable, Equatable, Sendable {
    case unknown
    case unedited
    case edited
}

enum LibraryDefectReviewState: String, Codable, CaseIterable, Equatable, Sendable {
    case unknown
    case notRequired
    case needsReview
    case reviewed
}

/// Develop calibration과 별개인 입력 장치 calibration의 향후 영속 상태다.
enum LibraryDeviceCalibrationState: String, Codable, CaseIterable, Equatable, Sendable {
    case unknown
    case uncalibrated
    case valid
    case expired
}
