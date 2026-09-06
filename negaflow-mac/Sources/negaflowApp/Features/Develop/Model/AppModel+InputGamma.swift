import Foundation
import Chromabase

extension AppModel {
    func checkInputGammaSupport(for frame: ScanFrame) async {
        let revision = frame.sourceLocationRevision
        let url = frame.rawScanURL
        let mayPreparePreview = !frame.isPreviewScan
        frame.inputGammaSupportChecked = false
        frame.inputGammaSourceInfo = nil
        frame.inputGammaPreviewSource = nil
        frame.inputGammaPreviewMeasurements.clear()
        let result = await Task.detached(priority: .userInitiated) {
            Result { () -> (InputGammaSourceInfo, InputGammaPreviewSource?) in
                let info = try ImageLoader.inputGammaSourceInfo(url)
                return (info, info.manualError == nil && mayPreparePreview ? try? InputGammaPreviewSource(url: url) : nil)
            }
        }.value
        guard !Task.isCancelled, ownsFrame(frame), frame.sourceLocationRevision == revision else { return }
        switch result {
        case .success(let (info, previewSource)):
            frame.inputGammaSourceInfo = info
            frame.inputGammaSourceError = info.manualError
            frame.inputGammaPreviewSource = previewSource
            if previewSource != nil { markDevelopedResident(frame) }
        case .failure(let error):
            frame.inputGammaSourceError = (error as? InputGammaDecodeError) ?? .decodeFailed
        }
        frame.inputGammaSupportChecked = true
    }

    /// 드래그 후보는 카탈로그/Undo에 쓰지 않고 기존 리딩·트레일링 렌더 요청으로 전달합니다.
    func previewInputGamma(_ gamma: InputGammaInterpretation?, for frame: ScanFrame) {
        guard ownsFrame(frame), frame.inputGammaPreviewOverride != gamma else { return }
        guard gamma == nil || (actionableFrame === frame && !frame.isApplyingInputGamma
            && !frame.isPreviewScan && !frame.defectEditsNeedRestore
            && frame.inputGammaSourceError == nil && frame.inputGammaSupportChecked) else { return }
        frame.autoAdjustRevision &+= 1
        let previousSession = frame.inputGammaPreviewSessionRevision
        if (gamma == nil) != (frame.inputGammaPreviewOverride == nil) {
            frame.inputGammaPreviewSessionRevision &+= 1
        }
        frame.inputGammaPreviewOverride = gamma
        InputGammaPreviewTrace.emit(gamma == nil ? "finish" : "request", frameID: frame.id,
            session: gamma == nil ? previousSession : frame.inputGammaPreviewSessionRevision, value: gamma?.value)
        frame.developRevision += 1
        frame.cancelSettledDevelopRender?()
        requestDevelop(frame)
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
        frame.cancelSettledDevelopRender?()
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
