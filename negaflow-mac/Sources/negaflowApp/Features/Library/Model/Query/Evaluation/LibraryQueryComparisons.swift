import Foundation
import Chromabase
import ScannerKit

extension LibraryNumericComparison {
    func matches<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool {
        switch self {
        case .equal: lhs == rhs
        case .notEqual: lhs != rhs
        case .lessThan: lhs < rhs
        case .lessThanOrEqual: lhs <= rhs
        case .greaterThan: lhs > rhs
        case .greaterThanOrEqual: lhs >= rhs
        }
    }
}

extension LibraryDatePredicate {
    var isValid: Bool {
        switch self {
        case let .before(date), let .after(date):
            return date.timeIntervalSinceReferenceDate.isFinite
        case let .range(start, end):
            return start.timeIntervalSinceReferenceDate.isFinite
                && end.timeIntervalSinceReferenceDate.isFinite
                && start < end
        }
    }

    func matches(_ date: Date) -> Bool {
        switch self {
        case let .before(boundary): date < boundary
        case let .after(boundary): date > boundary
        case let .range(start, end): date >= start && date < end
        }
    }
}

extension LibraryCalendarDatePredicate {
    var isValid: Bool {
        switch self {
        case .before, .after:
            return true
        case let .range(start, end):
            return start < end
        }
    }

    func matches(_ interval: LibraryCalendarDateInterval) -> Bool {
        switch self {
        case let .before(boundary): interval.lastInclusive < boundary
        case let .after(boundary): interval.firstInclusive > boundary
        case let .range(start, end):
            interval.firstInclusive >= start && interval.lastInclusive < end
        }
    }
}
