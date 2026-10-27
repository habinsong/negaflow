import Foundation
import Chromabase

// MARK: - 채널 범위 롤 교정
//
// 자동 밸런스 OFF 의 고정 반전은 세 채널에 같은 밀도 범위를 쓰므로 장치·필름이 정하는 실제 채널
// 범위비만큼 색이 기운다(ChannelRangeCalibration 머리말). 이 교정은 렌더가 프레임마다 한 번 잰
// 모양(`ScanFrame.rangeShape`)을 같은 롤(없으면 같은 스캔 폴더)에서 모아 중앙값 하나로 정하고,
// 그 값을 각 프레임의 `params.channelRange` 로 찍는다. 찍힌 값은 프레임에 영속되고 이후 표본이
// 늘어도 바뀌지 않는다 — 같은 입력과 같은 params 는 같은 그림이어야 하기 때문이다.
extension AppModel {
    /// 렌더 결과를 받은 직후에 부른다. 새로 잰 모양을 프레임에 기록하고 묶음 교정을 시도한다.
    func applyRangeCalibration(_ result: DevelopFrameRenderResult, to frame: ScanFrame) {
        guard frame.filmType == .colorNegative else { return }
        if result.rangeShapeAttempted { frame.rangeShapeAttempted = true }
        if frame.rangeShape == nil, let shape = result.rangeShape {
            frame.rangeShape = shape
            calibrateChannelRange(around: frame)
            return
        }
        // 교정이 비어 있는 프레임(카탈로그에서 막 올라왔거나 설정 초기화로 지워진 경우)은 한 번만 시도한다.
        guard frame.params.channelRange == nil, !frame.rangeCalibrationSettled else { return }
        calibrateChannelRange(around: frame)
    }

    /// `frame` 이 속한 묶음의 교정값을 정하고, 아직 교정이 없는 묶음 구성원에게 찍는다.
    func calibrateChannelRange(around frame: ScanFrame) {
        frame.rangeCalibrationSettled = true
        var rollOfFrame: [UUID: UUID] = [:]
        for roll in rollStore.rolls where roll.kind == .physical {
            for id in roll.frameIDs { rollOfFrame[id] = roll.id }
        }
        func group(of candidate: ScanFrame) -> ChannelRangeCalibrator.Group {
            ChannelRangeCalibrator.group(
                rollID: rollOfFrame[candidate.id],
                sourceFolder: candidate.rawScanURL.deletingLastPathComponent().path,
                source: candidate.sourceKind
            )
        }
        let target = group(of: frame)
        let members = frames.filter {
            $0.filmType == .colorNegative && $0.sourceKind == frame.sourceKind && group(of: $0) == target
        }
        let resolved = ChannelRangeCalibrator.resolve(members.map {
            .init(shape: $0.rangeShape, stamped: $0.params.channelRange,
                  contributesShape: !$0.isVirtualCopy)
        })
        guard let resolved else { return }
        for member in members where member.params.channelRange == nil {
            stampChannelRange(resolved, on: member)
        }
    }

    /// 교정값을 params 에 찍는다. 사용자 편집이 아니므로 되돌리기 기록과 편집 상태 분류에서 뺀다.
    private func stampChannelRange(_ range: SIMD3<Double>, on frame: ScanFrame) {
        let before = frame.currentLibraryDevelopRecipeSHA256()
        frame.updateParams { $0.channelRange = range }
        frame.rangeCalibrationSettled = true
        frame.rebaseUserEditTracking(afterNonUserChangeFrom: before)
        if frameEditBaselines[frame.id] != nil { noteFrameEditBaseline(frame) }
        // 자동 밸런스가 켜져 있으면 그림이 달라지지 않으므로 다시 현상할 이유가 없다.
        guard !frame.params.autoBalance else { return }
        if frame.hasDevelopedOnce { frame.developedIsSettled = false }
        if frame === actionableFrame {
            developController.requestDevelop(frame) { [weak self] frame in
                await self?.developFrame(frame)
            }
        }
    }
}

extension ScanFrame {
    /// 사용자가 하지 않은 params 변경(롤 교정 찍기)을 편집 추적에서 지운다. 변경 전 레시피 해시가
    /// 추적 중인 현재값과 같을 때만 건드리고, 아직 손대지 않은 프레임(가져온 때 해시 = 현재 해시)
    /// 이면 기준점도 같이 옮겨 "편집됨" 으로 바뀌지 않게 한다.
    func rebaseUserEditTracking(afterNonUserChangeFrom before: String?) {
        guard var state = libraryWorkflowTrackingState,
              state.userEditTracking.coverage == .tracked,
              let before, let after = currentLibraryDevelopRecipeSHA256(), before != after,
              state.userEditTracking.currentRecipeSHA256 == before else { return }
        if state.userEditTracking.ingestRecipeSHA256 == before {
            state.userEditTracking.ingestRecipeSHA256 = after
        }
        state.userEditTracking.currentRecipeSHA256 = after
        libraryWorkflowTrackingState = state
    }
}
