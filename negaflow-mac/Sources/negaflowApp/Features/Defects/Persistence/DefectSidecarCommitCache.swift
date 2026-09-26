import Foundation
import ScannerKit

/// 검증된 sidecar 세대만 기억합니다. 카탈로그 저장마다 큰 마스크를 다시 풀지 않습니다.
final class DefectSidecarCommitCache: @unchecked Sendable {
    static let shared = DefectSidecarCommitCache()
    private let lock = NSLock()
    private var entries: [String: (DefectRecipeIdentity, CaptureFileObservation)] = [:]

    func record(_ identity: DefectRecipeIdentity, at url: URL) {
        guard let observation = try? CaptureFileObservation.capture(for: url) else { return }
        lock.lock()
        entries[url.path] = (identity, observation)
        lock.unlock()
    }

    /// ctime은 비교하지 않는다. 시스템이 기록 뒤에 `com.apple.provenance` 등 확장 속성을
    /// 붙이면 내용과 무관하게 ctime이 바뀌어, 한 번 어긋나면 그 세션의 카탈로그 저장이 전부 막힌다.
    func matches(_ identity: DefectRecipeIdentity, at url: URL) -> Bool {
        lock.lock()
        let entry = entries[url.path]
        lock.unlock()
        guard let entry, entry.0 == identity,
              let observation = try? CaptureFileObservation.capture(for: url) else { return false }
        return entry.1.identifiesSameFile(as: observation)
    }

    /// 관찰값이 어긋났을 때의 대체 확인. 백업·동기화 도구가 수정 시각이나 속성만 바꿔도 관찰값은
    /// 어긋나므로, 그것만으로 저장을 막지 않고 디스크 기록을 직접 읽어 같은 세대인지 본다.
    /// 같으면 지금 관찰값을 새로 기억해 다음 저장부터는 다시 가볍게 확인한다.
    func revalidate(_ identity: DefectRecipeIdentity, frameID: UUID, in directory: URL) -> Bool {
        let stored: DefectRecipeIdentity?
        switch DefectSidecarFile.read(for: frameID, in: directory) {
        case .loaded(.currentV2(_, let snapshot)):
            stored = snapshot.identity
        case .loaded(.legacyV1(_, let records)):
            stored = (try? DefectRecipeSnapshot(
                frameID: frameID, revision: 1, sourceIdentity: nil, items: records
            ))?.identity
        case .missing, .unsupportedVersion, .invalid, .unreadable:
            stored = nil
        }
        guard stored == identity else { return false }
        record(identity, at: DefectSidecarFile.url(for: frameID, in: directory))
        return true
    }
}
