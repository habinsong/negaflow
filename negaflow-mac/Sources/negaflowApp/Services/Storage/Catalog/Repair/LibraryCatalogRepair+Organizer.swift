import Foundation

extension LibraryCatalogRepair {
    /// 이름 없는 컬렉션에 붙이는 이름. 사용자가 언제든 바꿀 수 있고, 컬렉션과 그 안의
    /// 사진 목록을 지키는 편이 이름 하나를 지키는 것보다 낫다.
    static let placeholderOrganizerName = "Untitled"

    static func repairOrganizer(
        _ catalog: inout LibraryCatalog,
        report: inout LibraryCatalogRepairReport
    ) {
        let frameIDs = Set(catalog.frames.map(\.id))

        var seenManualIDs = Set<UUID>()
        var manualCollections: [LibraryManualCollection] = []
        for collection in catalog.manualCollections {
            guard seenManualIDs.insert(collection.id).inserted else {
                report.record(.droppedDuplicateOrganizerID)
                continue
            }
            var updated = collection
            updated.name = repairedOrganizerName(updated.name, report: &report)

            let existing = updated.frameIDs.filter { frameIDs.contains($0) }
            report.record(
                .droppedMissingOrganizerFrame,
                count: updated.frameIDs.count - existing.count
            )
            let deduplicated = uniqued(existing)
            report.record(.droppedDuplicateOrganizerMembership, count: deduplicated.removed)
            updated.frameIDs = deduplicated.ids

            manualCollections.append(updated)
        }
        catalog.manualCollections = manualCollections

        var seenSmartIDs = Set<UUID>()
        catalog.smartCollections = catalog.smartCollections.compactMap { collection in
            guard seenSmartIDs.insert(collection.id).inserted else {
                report.record(.droppedDuplicateOrganizerID)
                return nil
            }
            var updated = collection
            updated.name = repairedOrganizerName(updated.name, report: &report)
            return updated
        }

        var seenSavedSearchIDs = Set<UUID>()
        catalog.savedSearches = catalog.savedSearches.compactMap { savedSearch in
            guard seenSavedSearchIDs.insert(savedSearch.id).inserted else {
                report.record(.droppedDuplicateOrganizerID)
                return nil
            }
            var updated = savedSearch
            updated.name = repairedOrganizerName(updated.name, report: &report)
            return updated
        }

        repairStacks(&catalog, frameIDs: frameIDs, report: &report)
    }

    private static func repairedOrganizerName(
        _ name: String,
        report: inout LibraryCatalogRepairReport
    ) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return name }
        report.record(.filledOrganizerName)
        return placeholderOrganizerName
    }

    private static func repairStacks(
        _ catalog: inout LibraryCatalog,
        frameIDs: Set<UUID>,
        report: inout LibraryCatalogRepairReport
    ) {
        var seenStackIDs = Set<UUID>()
        var claimedFrameIDs = Set<UUID>()
        var stacks: [LibraryPhotoStack] = []

        for stack in catalog.stacks {
            guard seenStackIDs.insert(stack.id).inserted else {
                report.record(.droppedDuplicateOrganizerID)
                continue
            }
            let existing = stack.frameIDs.filter { frameIDs.contains($0) }
            let deduplicated = uniqued(existing).ids
            let claimed = deduplicated.filter { claimedFrameIDs.insert($0).inserted }
            report.record(
                .droppedDuplicateStackMembership,
                count: deduplicated.count - claimed.count
            )

            // 사진이 하나만 남은 스택은 스택이 아니다. 사진 자체는 카탈로그에 그대로 있다.
            guard let repaired = LibraryPhotoStack(
                id: stack.id,
                frameIDs: claimed,
                isCollapsed: stack.isCollapsed
            ) else {
                report.record(.droppedInvalidStack)
                claimedFrameIDs.subtract(claimed)
                continue
            }
            stacks.append(repaired)
        }
        catalog.stacks = stacks
    }

    /// 가상 사본은 원본과 같은 롤에, 같은 원본 메타데이터를 들고 있어야 한다.
    static func repairVirtualCopies(
        _ catalog: inout LibraryCatalog,
        report: inout LibraryCatalogRepairReport
    ) {
        let framesByID = Dictionary(
            catalog.frames.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var rollIndexByFrameID: [UUID: Int] = [:]
        for (rollIndex, roll) in catalog.rolls.enumerated() {
            for frameID in roll.frameIDs {
                rollIndexByFrameID[frameID] = rollIndex
            }
        }

        for index in catalog.frames.indices {
            let frame = catalog.frames[index]
            guard let sourceFrameID = frame.sourceFrameID,
                  let source = framesByID[sourceFrameID] else { continue }

            if frame.sourceMetadata != source.sourceMetadata {
                catalog.frames[index].sourceMetadata = source.sourceMetadata
                report.record(.realignedVirtualCopyMetadata)
            }

            guard let sourceRollIndex = rollIndexByFrameID[sourceFrameID],
                  let frameRollIndex = rollIndexByFrameID[frame.id],
                  sourceRollIndex != frameRollIndex else { continue }
            catalog.rolls[frameRollIndex].frameIDs.removeAll { $0 == frame.id }
            catalog.rolls[sourceRollIndex].frameIDs.append(frame.id)
            rollIndexByFrameID[frame.id] = sourceRollIndex
            report.record(.realignedVirtualCopyRoll)
        }
    }
}
