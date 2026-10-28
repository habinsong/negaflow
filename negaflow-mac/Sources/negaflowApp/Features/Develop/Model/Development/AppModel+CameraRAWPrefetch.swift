import Chromabase
import Foundation

extension AppModel {
    func usesCameraNativeDecode(_ frame: ScanFrame) -> Bool {
        ImageLoader.kind(of: frame.rawScanURL) == .rawDng
            && ImageLoader.RAWRendering.forDigitalSource(frame.params.isDigitalSource, filmType: frame.filmType)
                == .cameraNativeNegative
    }

    func cameraRAWPrefetchCandidate(after frame: ScanFrame) -> ScanFrame? {
        guard ownsFrame(frame), selectedFrameID == frame.id,
              usesCameraNativeDecode(frame), frameCacheManager.pressureLevel == .normal,
              let index = interactionFrameIDs.firstIndex(of: frame.id),
              interactionFrameIDs.indices.contains(index + 1),
              let next = libraryFramesByIDCache[interactionFrameIDs[index + 1]],
              usesCameraNativeDecode(next), next.isSourceAvailable,
              next.cachedSettledPreviewRaw == nil,
              !next.requiresCleanedRawForActiveDefects else { return nil }
        return next
    }

    func cancelNeighborCameraRAWPrefetch(keeping frameID: UUID? = nil) {
        // 미리 읽던 바로 그 사진을 선택했다면 디코드를 끝내고 선택 렌더와 공유한다.
        if let frameID, frameID == neighborCameraRAWPrefetchFrameID { return }
        neighborCameraRAWPrefetchTask?.cancel()
        neighborCameraRAWPrefetchFrameID = nil
    }

    func prefetchNeighborCameraRAW(around frame: ScanFrame) {
        let previous = neighborCameraRAWPrefetchTask
        cancelNeighborCameraRAWPrefetch()
        guard let next = cameraRAWPrefetchCandidate(after: frame) else { return }
        let url = next.rawScanURL
        neighborCameraRAWPrefetchFrameID = next.id
        neighborCameraRAWPrefetchTask = Task.detached(priority: .utility) {
            // 취소된 LibRaw 호출이 마무리되기 전에 새 추측 디코드를 겹쳐 쌓지 않는다.
            await previous?.value
            guard !Task.isCancelled else { return }
            NativeCameraRAW.prefetchPreviewMaster(url)
        }
    }
}
