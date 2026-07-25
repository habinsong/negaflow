import Combine
import Foundation
import Chromabase

final class RollStore: ObservableObject {
    @Published private(set) var rolls: [LibraryRoll] = []
    @Published private(set) var activeRollID: UUID?

    var snapshot: RollStoreSnapshot {
        RollStoreSnapshot(rolls: rolls, activeRollID: activeRollID)
    }

    var activeRoll: LibraryRoll? {
        guard let activeRollID else { return nil }
        return rolls.first { $0.id == activeRollID && $0.kind == .physical }
    }

    func replace(with snapshot: RollStoreSnapshot) {
        rolls = snapshot.rolls.filter {
            !($0.kind == .unassigned && $0.frameIDs.isEmpty)
        }
        activeRollID = snapshot.activeRollID
    }

    func rollID(containing frameID: UUID) -> UUID? {
        let memberships = rolls.filter { $0.frameIDs.contains(frameID) }
        guard memberships.count == 1 else { return nil }
        return memberships[0].id
    }

    func hasExactMembership(for frameIDs: [UUID]) -> Bool {
        let expected = Set(frameIDs)
        guard expected.count == frameIDs.count else { return false }
        let memberships = rolls.flatMap(\.frameIDs)
        return memberships.count == frameIDs.count && Set(memberships) == expected
    }

