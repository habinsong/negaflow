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
        guard let next = cameraRAWPrefetchCandidate(after: frame) else {
            prefetchNeighborPreviewInput(around: frame, after: previous)
            return
        }
        let url = next.rawScanURL
        neighborCameraRAWPrefetchFrameID = next.id
        neighborCameraRAWPrefetchTask = Task.detached(priority: .utility) {
            // 취소된 LibRaw 호출이 마무리되기 전에 새 추측 디코드를 겹쳐 쌓지 않는다.
            await previous?.value
            guard !Task.isCancelled else { return }
            await NativeCameraRAW.prefetchPreviewMasterUntilCancelled(url)
        }
    }

    /// TIFF 와 Apple RAW 디코드(포지티브·디지털)를 쓰는 다음 사진의 정착 입력을 미리 굳힌다. 넘기는 순간
    /// 원본 디코드 없이 메모리에서 바로 현상한다. 결과는 그 프레임의 정착 입력 캐시에 들어가고 현상 상주
    /// FIFO 에 등록되므로 자동/수동 상주 한도와 메모리 압박 처리를 그대로 따른다.
    private func prefetchNeighborPreviewInput(around frame: ScanFrame, after previous: Task<Void, Never>?) {
        guard ownsFrame(frame), selectedFrameID == frame.id, activeWorkspaceModule == .develop,
              frameCacheManager.pressureLevel == .normal, frameCacheManager.maxResidentDeveloped >= 2,
              let index = interactionFrameIDs.firstIndex(of: frame.id),
              interactionFrameIDs.indices.contains(index + 1),
              let next = libraryFramesByIDCache[interactionFrameIDs[index + 1]],
              !usesCameraNativeDecode(next), next.isSourceAvailable,
              librarySourceAvailability(for: next) != .offline,
              cachedSettledPreviewRaw(for: next) == nil,
              !next.defectEditsLoadDeferred, !next.requiresCleanedRawForActiveDefects,
              next.identityMatchedCleanedRawImage == nil,
              next.inputGammaPreviewOverride == nil, next.inputGammaPreviewSource == nil,
              let key = selectionPreviewSessionKey(for: next) else { return }
        let baseKey = FilmBaseCacheKey(
            filmType: next.filmType,
            mode: next.params.baseEstimationMode,
            manualBaseRGB: next.params.manualBaseRGB,
            filmStockDminID: next.params.filmStockDminID,
            lightSourceProfileID: next.params.lightSourceProfileID,
            imageTransform: next.imageTransform
        )
        var snapshot = makeSnapshot(
            for: next, baseKey: baseKey,
            needsRawPreview: false, needsNeutralPreview: false, needsDebugPreviews: false,
            needsThumbnail: false, proxyMaxDimension: DevelopFrameRenderer.fullMaxDimension
        )
        snapshot.inputPreviewSession = ImagePreviewSession(
            url: key.url, inputGamma: key.inputGamma, rawRendering: key.rendering,
            applyOrientation: key.applyOrientation, interpretInputGamma: key.interpretInputGamma)
        let prepared = snapshot
        let cleanRawRevision = next.cleanRawRevision
        let params = next.params
        let sourceURL = next.rawScanURL
        neighborCameraRAWPrefetchFrameID = next.id
        neighborCameraRAWPrefetchTask = Task { [weak self, weak next] in
            await previous?.value
            guard !Task.isCancelled else { return }
            let input = await Task.detached(priority: .utility) { () -> DevelopFramePreviewRaw? in
                guard !Task.isCancelled, !ExportSourceMaterialization.isEvicted(sourceURL) else { return nil }
                return try? DevelopFrameRenderer.settledPreviewInput(prepared)
            }.value
            guard let self, let next, let input, !Task.isCancelled, self.ownsFrame(next),
                  self.frameCacheManager.pressureLevel == .normal,
                  next.cleanRawRevision == cleanRawRevision, next.params == params,
                  next.rawScanURL == sourceURL,
                  self.cachedSettledPreviewRaw(for: next) == nil else { return }
            self.applyPreviewRawCache(input, to: next, maxDimension: DevelopFrameRenderer.fullMaxDimension)
            self.markDevelopedResident(next)
        }
    }
}
