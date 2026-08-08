import Foundation

struct LibraryQueryTextRefinement {
    let condition: LibraryTextCondition

    static func make(
        previous: LibraryQuery,
        next: LibraryQuery
    ) -> LibraryQueryTextRefinement? {
        guard previous.isValid,
              next.isValid,
              previous.matchMode == .all,
              next.matchMode == .all else {
            return nil
        }

        let previousConditions = previous.conditions.filter(\.isActive)
        let nextConditions = next.conditions.filter(\.isActive)
        guard let nextText = singleSearchCondition(in: nextConditions) else { return nil }

        let nextRemainder = removingTextCondition(
            at: nextText.index,
            from: nextConditions
        )
        guard let previousText = singleSearchCondition(in: previousConditions) else {
            guard !previousConditions.contains(where: isTextCondition),
                  previousConditions == nextRemainder else {
                return nil
            }
            return LibraryQueryTextRefinement(condition: nextText.condition)
        }

        guard removingTextCondition(
                at: previousText.index,
                from: previousConditions
              ) == nextRemainder else {
            return nil
        }
        let previousTerms = LibrarySearchText.substringTerms(
            LibrarySearchText.normalize(previousText.condition.value)
        )
        let nextTerms = LibrarySearchText.substringTerms(
            LibrarySearchText.normalize(nextText.condition.value)
        )
        guard !previousTerms.isEmpty,
              !nextTerms.isEmpty,
              previousTerms.allSatisfy({ previousTerm in
                  nextTerms.contains { $0.contains(previousTerm) }
              }) else {
            return nil
        }
        return LibraryQueryTextRefinement(condition: nextText.condition)
    }

    private static func singleSearchCondition(
        in conditions: [LibraryQueryCondition]
    ) -> (index: Int, condition: LibraryTextCondition)? {
        let matches = conditions.enumerated().compactMap { index, condition
            -> (Int, LibraryTextCondition)? in
            guard case let .text(text) = condition,
                  text.field == .anySearchable,
                  text.rule == .containsAll else {
                return nil
            }
            return (index, text)
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private static func removingTextCondition(
        at index: Int,
        from conditions: [LibraryQueryCondition]
    ) -> [LibraryQueryCondition] {
        var result = conditions
        result.remove(at: index)
        return result
    }

    private static func isTextCondition(_ condition: LibraryQueryCondition) -> Bool {
        if case .text = condition { return true }
        return false
    }
}
