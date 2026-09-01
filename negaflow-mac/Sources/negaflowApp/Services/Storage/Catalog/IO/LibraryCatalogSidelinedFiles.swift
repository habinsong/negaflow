import Foundation

/// 복구 과정에서 옆으로 치워 둔 카탈로그 사본(`library.corrupt-*`, `library.pre-repair-*`)과
/// 그 짝인 결함 폴더를 정리한다. 최근 것 몇 개는 남긴다 — 마지막으로 기댈 사본이라서
/// 무조건 지우면 안 되고, 무한정 쌓아 두면 지원 폴더가 계속 커진다.
enum LibraryCatalogSidelinedFiles {
    static let defaultRetentionCount = 3

    private static let catalogPrefixes = ["library.corrupt-", "library.pre-repair-"]
    private static let defectPrefix = "defects.corrupt-"

    static func prune(
        in directory: URL,
        keeping retentionCount: Int = defaultRetentionCount,
        fileManager: FileManager = .default
    ) {
        let keep = max(1, retentionCount)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for prefix in catalogPrefixes + [defectPrefix] {
            let matches = urls.filter { $0.lastPathComponent.hasPrefix(prefix) }
            guard matches.count > keep else { continue }
            let ordered = matches.sorted { lhs, rhs in
                let lhsDate = modificationDate(of: lhs, fileManager: fileManager)
                let rhsDate = modificationDate(of: rhs, fileManager: fileManager)
                if lhsDate == rhsDate {
                    return lhs.lastPathComponent < rhs.lastPathComponent
                }
                return lhsDate > rhsDate
            }
            for url in ordered.dropFirst(keep) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private static func modificationDate(
        of url: URL,
        fileManager: FileManager
    ) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }
}
