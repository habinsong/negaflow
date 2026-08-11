import Foundation
import Chromabase
import ScannerKit

extension LibraryQueryCondition {
    var isActive: Bool {
        guard case let .text(condition) = self else { return true }
        switch condition.rule {
        case .isEmpty, .isNotEmpty:
            return true
        default:
            return !LibrarySearchText.normalize(condition.value).isEmpty
        }
    }

    var isValid: Bool {
        switch self {
        case let .text(condition):
            guard condition.value.utf8.count <= LibraryQuery.maximumTextLength else { return false }
            let normalized = LibrarySearchText.normalize(condition.value)
            switch condition.rule {
            case .isEmpty, .isNotEmpty:
                return normalized.isEmpty
            case .containsAny, .containsAll, .containsAllWords, .doesNotContainAny:
                return normalized.isEmpty || !LibrarySearchText.substringTerms(normalized).isEmpty
            case .containsPhrase:
                return normalized.isEmpty
                    || !LibrarySearchText.removingWhitespace(normalized).isEmpty
            case .startsWith, .endsWith, .equals:
                return true
            }
        case let .textIsAnyOf(_, values):
            guard !values.isEmpty,
                  values.count <= LibraryQuery.maximumAnyOfValueCount,
                  values.allSatisfy({ $0.utf8.count <= LibraryQuery.maximumTextLength }) else {
                return false
            }
            let normalized = values.map(LibrarySearchText.normalize)
            return normalized.allSatisfy { !$0.isEmpty }
                && Set(normalized).count == normalized.count
        case let .rating(_, value):
            return (0...5).contains(value)
        case let .pickState(values):
            return Self.isValidAnyOf(values)
        case let .date(condition):
            return condition.predicate.isValid
        case let .calendarDate(condition):
            return condition.predicate.isValid
        case let .roll(values):
            return Self.isValidAnyOf(values)
        case .currentRoll:
            return true
        case let .filmType(values):
            return Self.isValidAnyOf(values)
        case let .sourceAvailability(values):
            return Self.isValidAnyOf(values)
        case .virtualCopy, .infraredCapture, .defectRecipe:
            return true
        case let .scannerProfileState(values):
            return Self.isValidAnyOf(values)
        case .metadata, .metadataReadProblem, .creativeCalibrationAdjusted:
            return true
        case let .exportState(values):
            return Self.isValidAnyOf(values)
        case let .userEditState(values):
            return Self.isValidAnyOf(values)
        case let .defectReviewState(values):
            return Self.isValidAnyOf(values)
        case let .deviceCalibrationState(values):
            return Self.isValidAnyOf(values)
        }
    }

    private static func isValidAnyOf<Value>(_ values: [Value]) -> Bool {
        !values.isEmpty && values.count <= LibraryQuery.maximumAnyOfValueCount
    }

    func matches(
        _ facts: LibraryFrameQueryFacts,
        context: LibraryQueryContext
    ) -> Bool {
        switch self {
        case let .text(condition):
            return LibrarySearchText.matches(
                values: facts.textValues[condition.field] ?? [],
                rule: condition.rule,
                query: condition.value,
                knowledgeIsComplete: !facts.unknownTextFields.contains(condition.field)
            )
        case let .textIsAnyOf(field, values):
            let accepted = Set(values.map(LibrarySearchText.normalize))
            return facts.textValues[field, default: []].contains(where: accepted.contains)
        case let .rating(comparison, value):
            return comparison.matches(facts.rating, value)
        case let .pickState(values):
            return values.contains(facts.pickState)
        case let .date(condition):
            let date = switch condition.field {
            case .contentInstant: facts.contentDate
            case .scannedOrImportedDate: Optional(facts.scannedAt)
            }
            guard let date else { return false }
            return condition.predicate.matches(date)
        case let .calendarDate(condition):
            let interval = switch condition.field {
            case .contentDate: facts.contentCalendarDateInterval
            }
            guard let interval else { return false }
            return condition.predicate.matches(interval)
        case let .roll(values):
            guard let rollID = facts.rollID else { return false }
            return values.contains(rollID)
        case .currentRoll:
            guard let activeRollID = context.activeRollID else { return false }
            return facts.rollID == activeRollID
        case let .filmType(values):
            return values.contains(facts.filmType)
        case let .sourceAvailability(values):
            return values.contains(facts.availability)
        case let .virtualCopy(expected):
            return facts.isVirtualCopy.map { $0 == expected } ?? false
        case let .infraredCapture(expected):
            return facts.hasInfraredCapture == expected
        case let .defectRecipe(expected):
            return facts.hasDefectRecipe == expected
        case let .scannerProfileState(values):
            return values.contains(facts.scannerProfileState)
        case let .metadata(field, presence):
            return facts.metadataPresenceByField[field, default: .unknown] == presence
        case let .metadataReadProblem(expected):
            return facts.metadataReadProblem.map { $0 == expected } ?? false
        case let .creativeCalibrationAdjusted(expected):
            return facts.hasCreativeCalibrationAdjustments == expected
        case let .exportState(values):
            return values.contains(facts.exportState)
        case let .userEditState(values):
            return values.contains(facts.userEditState)
        case let .defectReviewState(values):
            return values.contains(facts.defectReviewState)
        case let .deviceCalibrationState(values):
            return values.contains(facts.deviceCalibrationState)
        }
    }
}
