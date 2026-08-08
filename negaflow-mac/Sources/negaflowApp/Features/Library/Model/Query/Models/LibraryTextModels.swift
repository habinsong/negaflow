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
