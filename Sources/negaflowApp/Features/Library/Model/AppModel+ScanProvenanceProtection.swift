import Foundation

extension AppModel {
    /// 성공 manifest가 가리키는 root는 캡처 당시의 물리 Roll 소속을 유지한다.
    /// 라이브러리 제거 또는 원본 휴지통 이동은 캡처 기록을 보존한 채 별도로 허용한다.
    func isProtectedScanProvenanceRoot(_ frame: ScanFrame) -> Bool {
        !frame.isPreviewScan
            && !frame.isVirtualCopy
            && (frame.scanSessionID != nil || frame.scanJobID != nil)
    }

    func containsProtectedScanProvenanceRoot(frameIDs: Set<UUID>) -> Bool {
        frames.contains { frameIDs.contains($0.id) && isProtectedScanProvenanceRoot($0) }
    }

    func isProtectedScanProvenanceRoll(_ rollID: UUID) -> Bool {
        if scanRollAssignments.contains(where: { $0.rollID == rollID }) {
            return true
        }
        guard let roll = rolls.first(where: { $0.id == rollID }) else { return false }
        return containsProtectedScanProvenanceRoot(frameIDs: Set(roll.frameIDs))
    }

    func reportProtectedScanProvenanceMutation() {
        statusMessage = text(AppLocalizedPhrase.scanProvenanceProtectedStatus)
    }
}
