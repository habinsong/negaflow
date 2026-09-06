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

    func matches(_ identity: DefectRecipeIdentity, at url: URL) -> Bool {
        lock.lock()
        let entry = entries[url.path]
        lock.unlock()
        guard let entry, entry.0 == identity,
              let observation = try? CaptureFileObservation.capture(for: url) else { return false }
        return entry.1 == observation
    }
}
