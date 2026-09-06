import Foundation
import Chromabase

extension AppModel {
    func checkInputGammaSupport(for frame: ScanFrame) async {
        let revision = frame.sourceLocationRevision
        let url = frame.rawScanURL
        frame.inputGammaSupportChecked = false
        frame.inputGammaSourceInfo = nil
        let result = await Task.detached(priority: .userInitiated) {
            Result { try ImageLoader.inputGammaSourceInfo(url) }
        }.value
        guard !Task.isCancelled, ownsFrame(frame), frame.sourceLocationRevision == revision else { return }
        switch result {
        case .success(let info):
            frame.inputGammaSourceInfo = info
            frame.inputGammaSourceError = info.manualError
        case .failure(let error):
            frame.inputGammaSourceError = (error as? InputGammaDecodeError) ?? .decodeFailed
        }
        frame.inputGammaSupportChecked = true
    }

    private nonisolated static func inputGammaSourceFailure(_ url: URL) async -> InputGammaDecodeError? {
        await Task.detached(priority: .userInitiated) {
            do {
                return try ImageLoader.inputGammaSourceInfo(url).manualError
            } catch { return (error as? InputGammaDecodeError) ?? .decodeFailed }
        }.value
    }
    /// 지원 판정 뒤 측정 베이스를 무효화하고 배율을 보존한 입력 변경을 한 편집으로 기록합니다.
    @discardableResult
    func setInputGamma(_ gamma: InputGammaInterpretation, for frame: ScanFrame) async -> Bool {
        guard ownsFrame(frame), !frame.isPreviewScan,
              !frame.defectEditsNeedRestore else { return false }
        if frame.params.inputGamma == gamma {
            // 진행 중인 다른 값에서 현재 값으로 돌아온 입력도 이전 요청을 취소해야 합니다.
            frame.inputGammaRequestRevision &+= 1
            frame.isApplyingInputGamma = false
            return false
        }
        let params = frame.params
        let sourceRevision = frame.sourceLocationRevision
        let rawURL = frame.rawScanURL
        let selectedID = selectedFrameID
        frame.inputGammaRequestRevision &+= 1
        let requestRevision = frame.inputGammaRequestRevision
        frame.isApplyingInputGamma = true
        defer {
            if frame.inputGammaRequestRevision == requestRevision { frame.isApplyingInputGamma = false }
        }
        if gamma != .automatic {
            let failure = await Self.inputGammaSourceFailure(rawURL)
            guard inputGammaRequestIsCurrent(frame, requestRevision: requestRevision,
                    sourceRevision: sourceRevision, params: params, selectedID: selectedID) else { return false }
            if let failure {
                frame.inputGammaSourceError = failure
                statusMessage = text(failure == .decodeFailed ? .inputGammaLoadFailed : .inputGammaUnsupported)
                return false
            }
        }
        guard inputGammaRequestIsCurrent(frame, requestRevision: requestRevision,
                sourceRevision: sourceRevision, params: params, selectedID: selectedID) else { return false }
        cancelInfraredClean(frame)
        frame.inputGammaSourceError = frame.inputGammaSourceInfo?.manualError
        cancelRegionDefect(frame)
        // 감마는 이산 편집입니다. 이전 슬라이더와 다음 편집에 undo가 합쳐지지 않습니다.
        frameEditCoalesceTasks[frame.id]?.cancel()
        frameEditCoalesceTasks[frame.id] = nil
        noteFrameEditBaseline(frame)
        frame.updateParams {
            $0.inputGamma = gamma
            $0.manualBaseRGB = nil
            if $0.baseEstimationMode == .manual { $0.baseEstimationMode = .auto }
        }
        pixelSamplerStore.removeFrame(frame.id)
        requestDevelop(frame)
        frameEditCoalesceTasks[frame.id]?.cancel()
        frameEditCoalesceTasks[frame.id] = nil
        noteFrameEditBaseline(frame)
        return true
    }

    private func inputGammaRequestIsCurrent(
        _ frame: ScanFrame, requestRevision: UInt64, sourceRevision: UInt64,
        params: DevelopParameters, selectedID: UUID?
    ) -> Bool {
        !Task.isCancelled && ownsFrame(frame)
            && frame.inputGammaRequestRevision == requestRevision
            && frame.sourceLocationRevision == sourceRevision
            && frame.params == params && selectedFrameID == selectedID
    }
}
