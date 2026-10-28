import Foundation

/// 디스크 보정 RAW(cleaned raw TIFF)의 수명.
///
/// 이 파일은 원본과 결함 기록으로 언제든 다시 만들 수 있는 캐시다. 카탈로그는 경로를 남기지 않아
/// 다음 실행에서는 쓰이지 않는다. 그런데도 예전에는 편집마다 새 TIFF(장당 47~290MB)를 쓰고,
/// 입력 해석이 바뀌거나 앱을 다시 켤 때 참조만 끊은 채 파일을 남겨 캐시 폴더가 끝없이 불었다
/// (2026-10-28 실측: 프레임 60장에 파일 284개, 14GB).
///
/// 이제는 메모리 상주 한도가 그 프레임의 보정 RAW 를 내려놓을 때만 디스크에 쓴다. 디스크에는
/// 최근에 내려놓은 몇 장만 남기고, 참조가 끊긴 파일은 지운다. 실행 시작 때는 지난 실행의 파일을
/// 모두 지운다.
extension AppModel {
    /// 디스크에 남기는 보정 RAW 장수. 메모리 상주 한도(설정의 자동/수동 값)의 두 배, 최소 8장.
    var cleanedRawDiskFrameLimit: Int { max(8, maxResidentCleanedRaw * 2) }
    /// 장수와 별개인 총량 상한. 96MP 원본 한 장이 약 290MB 다.
    static let cleanedRawDiskByteLimit: Int64 = 4 * 1_024 * 1_024 * 1_024
    /// 쓰는 중일 수 있는 파일은 이보다 오래된 것만 지운다.
    static let cleanedRawDiskMinimumFileAge: TimeInterval = 60
    static let cleanedRawDiskSweepDelayNanoseconds: UInt64 = 5_000_000_000

    /// 메모리에서 내려놓기 직전에 부른다. 현재 기록과 맞는 픽셀이 있고 디스크에 같은 것이 없을 때만
    /// 쓴다. 이미 있으면 최근 사용으로 표시만 한다. 메모리가 급한 때는 쓰지 않는다 — 큰 TIFF 를 쓰는
    /// 동안 픽셀을 붙잡게 되고, 나중에 원본과 기록으로 다시 만들면 된다.
    func persistCleanedRawBeforeEviction(_ frame: ScanFrame) {
        guard let image = frame.cleanedRawImage,
              let identity = frame.cleanedRawMemoryIdentity,
              identity == frame.defectRecipeIdentity,
              frame.cleanedRawEditCount == frame.defectEdits.count,
              frame.requiresCleanedRawForActiveDefects else { return }
        if frame.cleanedRawDiskIdentity == identity, let url = frame.cleanedRawDiskURL {
            Task.detached(priority: .utility) {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            }
            return
        }
        guard frameCacheManager.pressureLevel != .critical else { return }
        scheduleCleanedRawPersist(frame, image: image, identity: identity, revision: frame.cleanRawRevision)
    }

    func scheduleCleanedRawDiskSweep() {
        guard libraryPersistenceEnabled, cleanedRawDiskSweepTask == nil else { return }
        cleanedRawDiskSweepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: AppModel.cleanedRawDiskSweepDelayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.cleanedRawDiskSweepTask = nil
            await self.sweepCleanedRawDisk()
        }
    }

    /// 한도를 넘는 오래된 디스크 백킹의 참조를 끊고, 어느 프레임도 가리키지 않는 파일을 지운다.
    func sweepCleanedRawDisk() async {
        guard libraryPersistenceEnabled, libraryCatalogBlockReason == nil else { return }
        let directory = diskStorage.cleanedRawURL
        var protected = Set(residentCleanedRawIDs)
        if let selectedFrameID { protected.insert(selectedFrameID) }
        let backed = frames.compactMap { frame -> (id: UUID, url: URL, protected: Bool)? in
            guard let url = frame.cleanedRawDiskURL else { return nil }
            let busy = frame.cleanRawTask != nil || frame.cleanedRawPersistTask != nil
                || developController.isDevelopingFrame(frame)
            return (frame.id, url, busy || protected.contains(frame.id))
        }
        let measured = await Task.detached(priority: .utility) {
            backed.map { entry -> (id: UUID, url: URL, protected: Bool, modified: Date, size: Int64) in
                let attributes = try? FileManager.default.attributesOfItem(atPath: entry.url.path)
                return (entry.id, entry.url, entry.protected,
                        attributes?[.modificationDate] as? Date ?? .distantPast,
                        (attributes?[.size] as? NSNumber)?.int64Value ?? 0)
            }
        }.value
        let leased = CleanedRawCacheFile.leasedPaths()
        var keptCount = 0
        var keptBytes: Int64 = 0
        var released = false
        for entry in measured.sorted(by: { $0.modified > $1.modified }) {
            let fits = keptCount < cleanedRawDiskFrameLimit
                && keptBytes + entry.size <= AppModel.cleanedRawDiskByteLimit
            if entry.protected || fits || leased.contains(entry.url.standardizedFileURL.path) {
                keptCount += 1
                keptBytes += entry.size
                continue
            }
            guard let frame = frames.first(where: { $0.id == entry.id }),
                  frame.cleanedRawDiskURL == entry.url else { continue }
            frame.cleanedRawDiskURL = nil
            frame.cleanedRawDiskIdentity = nil
            released = true
        }
        let keep = Set(frames.compactMap { $0.cleanedRawDiskURL?.standardizedFileURL.path })
        let minimumAge = AppModel.cleanedRawDiskMinimumFileAge
        _ = await Task.detached(priority: .utility) {
            CleanedRawCacheFile.removeUnreferenced(in: directory, keeping: keep, minimumAge: minimumAge)
        }.value
        if released { scheduleLibrarySave() }
    }
}
