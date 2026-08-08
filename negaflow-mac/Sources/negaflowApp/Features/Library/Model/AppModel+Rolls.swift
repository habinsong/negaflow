import Foundation
import Chromabase

extension AppModel {
    func rollID(containing frameID: UUID) -> UUID? {
        rollStore.rollID(containing: frameID)
    }

    @discardableResult
    func createPhysicalRoll(
        name: String,
        filmType: FilmType,
        activate: Bool = false,
        createdAt: Date = Date()
    ) -> LibraryRoll? {
        guard allowsLibraryMutation else { return nil }
        guard let roll = rollStore.createPhysicalRoll(
            name: name,
            filmType: filmType,
            createdAt: createdAt
        ) else { return nil }
        if activate {
            guard rollStore.activatePhysicalRoll(id: roll.id) else {
                _ = rollStore.deletePhysicalRoll(
                    id: roll.id,
                    unassignedCreatedAt: roll.createdAt
                )
                return nil
            }
        }
        return roll
    }

    @discardableResult
    func renamePhysicalRoll(id: UUID, name: String) -> Bool {
        guard allowsLibraryMutation else { return false }
        return rollStore.renamePhysicalRoll(id: id, name: name)
    }

    @discardableResult
    func activatePhysicalRoll(id: UUID?) -> Bool {
        guard allowsLibraryMutation else { return false }
        guard id != activeRollID else { return true }
        return rollStore.activatePhysicalRoll(id: id)
    }

    /// 롤 삭제는 catalog organization만 변경한다. 원본과 프레임은 유지하며 해당 롤의
    /// membership만 `unassigned`로 옮긴다.
    @discardableResult
    func deletePhysicalRoll(id: UUID) -> Bool {
        guard allowsLibraryMutation else { return false }
        guard let roll = rolls.first(where: { $0.id == id && $0.kind == .physical }) else {
            return false
        }
        guard !isProtectedScanProvenanceRoll(id) else {
            reportProtectedScanProvenanceMutation()
            return false
        }
        let memberIDs = Set(roll.frameIDs)
        let createdAt = frames.lazy
            .filter { memberIDs.contains($0.id) }
            .map(\.scannedAt)
            .min() ?? roll.createdAt
        return rollStore.deletePhysicalRoll(id: id, unassignedCreatedAt: createdAt)
    }

    /// 새 영속 프레임의 membership을 명시적으로 만든다. nil 또는 reserved unassigned ID는
    /// `unassigned`이며, 현재 폴더·경로·프레임 순서로 물리 롤을 자동 추정하지 않는다.
    @discardableResult
    func assignNewPersistentFrames(
        _ newFrames: [ScanFrame],
        toRollID requestedRollID: UUID? = nil
    ) -> Bool {
        guard allowsLibraryMutation else { return false }
        let uniqueIDs = Set(newFrames.map(\.id))
        guard !newFrames.isEmpty,
              uniqueIDs.count == newFrames.count,
              newFrames.allSatisfy({ !$0.isPreviewScan && ownsFrame($0) }),
              let createdAt = newFrames.map(\.scannedAt).min() else {
            return false
        }
        let physicalRollID = requestedRollID == LibraryRoll.unassignedID
            ? nil
            : requestedRollID
        guard rollStore.assignNewPersistentFrameIDs(
            newFrames.map(\.id),
            toPhysicalRollID: physicalRollID,
            unassignedCreatedAt: createdAt
        ) else { return false }
        // 롤에 적어 둔 카메라·렌즈·필름을 새 프레임의 빈 칸에 채운다.
        if let physicalRollID { fillFramesFromRollRecord(rollID: physicalRollID) }
        return true
    }

    /// 원본과 그 가상 사본 전체를 같은 롤로 옮긴다. 전역 프레임 배열과 파일·scanIndex는
    /// 변경하지 않는다. nil 또는 reserved ID는 명시적인 `unassigned` 이동이다.
    @discardableResult
    func moveOriginalFrameFamily(
        containing frame: ScanFrame,
        toRollID requestedRollID: UUID?
    ) -> Bool {
        guard allowsLibraryMutation else { return false }
        guard ownsFrame(frame), !frame.isPreviewScan else { return false }
        let family = frames.filter {
            !$0.isPreviewScan && $0.rootFrameID == frame.rootFrameID
        }
        guard !family.isEmpty else { return false }
        let sourceRollID = rollStore.rollID(containing: family[0].id)
        let physicalRollID = requestedRollID == LibraryRoll.unassignedID
            ? nil
            : requestedRollID
        let resolvedTargetID = physicalRollID ?? LibraryRoll.unassignedID
        if family.contains(where: isProtectedScanProvenanceRoot),
           sourceRollID != resolvedTargetID {
            reportProtectedScanProvenanceMutation()
            return false
        }
        let createdAt = family.map(\.scannedAt).min() ?? frame.scannedAt
        guard rollStore.moveFrameFamily(
            family.map(\.id),
            toPhysicalRollID: physicalRollID,
            unassignedCreatedAt: createdAt
        ) else { return false }
        if let physicalRollID { fillFramesFromRollRecord(rollID: physicalRollID) }
        return true
    }

    func rollStateSnapshot() -> RollStoreSnapshot {
        rollStore.snapshot
    }

    func replaceRollState(with snapshot: RollStoreSnapshot) {
        rollStore.replace(with: snapshot)
    }

}
