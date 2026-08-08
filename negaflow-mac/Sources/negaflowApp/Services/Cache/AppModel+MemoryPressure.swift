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
    }

    func applyFrameCachePressure(_ pressure: FrameCachePressureLevel) {
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
    }

    func evictCleanedRawBuffers(_ frame: ScanFrame) {
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
    }
}
