import Foundation
import Chromabase
import ScannerKit

enum TextJoinResolution<Value> {
    case known(Value?)
    case unknown

    var value: Value? {
        guard case let .known(value) = self else { return nil }
        return value
    }

    var knowledgeIsComplete: Bool {
        guard case .known = self else { return false }
        return true
    }
}

enum ProfileResolution {
    case none
    case missing(String)
    case resolved(ScannerProfile)
    case unknown(String)

    var value: ScannerProfile? {
        guard case let .resolved(profile) = self else { return nil }
        return profile
    }

    var knowledgeIsComplete: Bool {
        switch self {
        case .none, .resolved: return true
        case .missing, .unknown: return false
        }
    }

    var state: LibraryScannerProfileState {
        switch self {
        case .none:
            return .none
        case .missing:
            return .missing
        case .unknown:
            return .unknown
        case let .resolved(profile):
            switch profile.validationStatus {
            case .draft: return .draft
            case .realOnly: return .realOnly
            case .pairedSmoke: return .pairedSmoke
            case .pairedValidated: return .pairedValidated
            }
        }
    }
}
