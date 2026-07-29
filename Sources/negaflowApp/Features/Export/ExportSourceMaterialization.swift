import Foundation

/// iCloud Drive 가 로컬 사본을 내린(dataless) 원본을 내보내기 **전에** 한 번에 받아둔다.
///
/// 이런 파일은 열어서 읽는 순간 커널이 다운로드가 끝날 때까지 그 스레드를 막는다. 그래서
/// 아무 표시 없이 특정 프레임에서 수십 초 멈춘 것처럼 보인다. 여기서 먼저 상태를 확인하고
/// 다운로드를 요청해, 기다림을 예측 가능한 한 구간으로 모은다.
enum ExportSourceMaterialization {
    struct Progress: Sendable, Equatable {
        let total: Int
        let ready: Int

        var remaining: Int { max(0, total - ready) }
    }

    /// 로컬 사본이 없는 iCloud 원본만 중복 없이 골라낸다. 로컬 파일과 이미 받아둔 파일은 제외한다.
    static func evictedSources(among urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap { url in
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { return nil }
            return isEvicted(standardized) ? standardized : nil
        }
    }

    static func isEvicted(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ]), values.isUbiquitousItem == true else { return false }
        // .current 만 "로컬에 최신 사본이 있다"는 뜻이다. .downloaded 는 오래된 사본이 남아 있는
        // 상태이므로 그대로 읽으면 안 되고, .notDownloaded 는 사본이 아예 없다.
        return values.ubiquitousItemDownloadingStatus != .current
    }

    /// 주어진 원본들의 다운로드를 요청하고 전부 로컬에 올라올 때까지 기다린다.
    /// 진행 상황은 상태가 바뀔 때만 `onProgress` 로 보고한다. 반환값은 전부 준비됐는지 여부다.
    static func materialize(
        _ urls: [URL],
        timeout: TimeInterval = 600,
        pollInterval: TimeInterval = 0.25,
        onProgress: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async -> Bool {
        let pending = evictedSources(among: urls)
        guard !pending.isEmpty else { return true }
        let total = pending.count
        onProgress(Progress(total: total, ready: 0))

        for url in pending {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var remaining = pending
        var lastReported = -1
        while !remaining.isEmpty, Date() < deadline, !Task.isCancelled {
            let stillEvicted = remaining
            let refreshed = await Task.detached(priority: .userInitiated) {
                stillEvicted.filter { isEvicted($0) }
            }.value
            remaining = refreshed
            let ready = total - remaining.count
            if ready != lastReported {
                lastReported = ready
                onProgress(Progress(total: total, ready: ready))
            }
            guard !remaining.isEmpty else { break }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        return remaining.isEmpty
    }
}
