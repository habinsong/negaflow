import Foundation

enum LibraryCatalogStackHealthInspector {
    static func inspect(
        _ catalog: LibraryCatalog,
        frameIDCounts: [UUID: Int]
    ) -> [LibraryCatalogHealthIssue] {
        let stackIDCounts = Dictionary(grouping: catalog.stacks, by: \.id).mapValues(\.count)
        let memberships = Dictionary(
            grouping: catalog.stacks.enumerated().flatMap { stackIndex, stack in
                stack.frameIDs.map { (frameID: $0, stackID: stack.id, stackIndex: stackIndex) }
            },
            by: \.frameID
        )
        var issues: [LibraryCatalogHealthIssue] = []

        for (stackIndex, stack) in catalog.stacks.enumerated() {
            if stackIDCounts[stack.id, default: 0] > 1 {
                issues.append(.stackIssue(
                    .duplicateStackID,
                    stackID: stack.id,
                    stackIndex: stackIndex
                ))
            }
            if stack.frameIDs.count < 2 || Set(stack.frameIDs).count != stack.frameIDs.count {
                issues.append(.stackIssue(
                    .invalidPhotoStack,
                    stackID: stack.id,
                    stackIndex: stackIndex
                ))
            }
            for frameID in stack.frameIDs where frameIDCounts[frameID, default: 0] != 1 {
                issues.append(.stackIssue(
                    .stackReferencesMissingFrame,
                    frameID: frameID,
                    stackID: stack.id,
                    stackIndex: stackIndex
                ))
            }
        }

        for (frameID, entries) in memberships where entries.count > 1 {
            for entry in entries {
                issues.append(.stackIssue(
                    .duplicateStackMembership,
                    frameID: frameID,
                    stackID: entry.stackID,
                    stackIndex: entry.stackIndex
                ))
            }
        }
        return issues
    }
}

private extension LibraryCatalogHealthIssue {
    static func stackIssue(
        _ code: LibraryCatalogHealthIssueCode,
        frameID: UUID? = nil,
        stackID: UUID,
        stackIndex: Int
    ) -> LibraryCatalogHealthIssue {
        LibraryCatalogHealthIssue(
            code: code,
            severity: .error,
            frameID: frameID,
            frameIndex: nil,
            rollID: nil,
            rollIndex: nil,
            sessionID: nil,
            jobID: nil,
            manifestID: nil,
            folderIndex: nil,
            collectionID: nil,
            collectionIndex: nil,
            savedSearchID: nil,
            savedSearchIndex: nil,
            exportEventID: nil,
            exportEventIndex: nil,
            stackID: stackID,
            stackIndex: stackIndex
        )
    }
}
