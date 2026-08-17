import Foundation
import Chromabase

// MARK: - 사진 편집 되돌리기 / 다시 실행
//
// 현상에서 사용자가 바꾸는 것은 결국 네 가지다: 필름 종류, 룩 프리셋, 현상 파라미터, 기하 변형.
// 인스펙터의 모든 슬라이더·곡선·믹서·그레이딩·캘리브레이션·디테일·현상 프로세스·현상 타깃,
// 자동 톤/색상/레벨/화이트밸런스, 크롭·회전·뒤집기, 각종 초기화가 전부 이 네 값 중 하나를 바꾸고
// 재현상을 요청한다. 그래서 되돌리기는 개별 컨트롤이 아니라 **재현상 요청 길목 한 곳**에서
// 기록한다 — 새 컨트롤이 생겨도 저절로 되돌려진다.
//
// 슬라이더를 끄는 동안 수십 번 값이 바뀌므로, 한 번의 조작은 히스토리 한 칸으로 묶는다.
struct FrameEditSnapshot: Equatable {
    var filmType: FilmType
    var presetID: String?
    var params: DevelopParameters
    var imageTransform: ImageTransform
}

extension AppModel {
    /// 연속 조작(드래그)을 한 칸으로 묶는 시간. 이 시간 동안 값이 계속 바뀌면 되돌리기는
    /// 조작 시작 직전 상태로 한 번에 되돌아간다.
    static let frameEditCoalesceInterval: TimeInterval = 0.7

    func frameEditSnapshot(_ frame: ScanFrame) -> FrameEditSnapshot {
        FrameEditSnapshot(
            filmType: frame.filmType,
            presetID: frame.preset?.id,
            params: frame.params,
            imageTransform: frame.imageTransform
        )
    }

    /// 되돌리기 기준점만 세운다. 가져오기·스캔·카탈로그 복원처럼 사용자가 한 일이 아닌 변화가
    /// 히스토리에 섞이지 않도록, 프레임을 처음 볼 때는 항목을 만들지 않는다.
    func noteFrameEditBaseline(_ frame: ScanFrame) {
        frameEditBaselines[frame.id] = frameEditSnapshot(frame)
    }

    /// 지금 상태가 기준점과 다르면 되돌리기 한 칸을 남긴다. 재현상/변형 요청 길목에서 부른다.
    func recordFrameEditIfChanged(_ frame: ScanFrame) {
        guard ownsFrame(frame) else { return }
        let current = frameEditSnapshot(frame)
        guard let baseline = frameEditBaselines[frame.id] else {
            frameEditBaselines[frame.id] = current      // 처음 본 프레임 = 기준점만
            return
        }
        guard !isApplyingFrameEditHistory else {
            frameEditBaselines[frame.id] = current      // 되돌리는 중의 변화는 기록하지 않는다
            return
        }
        guard baseline != current else { return }
        // 드래그 중이면 이미 이번 조작의 시작 상태로 항목을 만들어 뒀다 — 마감만 미룬다.
        guard frameEditCoalesceTasks[frame.id] == nil else {
            scheduleFrameEditBaselineRefresh(frame)
            return
        }
        registerFrameEditUndo(frame, snapshot: baseline)
        frameEditBaselines[frame.id] = current
        scheduleFrameEditBaselineRefresh(frame)
    }

    /// 조작이 멎으면 기준점을 지금 값으로 맞춘다 — 다음 조작이 그 지점으로 되돌아가게.
    private func scheduleFrameEditBaselineRefresh(_ frame: ScanFrame) {
        frameEditCoalesceTasks[frame.id]?.cancel()
        let frameID = frame.id
        frameEditCoalesceTasks[frameID] = Task { [weak self, weak frame] in
            try? await Task.sleep(for: .seconds(AppModel.frameEditCoalesceInterval))
            guard !Task.isCancelled, let self else { return }
            self.frameEditCoalesceTasks[frameID] = nil
            guard let frame, self.ownsFrame(frame) else { return }
            self.frameEditBaselines[frameID] = self.frameEditSnapshot(frame)
        }
    }

    private func registerFrameEditUndo(_ frame: ScanFrame, snapshot: FrameEditSnapshot) {
        guard let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.applyFrameEditSnapshot(snapshot, to: frame)
        }
    }

    /// 히스토리 한 칸을 적용한다. 되돌리는 중 등록한 항목은 UndoManager 가 다시 실행으로 잡으므로
    /// ⌘Z 와 ⇧⌘Z 가 같은 코드로 왕복한다.
    func applyFrameEditSnapshot(_ snapshot: FrameEditSnapshot, to frame: ScanFrame) {
        guard ownsFrame(frame) else { return }
        let current = frameEditSnapshot(frame)
        registerFrameEditUndo(frame, snapshot: current)

        isApplyingFrameEditHistory = true
        defer { isApplyingFrameEditHistory = false }
        frameEditCoalesceTasks[frame.id]?.cancel()
        frameEditCoalesceTasks[frame.id] = nil

        frame.filmType = snapshot.filmType
        frame.preset = snapshot.presetID.flatMap { id in presets.first(where: { $0.id == id }) }
        frame.params = snapshot.params
        let transformChanged = current.imageTransform != snapshot.imageTransform
        frame.imageTransform = snapshot.imageTransform
        frameEditBaselines[frame.id] = snapshot

        if transformChanged {
            applyTransformFast(frame)
        } else {
            requestDevelop(frame)
        }
        scheduleLibrarySave()
    }
}
