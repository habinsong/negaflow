import Foundation

// MARK: - 롤 기록 편집과 프레임 채우기
//
// 롤에 적은 카메라·렌즈·필름은 그 롤 프레임의 **비어 있는 칸만** 채운다. 프레임에 이미 적힌 값은
// 롤 기록보다 우선한다. 채우기는 기록을 고칠 때와 프레임이 롤에 새로 들어올 때 수행한다.
extension AppModel {
    /// 프레임이 속한 물리 롤. 미분류는 여러 촬영이 섞이므로 기록 대상이 아니다.
    func physicalRollID(for frame: ScanFrame) -> UUID? {
        guard let id = rollID(containing: frame.id), id != LibraryRoll.unassignedID else { return nil }
        return rolls.first(where: { $0.id == id && $0.kind == .physical })?.id
    }

    func rollRecord(for frame: ScanFrame) -> RollRecord? {
        guard let id = physicalRollID(for: frame) else { return nil }
        return rolls.first(where: { $0.id == id })?.record
    }

    func rollName(for frame: ScanFrame) -> String? {
        guard let id = physicalRollID(for: frame) else { return nil }
        return rolls.first(where: { $0.id == id })?.name
    }

    @discardableResult
    func updateRollRecord(id: UUID, record: RollRecord?) -> Bool {
        guard allowsLibraryMutation else { return false }
        guard record?.isValid ?? true else { return false }
        guard rollStore.updateRecord(id: id, record: record) else { return false }
        fillFramesFromRollRecord(rollID: id)
        return true
    }

    /// 롤 기록으로 프레임의 빈 칸을 채운다. 채운 프레임 수를 돌려준다.
    @discardableResult
    func fillFramesFromRollRecord(rollID: UUID) -> Int {
        guard allowsLibraryMutation,
              let roll = rolls.first(where: { $0.id == rollID }),
              let record = roll.record else { return 0 }
        let memberIDs = Set(roll.frameIDs)
        var filled = 0
        for frame in frames where memberIDs.contains(frame.id) {
            guard ownsFrame(frame), !frame.isPreviewScan else { continue }
            guard let merged = record.filling(frame.appMetadataOverlay?.filmShot) else { continue }
            if applyFilmShot(merged, to: frame) { filled += 1 }
        }
        if filled > 0 { invalidateLibraryQueryContext() }
        return filled
    }
}
