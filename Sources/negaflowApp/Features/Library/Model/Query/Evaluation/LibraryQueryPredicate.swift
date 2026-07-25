import Foundation
import Chromabase
import ScannerKit

struct LibraryQueryPredicate {
    private let matchMode: LibraryQueryMatchMode
    private let conditions: [LibraryPreparedQueryCondition]

    init?(_ query: LibraryQuery) {
        guard query.isValid else { return nil }
        matchMode = query.matchMode
        conditions = query.conditions.compactMap { condition in
            guard condition.isActive else { return nil }
            if case let .text(text) = condition {
                return .text(
                    field: text.field,
                    predicate: LibraryPreparedTextPredicate(text)
                )
            }
            if case let .textIsAnyOf(field, values) = condition {
                return .textIsAnyOf(
                    field: field,
                    normalizedValues: Set(values.map(LibrarySearchText.normalize))
                )
            }
            return .direct(condition)
        }
        .sorted { $0.evaluationCost < $1.evaluationCost }
    }

    func matches(
        _ facts: LibraryFrameQueryFacts,
        context: LibraryQueryContext
    ) -> Bool {
        guard !conditions.isEmpty else { return true }
        switch matchMode {
        case .all:
            return conditions.allSatisfy { $0.matches(facts, context: context) }
        case .any:
            return conditions.contains { $0.matches(facts, context: context) }
        }
    }
}

private enum LibraryPreparedQueryCondition {
    case text(field: LibraryTextField, predicate: LibraryPreparedTextPredicate)
    case textIsAnyOf(field: LibraryTextField, normalizedValues: Set<String>)
    case direct(LibraryQueryCondition)

    var evaluationCost: Int {
        switch self {
        case .direct: 0
        case .textIsAnyOf: 1
        case .text: 2
        }
    }

    func matches(
        _ facts: LibraryFrameQueryFacts,
        context: LibraryQueryContext
    ) -> Bool {
        switch self {
        case let .text(field, predicate):
            return predicate.matches(
                facts.textValues[field] ?? [],
                substringIndex: field == .anySearchable
                    ? facts.anySearchableSubstringIndex
                    : nil,
                knowledgeIsComplete: !facts.unknownTextFields.contains(field)
            )
        case let .textIsAnyOf(field, normalizedValues):
            return facts.textValues[field, default: []].contains(where: normalizedValues.contains)
        case let .direct(condition):
            return condition.matches(facts, context: context)
        }
    }
}

struct LibraryPreparedTextPredicate {
    let rule: LibraryTextMatchRule
    let phrase: String
    let substringTerms: [String]
    let requiredWords: [String]

    init(_ condition: LibraryTextCondition) {
        rule = condition.rule
        phrase = LibrarySearchText.normalize(condition.value)
        substringTerms = LibrarySearchText.substringTerms(phrase)
        requiredWords = LibrarySearchText.wordTokens(phrase)
    }

    func matches(
        _ normalizedValues: [String],
        substringIndex: String? = nil,
        knowledgeIsComplete: Bool
    ) -> Bool {
        switch rule {
        case .isEmpty:
            return knowledgeIsComplete && normalizedValues.isEmpty
        case .isNotEmpty:
            return !normalizedValues.isEmpty
        case .startsWith:
            return normalizedValues.contains { $0.hasPrefix(phrase) }
        case .endsWith:
            return normalizedValues.contains { $0.hasSuffix(phrase) }
        case .equals:
            return normalizedValues.contains(phrase)
        case .containsAny:
            if let substringIndex {
                return substringTerms.contains { substringIndex.contains($0) }
            }
            return substringTerms.contains { term in
                normalizedValues.contains {
                    $0.contains(term)
                        || LibrarySearchText.removingWhitespace($0).contains(term)
                }
            }
        case .containsAll:
            if let substringIndex {
                return substringTerms.allSatisfy { substringIndex.contains($0) }
            }
            return substringTerms.allSatisfy { term in
                normalizedValues.contains {
                    $0.contains(term)
                        || LibrarySearchText.removingWhitespace($0).contains(term)
                }
            }
        case .containsAllWords:
            let availableWords = Set(normalizedValues.flatMap(LibrarySearchText.wordTokens))
            return requiredWords.allSatisfy(availableWords.contains)
        case .doesNotContainAny:
            if let substringIndex {
                return knowledgeIsComplete
                    && !substringTerms.contains { substringIndex.contains($0) }
            }
            return knowledgeIsComplete
                && !substringTerms.contains { term in
                    normalizedValues.contains {
                        $0.contains(term)
                            || LibrarySearchText.removingWhitespace($0).contains(term)
                    }
                }
        }
    }
}
