import Foundation

// MARK: - DefectHistorySnapshot
//
// 되돌리기/다시 실행이 복원할 Defect Layer 목록을 만든다.
//
// **GrainMend IR 은 되돌리기로 사라지지 않는다.** IR 은 사람이 그린 기록이 아니라 스캔과 함께
// 측정된 결과이고, 사용자가 레이어 휴지통을 눌러야만 없어져야 한다. 브러시·자동·가이드·복제
// 도장을 되돌리다가 그보다 나중에 붙은 IR 레이어까지 스냅샷에서 빠져 사라지던 것이 이 규칙이
// 막는 일이다. 휴지통으로 IR 을 지우는 경우만 정확 복원(`exact`)으로 등록해, 그 삭제는 되돌리고
// 다시 실행할 수 있다.
enum DefectHistorySnapshot {
    enum Mode {
        /// 스냅샷을 그대로 복원한다. 사용자가 레이어를 명시적으로 지운 경우.
        case exact
        /// 현재 IR 레이어를 지키면서 나머지만 스냅샷으로 되돌린다.
        case preservingInfrared
    }

    static func resolve(
        _ snapshot: [DefectEditItem],
        current: [DefectEditItem],
        mode: Mode
    ) -> [DefectEditItem] {
        switch mode {
        case .exact:
            return snapshot
        case .preservingInfrared:
            var resolved = snapshot.filter { !$0.isInfrared }
            // 스냅샷에 있던 IR 은 그 자리에, 지금만 있는 IR(스냅샷 이후에 붙은 것)은 현재 자리에
            // 끼워 넣는다 — 어느 쪽도 잃지 않고 합성 순서도 흔들지 않는다.
            let snapshotInfraredIDs = Set(snapshot.filter(\.isInfrared).map(\.id))
            for (index, item) in snapshot.enumerated() where item.isInfrared {
                resolved.insert(item, at: min(index, resolved.count))
            }
            for (index, item) in current.enumerated()
            where item.isInfrared && !snapshotInfraredIDs.contains(item.id) {
                resolved.insert(item, at: min(index, resolved.count))
            }
            return resolved
        }
    }
}
