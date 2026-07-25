import Foundation

@MainActor
final class FrameCacheManager {
    let policy: FrameCachePolicy
    private(set) var pressureLevel: FrameCachePressureLevel = .normal

    var maxResidentCleanedRaw: Int { currentLimits.cleanedRaw }
    var maxResidentDeveloped: Int { currentLimits.developed }

    private(set) var residentCleanedRawIDs: [UUID] = []
    private(set) var residentDevelopedIDs: [UUID] = []

    init(maxResidentCleanedRaw: Int = 2, maxResidentDeveloped: Int = 3) {
        policy = FrameCachePolicy(normalLimits: FrameCacheLimits(
            cleanedRaw: maxResidentCleanedRaw,
            developed: maxResidentDeveloped
        ))
    }

    private var currentLimits: FrameCacheLimits { policy.limits(for: pressureLevel) }

    /// FIFO 재등록 후 한도 초과분을 축출한다. 축출 프레임은 `onEvict`로 넘기며,
    /// 호출자가 메모리 이미지와 재생성 가능한 임시 상태를 내려놓는다.
    func markCleanedRawResident(_ frame: ScanFrame, frames: [ScanFrame],
                                onEvict: (ScanFrame) -> Void) {
        residentCleanedRawIDs.removeAll { $0 == frame.id }
        residentCleanedRawIDs.append(frame.id)
        trimCleanedRaw(frames: frames, onEvict: onEvict)
    }

    func removeCleanedRawResident(_ frame: ScanFrame) {
        residentCleanedRawIDs.removeAll { $0 == frame.id }
    }

    func markDevelopedResident(
        _ frame: ScanFrame,
        selectedFrameID: UUID?,
        frames: [ScanFrame],
        evictBuffers: (ScanFrame) -> Void
    ) {
        residentDevelopedIDs.removeAll { $0 == frame.id }
        residentDevelopedIDs.append(frame.id)
        trimDeveloped(
            selectedFrameID: selectedFrameID,
            frames: frames,
            evictBuffers: evictBuffers
        )
    }

    func applyPressure(
        _ pressure: FrameCachePressureLevel,
        selectedFrameID: UUID?,
        frames: [ScanFrame],
        evictCleanedRaw: (ScanFrame) -> Void,
        evictDeveloped: (ScanFrame) -> Void
    ) {
        pressureLevel = pressure
        trimCleanedRaw(frames: frames, onEvict: evictCleanedRaw)
        trimDeveloped(
            selectedFrameID: selectedFrameID,
            frames: frames,
            evictBuffers: evictDeveloped
        )
    }

    private func trimCleanedRaw(
        frames: [ScanFrame],
        onEvict: (ScanFrame) -> Void
    ) {
        while residentCleanedRawIDs.count > maxResidentCleanedRaw {
            let evictID = residentCleanedRawIDs.removeFirst()
            if let evicted = frames.first(where: { $0.id == evictID }) {
                onEvict(evicted)
            }
        }
    }

    private func trimDeveloped(
        selectedFrameID: UUID?,
        frames: [ScanFrame],
        evictBuffers: (ScanFrame) -> Void
    ) {
        while residentDevelopedIDs.count > maxResidentDeveloped {
            guard let evictID = residentDevelopedIDs.first else { break }
            if evictID == selectedFrameID {
                residentDevelopedIDs.removeFirst()
                residentDevelopedIDs.append(evictID)
                if residentDevelopedIDs.allSatisfy({ $0 == selectedFrameID }) { break }
                continue
            }
            residentDevelopedIDs.removeFirst()
            if let evicted = frames.first(where: { $0.id == evictID }) {
                evictBuffers(evicted)
            }
        }
    }

    func removeDevelopedResident(_ frame: ScanFrame) {
        residentDevelopedIDs.removeAll { $0 == frame.id }
    }
}
