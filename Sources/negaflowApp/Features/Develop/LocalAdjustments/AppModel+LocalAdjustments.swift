import Foundation
import Chromabase

extension AppModel {
    func addLocalAdjustment(_ adjustment: LocalDodgeBurnAdjustment, to frame: ScanFrame) {
        replaceLocalAdjustments(
            frame.params.localDodgeBurn + [adjustment],
            on: frame,
            actionName: LocalAdjustmentLocalizedText.add.resolved(language: appLanguage)
        )
    }

    func updateLocalAdjustment(
        id: UUID,
        on frame: ScanFrame,
        recordsUndo: Bool = true,
        _ update: (inout LocalDodgeBurnAdjustment) -> Void
    ) {
        var adjustments = frame.params.localDodgeBurn
        guard let index = adjustments.firstIndex(where: { $0.id == id }) else { return }
        update(&adjustments[index])
        replaceLocalAdjustments(
            adjustments,
            on: frame,
            actionName: LocalAdjustmentLocalizedText.edit.resolved(language: appLanguage),
            recordsUndo: recordsUndo
        )
    }

    func removeLocalAdjustment(id: UUID, from frame: ScanFrame) {
        let adjustments = frame.params.localDodgeBurn.filter { $0.id != id }
        guard adjustments.count != frame.params.localDodgeBurn.count else { return }
        replaceLocalAdjustments(
            adjustments,
            on: frame,
            actionName: LocalAdjustmentLocalizedText.delete.resolved(language: appLanguage)
        )
    }

    func registerLocalAdjustmentUndo(
        from previous: [LocalDodgeBurnAdjustment],
        on frame: ScanFrame
    ) {
        guard previous != frame.params.localDodgeBurn else { return }
        registerLocalAdjustmentUndo(
            previous,
            on: frame,
            actionName: LocalAdjustmentLocalizedText.edit.resolved(language: appLanguage)
        )
    }

    private func replaceLocalAdjustments(
        _ adjustments: [LocalDodgeBurnAdjustment],
        on frame: ScanFrame,
        actionName: String,
        recordsUndo: Bool = true
    ) {
        guard ownsFrame(frame), adjustments != frame.params.localDodgeBurn else { return }
        let previous = frame.params.localDodgeBurn
        frame.updateParams { $0.localDodgeBurn = adjustments }
        requestDevelop(frame)
        if recordsUndo {
            registerLocalAdjustmentUndo(previous, on: frame, actionName: actionName)
        }
    }

    private func registerLocalAdjustmentUndo(
        _ adjustments: [LocalDodgeBurnAdjustment],
        on frame: ScanFrame,
        actionName: String
    ) {
        guard let undoManager = catalogUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.replaceLocalAdjustments(adjustments, on: frame, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }
}
