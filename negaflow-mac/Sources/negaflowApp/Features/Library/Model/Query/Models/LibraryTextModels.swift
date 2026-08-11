import Foundation
import Chromabase
import ScannerKit

enum LibraryQueryMatchMode: String, Codable, Equatable, Sendable {
    case all
    case any
}

enum LibraryTextField: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case anySearchable
    case displayName
    case fileName
    case folder
    case roll
    case film
    case camera
    case lens
    case keywords
    case titleDescription
    case scannerProfile
    case scannerDevice
    case lightSourceProfile
    case collection
}

enum LibraryTextMatchRule: String, Codable, Equatable, Sendable {
    case containsAny
    case containsAll
    /// 입력한 말이 **붙어 있는 그대로** 값 하나 안에 들어 있어야 한다. 낱말을 따로 떼어
    /// 서로 다른 값에서 하나씩 찾는 `containsAll` 과 다르다 — "사진 1" 로 찾을 때 이름이
    /// "사진 3" 이고 파일명이 `L1000003` 인 컷이 걸려 나오던 것이 그 때문이었다.
    case containsPhrase
    case containsAllWords
    case doesNotContainAny
    case startsWith
    case endsWith
    case equals
    case isEmpty
    case isNotEmpty
}

struct LibraryTextCondition: Codable, Equatable, Sendable {
    var field: LibraryTextField
    var rule: LibraryTextMatchRule
    var value: String
}

enum LibraryNumericComparison: String, Codable, Equatable, Sendable {
    case equal
    case notEqual
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual
}
