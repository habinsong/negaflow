import Foundation

/// 디스크 읽기·압축 해제는 백그라운드에서 끝낸 뒤 프레임에 전달합니다.
struct DefectRecipeRestoration: @unchecked Sendable {
    let snapshot: DefectRecipeSnapshot?
    let items: [DefectEditItem]

    static func read(frameID: UUID, in directory: URL) -> Self {
        let snapshot: DefectRecipeSnapshot?
        switch DefectSidecarFile.read(for: frameID, in: directory) {
        case .loaded(.currentV2(_, let stored)):
            snapshot = stored
        case .loaded(.legacyV1(_, let records)):
            snapshot = try? DefectRecipeSnapshot(
                frameID: frameID, revision: 1, sourceIdentity: nil, items: records
            )
        default:
            snapshot = nil
        }
        let records = snapshot.flatMap { try? DefectSidecarResourcePolicy.normalizedItems($0.items) }
        let items = records?.compactMap { $0.makeItem() } ?? []
        guard let snapshot, items.count == snapshot.items.count else {
            return Self(snapshot: nil, items: [])
        }
        DefectSidecarCommitCache.shared.record(snapshot.identity, at: DefectSidecarFile.url(for: frameID, in: directory))
        return Self(snapshot: snapshot, items: items)
    }

    @MainActor
    func apply(to frame: ScanFrame) {
        guard let snapshot, snapshot.frameID == frame.id else {
            frame.defectEditsNeedRestore = true
            return
        }
        frame.defectEdits = items
        frame.defectRecipeIdentity = snapshot.identity
        frame.defectRecipeRevision = snapshot.identity.revision
        frame.defectEditsNeedRestore = false
    }
}
