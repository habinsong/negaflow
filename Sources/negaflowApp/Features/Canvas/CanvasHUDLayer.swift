import SwiftUI
import Chromabase

struct CanvasHUDLayer: View {
    let brushMode: Bool

    @Binding var brushThickness: CGFloat
    let hasBrushStrokes: Bool
    let hasAppliedDefects: Bool
    let isRemovingDefects: Bool

    let onApplyBrush: () -> Void
    let onUndoBrush: () -> Void
    let onClearBrushDraft: () -> Void
    let onResetBrushes: () -> Void

    var body: some View {
        VStack {
            if brushMode {
                HStack {
                    Spacer()
                    BrushControlBar(
                        thickness: $brushThickness,
                        hasStrokes: hasBrushStrokes,
                        hasAppliedDefects: hasAppliedDefects,
                        isBusy: isRemovingDefects,
                        onApply: onApplyBrush,
                        onUndo: onUndoBrush,
                        onClear: onClearBrushDraft,
                        onResetAll: onResetBrushes
                    )
                    Spacer()
                }
                .padding(.top, 12)
            }
            Spacer()
        }
    }
}
