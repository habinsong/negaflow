import Foundation

/// 경로 문자열과 함께 보관하는 macOS 파일 bookmark.
///
/// 경로는 사용자에게 마지막 위치를 보여 주고 수동 재연결의 기준으로 남긴다. bookmark는 같은
/// 볼륨 안에서 Finder로 파일이 이동·변경된 경우 새 URL을 복원한다. 앱은 sandboxed target이
/// 아니므로 security-scoped option을 사용하지 않는다.
struct SourceBookmarkLocation {
    let url: URL
    let bookmarkData: Data?
}

enum SourceBookmark {
    static func create(for url: URL, fileManager: FileManager = .default) -> Data? {
        let standardized = url.standardizedFileURL
        guard fileManager.fileExists(atPath: standardized.path) else { return nil }
        return try? standardized.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(
        _ bookmarkData: Data?,
        fallbackURL: URL,
        fileManager: FileManager = .default
    ) -> SourceBookmarkLocation {
        let fallback = fallbackURL.standardizedFileURL
        guard let bookmarkData else {
            return SourceBookmarkLocation(
                url: fallback,
                bookmarkData: create(for: fallback, fileManager: fileManager)
            )
        }

        var isStale = false
        if let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).standardizedFileURL,
           fileManager.fileExists(atPath: resolved.path) {
            return SourceBookmarkLocation(
                url: resolved,
                bookmarkData: isStale
                    ? create(for: resolved, fileManager: fileManager)
                    : bookmarkData
            )
        }

        if fileManager.fileExists(atPath: fallback.path) {
            return SourceBookmarkLocation(
                url: fallback,
                bookmarkData: create(for: fallback, fileManager: fileManager) ?? bookmarkData
            )
        }

        // 볼륨이 offline인 동안에도 원래 bookmark를 보존해 다음 실행/새로고침에서 다시 푼다.
        return SourceBookmarkLocation(url: fallback, bookmarkData: bookmarkData)
    }
}
