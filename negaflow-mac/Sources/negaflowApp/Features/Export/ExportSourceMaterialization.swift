import Foundation

/// iCloud Drive 가 로컬 사본을 내린(dataless) 원본을 쓰기 **전에** 한 번에 받아둔다.
///
/// 이런 파일은 열어서 읽는 순간 커널이 다운로드가 끝날 때까지 그 스레드를 막는다. 그래서
/// 아무 표시 없이 특정 프레임에서 수십 초 멈춘 것처럼 보인다. 여기서 먼저 상태를 확인하고
/// 다운로드를 요청해, 기다림을 예측 가능한 한 구간으로 모은다.
///
/// 파일 시스템을 만지는 일은 전부 detached 로 내보낸다. 호출자가 MainActor 여도 이 타입
/// 때문에 UI 가 멈추지 않아야 한다.
enum ExportSourceMaterialization {
    struct Progress: Sendable, Equatable {
        let total: Int
        let ready: Int

        var remaining: Int { max(0, total - ready) }
    }

    /// 상태 재확인 간격. 처음에는 촘촘히 보고 길어지면 늘린다 — 파일이 많을 때 매번 전부
    /// 다시 묻는 것 자체가 iCloud 데몬을 붙잡는다.
    private static let minimumPollInterval: TimeInterval = 0.3
    private static let maximumPollInterval: TimeInterval = 2

    /// 로컬 사본이 없는 iCloud 원본만 중복 없이 골라낸다. 로컬 파일과 이미 받아둔 파일은 제외한다.
    nonisolated static func evictedSources(among urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap { url in
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { return nil }
            return isEvicted(standardized) ? standardized : nil
        }
    }

    nonisolated static func isEvicted(_ url: URL) -> Bool {
        // URL 은 한 번 읽은 resource value 를 캐시한다. 다운로드 상태는 기다리는 동안 바뀌는
        // 값이라 캐시를 지우지 않으면 파일이 다 내려온 뒤에도 계속 notDownloaded 로 보이고,
        // 진행률이 0% 에 멈춘 채 타임아웃까지 기다리게 된다.
        var probe = url
        probe.removeAllCachedResourceValues()
        guard let values = try? probe.resourceValues(forKeys: [
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
        onProgress: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async -> Bool {
        let pending = await Task.detached(priority: .userInitiated) {
            evictedSources(among: urls)
        }.value
        guard !pending.isEmpty else { return true }
        let total = pending.count
        onProgress(Progress(total: total, ready: 0))

        await Task.detached(priority: .userInitiated) {
            for url in pending {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }.value

        let deadline = Date().addingTimeInterval(timeout)
        var remaining = pending
        var lastReported = 0
        var pollInterval = minimumPollInterval
        while !remaining.isEmpty, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            guard !Task.isCancelled else { break }
            let stillEvicted = remaining
            remaining = await Task.detached(priority: .utility) {
                stillEvicted.filter { isEvicted($0) }
            }.value
            let ready = total - remaining.count
            if ready != lastReported {
                lastReported = ready
                onProgress(Progress(total: total, ready: ready))
                pollInterval = minimumPollInterval
            } else {
                pollInterval = min(pollInterval * 1.5, maximumPollInterval)
            }
        }
        return remaining.isEmpty
    }
}
