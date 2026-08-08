import SwiftUI
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    func ensureCleanedRawResident(_ frame: ScanFrame) {
        Task {
            guard await prepareCleanedRawForConsumption(frame),
                  ownsFrame(frame),
                  let expectedIdentity = frame.boundDefectRecipeIdentity else { return }
            if frame.cleanedRawImage != nil,
               frame.cleanedRawMemoryIdentity == expectedIdentity {
                cleanedRawResidentInsert(frame)
                return
            }
            frame.cleanedRawImage = nil
            frame.cleanedRawMemoryIdentity = nil
            frame.cleanedRawAppliedStamps = []
            guard let url = frame.cleanedRawDiskURL,
                  frame.cleanedRawDiskIdentity == expectedIdentity else { return }
            let rawURL = frame.rawScanURL
            let revision = frame.cleanRawRevision
            let loaded = await Task.detached(priority: .utility) {
                guard let sourceIdentity = expectedIdentity.sourceIdentity else {
                    return (source: CaptureFileVerificationResult.unavailable, image: nil as CGImage?)
                }
                guard let currentIdentity = try? AppModel.defectSourceIdentity(for: rawURL) else {
                    return (source: CaptureFileVerificationResult.unavailable, image: nil as CGImage?)
                }
                guard currentIdentity == sourceIdentity else {
                    return (source: CaptureFileVerificationResult.mismatch, image: nil as CGImage?)
                }
                return (source: CaptureFileVerificationResult.match, image: decodeCleanedRaw(url))
            }.value
            guard ownsFrame(frame),
                  frame.rawScanURL == rawURL,
                  frame.cleanRawRevision == revision,
                  frame.defectRecipeIdentity == expectedIdentity,
                  frame.cleanedRawDiskIdentity == expectedIdentity else { return }
            guard loaded.source != .unavailable else {
                discardCleanedRaw(frame, preservingDefectSidecar: true)
                return
            }
            guard loaded.source == .match else {
                recoverFromChangedDefectSource(
                    frame,
                    revision: revision,
                    expectedRecipeIdentity: expectedIdentity,
                    quiet: false
                )
                return
            }
            guard let cg = loaded.image else {
                discardCleanedRaw(frame, preservingDefectSidecar: true)
                if !frame.defectEdits.isEmpty { rebuildCleanedRaw(frame) }
                return
            }
            frame.cleanedRawImage = cg
            frame.cleanedRawMemoryIdentity = expectedIdentity
            // identity 가 현재 recipe 와 일치하므로 이 픽셀은 현재 편집 전체를 담고 있다.
            frame.cleanedRawEditCount = frame.defectEdits.count
            frame.cleanedRawAppliedStamps = frame.defectEdits.map(\.appliedStamp)
            cleanedRawResidentInsert(frame)
        }
    }

    /// FIFO 한도 초과 시 픽셀 버퍼와 패치 캐시만 내려놓는다. cache TIFF와 recipe sidecar가
    /// 남아 있어 export와 재선택 결과는 변하지 않는다.
    func cleanedRawResidentInsert(_ frame: ScanFrame) {
        frameCacheManager.markCleanedRawResident(frame, frames: frames) { evicted in
            evictCleanedRawBuffers(evicted)
        }
    }

    /// 발색 결과 FIFO에 프레임을 (재)등록하고, 한도를 넘으면 가장 오래된 비선택 프레임의 풀해상도
    /// 버퍼를 내려놓는다(썸네일은 유지). 선택 프레임은 절대 내려놓지 않는다.
    func markDevelopedResident(_ frame: ScanFrame) {
        frameCacheManager.markDevelopedResident(
            frame,
            selectedFrameID: selectedFrameID,
            frames: frames
        ) { evicted in
            evictDevelopBuffers(evicted)
        }
    }

    /// 비활성 프레임의 풀해상도 발색 버퍼를 해제한다(썸네일/현상완료 플래그/base는 유지).
    /// 재진입 시 raw(또는 cleaned raw)에서 재현상해 즉시 복원한다.
    func evictDevelopBuffers(_ frame: ScanFrame) {
        frame.developedImage = nil
        // 결과를 내려놓았으니 "정착 완료" 표시도 함께 내린다 — 이미지 없이 settled 로 남으면
        // 상태가 모순되고, 재진입 판정이 첫 조건을 스치는 경로에서 저해상도로 굳을 수 있다.
        frame.developedIsSettled = false
        frame.clippingOverlayImage = nil
        frame.destinationGamutOverlayImage = nil
        frame.rawPreviewImage = nil
        frame.neutralPreviewImage = nil
        frame.mainPreviewImage = nil
        frame.developedPreviewTransform = nil
        frame.rawPreviewTransform = nil
        frame.neutralPreviewTransform = nil
        frame.neutralPreviewBaseKey = nil
        frame.mainPreviewTransform = nil
        frame.mainPreviewDevelopRevision = -1
        frame.cachedDevelopedBase = nil
        frame.cachedClippingOverlayBase = nil
        frame.cachedDestinationGamutOverlayBase = nil
        frame.cachedThumbnailBase = nil
        frame.cachedRawBase = nil
        frame.cachedNeutralBase = nil
        frame.cachedMainBase = nil
        pixelSamplerStore.removeFrame(frame.id)
        frame.clearPreviewRawCaches()
        if !frame.debugPreviewImages.isEmpty { frame.debugPreviewImages = [:] }
        if !frame.debugMetrics.isEmpty { frame.debugMetrics = [:] }
    }

    /// cleaned raw generation이 바뀌면 Raw/Neutral 비교와 렌더 입력 캐시는 이전 recipe 픽셀을
    /// 가리킨다. 현재 developed 이미지는 다음 develop 완료까지 유지하되 파생 cache는 즉시 끊는다.
    func invalidateDefectDependentDevelopCaches(_ frame: ScanFrame) {
        frame.clippingOverlayImage = nil
        frame.destinationGamutOverlayImage = nil
        frame.rawPreviewImage = nil
        frame.neutralPreviewImage = nil
        frame.mainPreviewImage = nil
        frame.rawPreviewTransform = nil
        frame.neutralPreviewTransform = nil
        frame.neutralPreviewBaseKey = nil
        frame.mainPreviewTransform = nil
        frame.mainPreviewDevelopRevision = -1
        frame.cachedDevelopedBase = nil
        frame.cachedClippingOverlayBase = nil
        frame.cachedDestinationGamutOverlayBase = nil
        frame.cachedThumbnailBase = nil
        frame.cachedRawBase = nil
        frame.cachedNeutralBase = nil
        frame.cachedMainBase = nil
        pixelSamplerStore.removeFrame(frame.id)
        frame.clearPreviewRawCaches()
        if !frame.debugPreviewImages.isEmpty { frame.debugPreviewImages = [:] }
        if !frame.debugMetrics.isEmpty { frame.debugMetrics = [:] }
    }

    /// 프레임의 재생성 가능한 cleaned raw cache를 제거한다. 기록(defectEdits)은 세션
    /// 메모리에만 있으므로 디스크 sidecar 정리는 없다. 사용자 원본 파일은 건드리지 않는다.
    /// preservingDefectSidecar는 호출부 호환용으로 남긴 무동작 파라미터다.
    func discardCleanedRaw(_ frame: ScanFrame, preservingDefectSidecar: Bool = false) {
        frame.cleanRawTask?.cancel()
        frame.cleanedRawPersistTask?.cancel()
        frame.cleanedRawPersistTask = nil
        frame.cleanedRawImage = nil
        frame.cleanedRawCanvas = nil
        frame.cleanedRawMemoryIdentity = nil
        frame.cleanedRawAppliedStamps = []
        invalidatePreviousBase(frame)
        if let url = frame.cleanedRawDiskURL,
           CleanedRawCacheFile.isOwnedCacheURL(url, frameID: frame.id) {
            try? FileManager.default.removeItem(at: url)
        }
        frame.cleanedRawDiskURL = nil
        frame.cleanedRawDiskIdentity = nil
        frame.cleanedRawEditCount = 0
        frame.clearPreviewRawCaches()
        frameCacheManager.removeCleanedRawResident(frame)
        scheduleLibrarySave()
    }

    static func makeCleanedRawURL(for frame: ScanFrame) -> URL {
        CleanedRawCacheFile.makeBuildURL(frameID: frame.id)
    }

}
