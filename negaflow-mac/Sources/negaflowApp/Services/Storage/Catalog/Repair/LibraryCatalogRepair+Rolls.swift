import Foundation
import Chromabase

extension LibraryCatalogRepair {
    /// 롤 소속을 "모든 사진이 정확히 한 롤에" 상태로 되돌린다. 사진은 옮겨질 뿐 사라지지 않는다.
    static func repairRolls(
        _ catalog: inout LibraryCatalog,
        report: inout LibraryCatalogRepairReport
    ) {
        let frameIDs = Set(catalog.frames.map(\.id))
        let filmTypesByFrameID = Dictionary(
            catalog.frames.map { ($0.id, $0.filmType) },
            uniquingKeysWith: { first, _ in first }
        )

        mergeUnassignedRolls(&catalog, report: &report)

        var claimed = Set<UUID>()
        var repaired: [LibraryRoll] = []
        repaired.reserveCapacity(catalog.rolls.count)

        for roll in catalog.rolls {
            var updated = roll

            let existing = updated.frameIDs.filter { frameIDs.contains($0) }
            report.record(
                .droppedMissingRollFrameReference,
                count: updated.frameIDs.count - existing.count
            )

            let deduplicated = existing.filter { claimed.insert($0).inserted }
            report.record(
                .droppedDuplicateRollMembership,
                count: existing.count - deduplicated.count
            )
            updated.frameIDs = deduplicated

            guard updated.kind == .physical else {
                repaired.append(updated)
                continue
            }

            if let normalized = normalizedPhysicalRoll(
                updated,
                filmTypesByFrameID: filmTypesByFrameID,
                report: &report
            ) {
                repaired.append(normalized)
            } else {
                // 사진이 하나도 없는 물리 롤만 여기로 온다 — 버려도 잃는 사진이 없다.
                report.record(.droppedEmptyInvalidRoll)
            }
        }

        catalog.rolls = repaired
        adoptOrphanFrames(&catalog, report: &report)
        clearInvalidActiveRoll(&catalog, report: &report)
    }

    /// `unassigned` 는 카탈로그에 정확히 하나, 고정 ID 로만 존재한다. 어긋난 것들은 하나로 합친다.
    private static func mergeUnassignedRolls(
        _ catalog: inout LibraryCatalog,
        report: inout LibraryCatalogRepairReport
    ) {
        let unassignedRolls = catalog.rolls.filter {
            $0.kind == .unassigned || $0.id == LibraryRoll.unassignedID
        }
        guard !unassignedRolls.isEmpty else { return }
        let needsNormalization = unassignedRolls.count > 1
            || unassignedRolls.contains {
                $0.kind != .unassigned
                    || $0.id != LibraryRoll.unassignedID
                    || $0.name != nil
                    || $0.filmType != nil
            }
        guard needsNormalization else { return }

        let createdAt = unassignedRolls.map(\.createdAt).min() ?? Date()
        var merged = LibraryRoll.unassigned(
            createdAt: createdAt,
            frameIDs: unassignedRolls.flatMap(\.frameIDs)
        )
        merged.frameIDs = uniqued(merged.frameIDs).ids
        var rolls = catalog.rolls.filter {
            !($0.kind == .unassigned || $0.id == LibraryRoll.unassignedID)
        }
        if let insertionIndex = catalog.rolls.firstIndex(where: {
            $0.kind == .unassigned || $0.id == LibraryRoll.unassignedID
        }) {
            rolls.insert(merged, at: min(insertionIndex, rolls.count))
        } else {
            rolls.append(merged)
        }
        catalog.rolls = rolls
        report.record(.normalizedUnassignedRoll)
    }

    /// 이름과 필름 종류를 카탈로그 안의 사실에서 유도한다. 유도할 것이 없으면 nil.
    private static func normalizedPhysicalRoll(
        _ roll: LibraryRoll,
        filmTypesByFrameID: [UUID: FilmType],
        report: inout LibraryCatalogRepairReport
    ) -> LibraryRoll? {
        var updated = roll
        let trimmedName = updated.name?.trimmingCharacters(in: .whitespacesAndNewlines)

        if updated.filmType == nil {
            guard let derived = dominantFilmType(
                of: updated.frameIDs,
                filmTypesByFrameID: filmTypesByFrameID
            ) else { return nil }
            updated.filmType = derived
            report.record(.derivedRollFilmTypeFromFrames)
        }

        if trimmedName?.isEmpty != false {
            guard let derived = derivedRollName(updated) else { return nil }
            updated.name = derived
            report.record(.derivedRollName)
        } else if trimmedName != updated.name {
            updated.name = trimmedName
            report.record(.derivedRollName)
        }

        return updated
    }

    private static func dominantFilmType(
        of frameIDs: [UUID],
        filmTypesByFrameID: [UUID: FilmType]
    ) -> FilmType? {
        let filmTypes = frameIDs.compactMap { filmTypesByFrameID[$0] }
        guard !filmTypes.isEmpty else { return nil }
        var counts: [FilmType: Int] = [:]
        for filmType in filmTypes {
            counts[filmType, default: 0] += 1
        }
        // 동률이면 그 롤의 첫 사진이 이긴다 — 같은 입력이면 항상 같은 결과여야 한다.
        return filmTypes.max { lhs, rhs in
            let lhsCount = counts[lhs, default: 0]
            let rhsCount = counts[rhs, default: 0]
            if lhsCount != rhsCount { return lhsCount < rhsCount }
            let lhsIndex = filmTypes.firstIndex(of: lhs) ?? 0
            let rhsIndex = filmTypes.firstIndex(of: rhs) ?? 0
            return lhsIndex > rhsIndex
        }
    }

    private static func derivedRollName(_ roll: LibraryRoll) -> String? {
        if let code = roll.record?.code?.trimmingCharacters(in: .whitespacesAndNewlines),
           !code.isEmpty {
            return code
        }
        guard !roll.frameIDs.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: roll.createdAt)
    }

    private static func adoptOrphanFrames(
        _ catalog: inout LibraryCatalog,
        report: inout LibraryCatalogRepairReport
    ) {
        let survivingMembers = Set(catalog.rolls.flatMap(\.frameIDs))
        let orphans = catalog.frames.map(\.id).filter { !survivingMembers.contains($0) }
        guard !orphans.isEmpty else { return }

        if let index = catalog.rolls.firstIndex(where: { $0.kind == .unassigned }) {
            catalog.rolls[index].frameIDs.append(contentsOf: orphans)
        } else {
            let createdAt = catalog.frames
                .filter { orphans.contains($0.id) }
                .map(\.scannedAt)
                .min() ?? Date()
            catalog.rolls.append(
                LibraryRoll.unassigned(createdAt: createdAt, frameIDs: orphans)
            )
        }
        report.record(.adoptedOrphanFrameIntoUnassignedRoll, count: orphans.count)
    }

    private static func clearInvalidActiveRoll(
        _ catalog: inout LibraryCatalog,
        report: inout LibraryCatalogRepairReport
    ) {
        guard let activeRollID = catalog.activeRollID else { return }
        let matches = catalog.rolls.filter { $0.id == activeRollID }
        guard matches.count != 1 || matches[0].kind != .physical else { return }
        catalog.activeRollID = nil
        report.record(.clearedActiveRoll)
    }
}
