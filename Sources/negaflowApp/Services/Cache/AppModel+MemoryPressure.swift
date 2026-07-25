import Foundation

extension AppModel {
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