    @discardableResult
    func createPhysicalRoll(
        name: String,
        filmType: FilmType,
        createdAt: Date = Date()
    ) -> LibraryRoll? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let roll = LibraryRoll.physical(
            name: trimmed,
            createdAt: createdAt,
            filmType: filmType
        ) else { return nil }
        rolls.append(roll)
        return roll
    }

    @discardableResult
    func renamePhysicalRoll(id: UUID, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = rolls.firstIndex(where: { $0.id == id && $0.kind == .physical }) else {
            return false
        }
        guard rolls[index].name != trimmed else { return true }
        rolls[index].name = trimmed
        return true
    }

    @discardableResult
    func activatePhysicalRoll(id: UUID?) -> Bool {
        guard let id else {
            activeRollID = nil
            return true
        }
        guard id != LibraryRoll.unassignedID,
              rolls.contains(where: { $0.id == id && $0.kind == .physical }) else {
            return false
        }
        activeRollID = id
        return true
    }

    /// 물리 롤만 카탈로그에서 제거한다. 소속 프레임은 파일이나 전역 프레임 순서를 건드리지
    /// 않고 `unassigned`로 이동한다. 빈 물리 롤도 명시적으로 삭제하기 전까지 유지된다.
    @discardableResult
    func deletePhysicalRoll(id: UUID, unassignedCreatedAt: Date) -> Bool {
        guard let index = rolls.firstIndex(where: { $0.id == id && $0.kind == .physical }) else {
            return false
        }
        let frameIDs = rolls[index].frameIDs
        rolls.remove(at: index)
        if activeRollID == id { activeRollID = nil }
        appendToUnassigned(frameIDs, createdAt: unassignedCreatedAt)
        removeEmptyUnassignedRoll()
        return true
    }

    /// 아직 어떤 롤에도 속하지 않은 새 영속 프레임만 배정한다. nil은 명시적인
    /// `unassigned` 배정이며, 디렉터리나 파일명으로 물리 롤을 추정하지 않는다.
    @discardableResult
    func assignNewPersistentFrameIDs(
        _ frameIDs: [UUID],
        toPhysicalRollID rollID: UUID?,
        unassignedCreatedAt: Date
    ) -> Bool {
        let uniqueIDs = orderedUnique(frameIDs)
        guard !uniqueIDs.isEmpty,
              uniqueIDs.allSatisfy({ membershipCount(for: $0) == 0 }) else {
            return false
        }

        if let rollID {
            guard rollID != LibraryRoll.unassignedID,
                  let index = rolls.firstIndex(where: {
                      $0.id == rollID && $0.kind == .physical
                  }) else { return false }
            rolls[index].frameIDs.append(contentsOf: uniqueIDs)
        } else {
            appendToUnassigned(uniqueIDs, createdAt: unassignedCreatedAt)
        }
        return true
    }

    /// 새 가상 사본은 원본 패밀리가 속한 같은 롤에서 마지막 패밀리 멤버 뒤에 넣는다.
    @discardableResult
    func insertVirtualCopy(_ copyID: UUID, afterFamilyFrameIDs frameIDs: [UUID]) -> Bool {
        let familyIDs = orderedUnique(frameIDs)
        guard !familyIDs.isEmpty,
              membershipCount(for: copyID) == 0,
              familyIDs.allSatisfy({ membershipCount(for: $0) == 1 }) else {
            return false
        }
        let familyRollIDs = Set(familyIDs.compactMap(rollID(containing:)))
        guard familyRollIDs.count == 1,
              let rollID = familyRollIDs.first,
              let rollIndex = rolls.firstIndex(where: { $0.id == rollID }) else {
            return false
        }
        let familySet = Set(familyIDs)
        guard let lastFamilyIndex = rolls[rollIndex].frameIDs.indices.last(where: {
            familySet.contains(rolls[rollIndex].frameIDs[$0])
        }) else { return false }
        rolls[rollIndex].frameIDs.insert(copyID, at: lastFamilyIndex + 1)
        return true
    }

    func removalDelta(for frameIDs: Set<UUID>) -> RollMembershipRemovalDelta {
        var entries: [RollMembershipRemovalDelta.Entry] = []
        var removedUnassignedRoll: RollMembershipRemovalDelta.RemovedUnassignedRoll?
        for (rollIndex, roll) in rolls.enumerated() {
            let matching = roll.frameIDs.enumerated().compactMap {
                membershipIndex, frameID -> RollMembershipRemovalDelta.Entry? in
                guard frameIDs.contains(frameID) else { return nil }
                return RollMembershipRemovalDelta.Entry(
                    frameID: frameID,
                    rollID: roll.id,
                    membershipIndex: membershipIndex,
                    sourceRollCreatedAt: roll.createdAt
                )
            }
            guard !matching.isEmpty else { continue }
            entries.append(contentsOf: matching)
            if roll.kind == .unassigned,
               roll.frameIDs.allSatisfy(frameIDs.contains) {
                removedUnassignedRoll = .init(
                    createdAt: roll.createdAt,
                    rollIndex: rollIndex
                )
            }
        }
        return RollMembershipRemovalDelta(
            entries: entries,
            removedUnassignedRoll: removedUnassignedRoll
        )
    }

    func removeFrameIDs(_ frameIDs: Set<UUID>) {
        guard !frameIDs.isEmpty else { return }
        for index in rolls.indices {
            rolls[index].frameIDs.removeAll { frameIDs.contains($0) }
        }
        removeEmptyUnassignedRoll()
    }

    /// 제거된 membership delta만 되돌린다. 현재 roll 이름, 새 roll, active roll과 제거 후
    /// 추가된 다른 membership은 보존한다.
    @discardableResult
    func restoreMemberships(
        from delta: RollMembershipRemovalDelta,
        targetRollByFrameID: [UUID: UUID] = [:]
    ) -> Bool {
        guard !delta.entries.isEmpty else { return true }
        let restoredIDs = Set(delta.entries.map(\.frameID))
        guard restoredIDs.count == delta.entries.count,
              Set(targetRollByFrameID.keys).isSubset(of: restoredIDs) else {
            return false
        }

        // 전체 복원을 값 복사본에서 완성·검증한 뒤 한 번만 publish한다. 잘못된 target이
        // 뒤늦게 발견돼도 현재 membership 일부가 제거된 상태로 남지 않는다.
        var updatedRolls = rolls
        for index in updatedRolls.indices {
            updatedRolls[index].frameIDs.removeAll { restoredIDs.contains($0) }
        }

        func ensureUnassigned(createdAt: Date, preferredIndex: Int? = nil) {
            if let index = updatedRolls.firstIndex(where: { $0.kind == .unassigned }) {
                let existing = updatedRolls[index]
                if createdAt < existing.createdAt {
                    updatedRolls[index] = LibraryRoll.unassigned(
                        createdAt: createdAt,
                        frameIDs: existing.frameIDs
                    )
                }
                return
            }
            let roll = LibraryRoll.unassigned(createdAt: createdAt, frameIDs: [])
            if let preferredIndex {
                updatedRolls.insert(roll, at: min(preferredIndex, updatedRolls.count))
            } else {
                updatedRolls.append(roll)
            }
        }

        if let removed = delta.removedUnassignedRoll {
            ensureUnassigned(
                createdAt: removed.createdAt,
                preferredIndex: removed.rollIndex
            )
        }

        let resolvedEntries = delta.entries.map { entry -> (UUID, RollMembershipRemovalDelta.Entry) in
            if let target = targetRollByFrameID[entry.frameID] {
                return (target, entry)
            }
            let originalRollStillExists = updatedRolls.contains { $0.id == entry.rollID }
            return (originalRollStillExists ? entry.rollID : LibraryRoll.unassignedID, entry)
        }
        if resolvedEntries.contains(where: { $0.0 == LibraryRoll.unassignedID }),
           !updatedRolls.contains(where: { $0.id == LibraryRoll.unassignedID }),
           let createdAt = resolvedEntries.map({ $0.1.sourceRollCreatedAt }).min() {
            ensureUnassigned(createdAt: createdAt)
        }

        let targetRollIDs = Set(resolvedEntries.map { $0.0 })
        for rollID in targetRollIDs {
            let matches = updatedRolls.filter { $0.id == rollID }
            guard matches.count == 1 else { return false }
            if rollID == LibraryRoll.unassignedID {
                guard matches[0].kind == .unassigned else { return false }
            } else {
                guard matches[0].kind == .physical else { return false }
            }
        }

        var seenRollIDs = Set<UUID>()
        let orderedRollIDs = resolvedEntries.compactMap { rollID, _ -> UUID? in
            seenRollIDs.insert(rollID).inserted ? rollID : nil
        }
        for rollID in orderedRollIDs {
            let entries = resolvedEntries
                .filter { $0.0 == rollID }
                .map { $0.1 }
                .sorted { $0.membershipIndex < $1.membershipIndex }
            guard !entries.isEmpty else { continue }
            guard let rollIndex = updatedRolls.firstIndex(where: { $0.id == rollID }) else {
                return false
            }
            for entry in entries {
                updatedRolls[rollIndex].frameIDs.insert(
                    entry.frameID,
                    at: min(entry.membershipIndex, updatedRolls[rollIndex].frameIDs.count)
                )
            }
        }
        updatedRolls.removeAll { $0.kind == .unassigned && $0.frameIDs.isEmpty }
        for frameID in restoredIDs {
            let count = updatedRolls.reduce(into: 0) { result, roll in
                result += roll.frameIDs.count { $0 == frameID }
            }
            guard count == 1 else { return false }
        }
        rolls = updatedRolls
        return true
    }

    /// 원본과 모든 가상 사본을 한 단위로 이동한다. 전역 `frames`, 파일 URL, `scanIndex`는
    /// 호출자가 건드리지 않으며 이 저장소는 membership 순서만 변경한다.
    @discardableResult
    func moveFrameFamily(
        _ orderedFrameIDs: [UUID],
        toPhysicalRollID targetRollID: UUID?,
        unassignedCreatedAt: Date
    ) -> Bool {
        let familyIDs = orderedUnique(orderedFrameIDs)
        guard !familyIDs.isEmpty,
              familyIDs.allSatisfy({ membershipCount(for: $0) == 1 }) else {
            return false
        }
        let sourceRollIDs = Set(familyIDs.compactMap(rollID(containing:)))
        guard sourceRollIDs.count == 1 else { return false }

        let resolvedTargetID: UUID
        if let targetRollID {
            guard targetRollID != LibraryRoll.unassignedID,
                  rolls.contains(where: {
                      $0.id == targetRollID && $0.kind == .physical
                  }) else { return false }
            resolvedTargetID = targetRollID
        } else {
            resolvedTargetID = LibraryRoll.unassignedID
        }
        if sourceRollIDs.first == resolvedTargetID { return true }

        let familySet = Set(familyIDs)
        for index in rolls.indices {
            rolls[index].frameIDs.removeAll { familySet.contains($0) }
        }
        if let targetRollID,
           let targetIndex = rolls.firstIndex(where: { $0.id == targetRollID }) {
            rolls[targetIndex].frameIDs.append(contentsOf: familyIDs)
        } else {
            appendToUnassigned(familyIDs, createdAt: unassignedCreatedAt)
        }
        removeEmptyUnassignedRoll()
        return true
    }

    private func membershipCount(for frameID: UUID) -> Int {
        rolls.reduce(into: 0) { count, roll in
            count += roll.frameIDs.count { $0 == frameID }
        }
    }

    private func appendToUnassigned(_ frameIDs: [UUID], createdAt: Date) {
        guard !frameIDs.isEmpty else { return }
        if let index = rolls.firstIndex(where: { $0.kind == .unassigned }) {
            let existing = rolls[index]
            rolls[index] = LibraryRoll.unassigned(
                createdAt: min(existing.createdAt, createdAt),
                frameIDs: existing.frameIDs + frameIDs
            )
        } else {
            rolls.append(LibraryRoll.unassigned(createdAt: createdAt, frameIDs: frameIDs))
        }
    }

    private func ensureUnassignedRoll(
        from removed: RollMembershipRemovalDelta.RemovedUnassignedRoll
    ) {
        if let index = rolls.firstIndex(where: { $0.kind == .unassigned }) {
            let existing = rolls[index]
            guard removed.createdAt < existing.createdAt else { return }
            rolls[index] = LibraryRoll.unassigned(
                createdAt: removed.createdAt,
                frameIDs: existing.frameIDs
            )
            return
        }
        let empty = LibraryRoll.unassigned(createdAt: removed.createdAt, frameIDs: [])
        rolls.insert(empty, at: min(removed.rollIndex, rolls.count))
    }

    private func ensureUnassignedRoll(createdAt: Date) {
        if let index = rolls.firstIndex(where: { $0.kind == .unassigned }) {
            let existing = rolls[index]
            guard createdAt < existing.createdAt else { return }
            rolls[index] = LibraryRoll.unassigned(
                createdAt: createdAt,
                frameIDs: existing.frameIDs
            )
        } else {
            rolls.append(LibraryRoll.unassigned(createdAt: createdAt, frameIDs: []))
        }
    }

    private func removeEmptyUnassignedRoll() {
        rolls.removeAll { $0.kind == .unassigned && $0.frameIDs.isEmpty }
    }

    private func orderedUnique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
