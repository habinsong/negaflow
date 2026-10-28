import Chromabase
import Foundation

extension AppModel {
    /// 설정(자동/수동)의 상주 한도를 캐시 매니저에 연결한다. 시작 시 한 번 적용하고, 이후 설정이
    /// 바뀔 때마다 다시 적용한다 — 낮추면 초과분이 즉시 축출된다.
    func bindFrameCacheResidencySettings() {
        applyFrameCacheLimits(frameCacheResidencyStore.effectiveLimits)
        frameCacheResidencyStore.onLimitsChange = { [weak self] limits in
            self?.applyFrameCacheLimits(limits)
        }
    }

    func applyFrameCacheLimits(_ limits: FrameCacheLimits) {
        frameCacheManager.updateNormalLimits(
            limits,
            selectedFrameID: selectedFrameID,
            frames: frames,
            evictCleanedRaw: { [weak self] frame in
                self?.evictCleanedRawBuffers(frame)
            },
            evictDeveloped: { [weak self] frame in
                self?.evictDevelopBuffers(frame)
            }
        )
        NativeCameraRAW.setPreviewCacheResidencyLimit(
            frameCacheManager.pressureLevel == .normal ? frameCacheManager.maxResidentDeveloped : 1)
    }

    func applyFrameCachePressure(_ pressure: FrameCachePressureLevel) {
        // 카메라 RAW 프리뷰 마스터도 같은 압박 신호를 따른다.
        if pressure != .normal {
            cancelNeighborCameraRAWPrefetch()
            NativeCameraRAW.purgePreviewCache()
        }
        frameCacheManager.applyPressure(
            pressure,
            selectedFrameID: selectedFrameID,
            frames: frames,
            evictCleanedRaw: { [weak self] frame in
                self?.evictCleanedRawBuffers(frame)
            },
            evictDeveloped: { [weak self] frame in
                self?.evictDevelopBuffers(frame)
            }
        )
        // 경고 중에는 진행 중 디코드가 끝나도 별도 마스터를 다시 쌓지 않는다.
        NativeCameraRAW.setPreviewCacheResidencyLimit(
            pressure == .normal ? frameCacheManager.maxResidentDeveloped : 1)
    }

    func evictCleanedRawBuffers(_ frame: ScanFrame) {
        // 디스크 백킹은 지금처럼 메모리에서 내려놓을 때만 만든다.
        persistCleanedRawBeforeEviction(frame)
        frame.cleanedRawImage = nil
        frame.cleanedRawCanvas = nil
        frame.cleanedRawMemoryIdentity = nil
        frame.cleanedRawAppliedStamps = []
        frame.cleanedRawPreviousImage = nil
        frame.cleanedRawPreviousEditCount = -1
        frame.cleanedRawPreviousIdentity = nil
        frame.defectSessionRaw = nil
        frame.defectSessionRawRevision = -1
        frame.stripDefectPatchCaches()
        // 진행 중인 persist 는 취소하지 않는다 — 그 결과(디스크 백킹)가 곧 축출의 안전망이다.
        // 결함 항목도 같은 한도를 따른다 — 확정된 기록은 내려놓고 다음에 쓸 때 다시 읽는다.
        unloadCommittedDefectEditsIfIdle(frame)
    }
}
