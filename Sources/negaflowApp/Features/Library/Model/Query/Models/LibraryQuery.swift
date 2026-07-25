import Foundation
import Chromabase
import ScannerKit

struct LibraryQuery: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maximumConditionCount = 64
    static let maximumAnyOfValueCount = 64
    static let maximumTextLength = 1_024

    var version: Int
    var matchMode: LibraryQueryMatchMode
    var conditions: [LibraryQueryCondition]

    init(
        version: Int = currentVersion,
        matchMode: LibraryQueryMatchMode = .all,
        conditions: [LibraryQueryCondition] = []
    ) {
        self.version = version
        self.matchMode = matchMode
        self.conditions = conditions
    }

    var isValid: Bool {
        guard version == Self.currentVersion,
              conditions.count <= Self.maximumConditionCount else { return false }
        return conditions.allSatisfy(\.isValid)
    }

    func matches(frameID: UUID, in context: LibraryQueryContext) -> Bool {
        guard let predicate = LibraryQueryPredicate(self),
              let facts = context.factsByFrameID[frameID] else { return false }
        return predicate.matches(facts, context: context)
    }
}
