import SwiftUI
import AppKit
import CoreImage
import Chromabase

struct BrushControlBar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var thickness: CGFloat
    let hasStrokes: Bool
    let hasAppliedDefects: Bool
    let isBusy: Bool
    let onApply: () -> Void
    let onUndo: () -> Void
    let onClear: () -> Void
    let onResetAll: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "paintbrush.pointed.fill").foregroundStyle(.red)
            HStack(spacing: 6) {
                Image(systemName: "lineweight").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $thickness, in: 0.004...0.06).frame(width: 110)
            }
            Divider().frame(height: 16)
            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                .help(model.text(AppLocalizedPhrase.undoLastStroke)).disabled(!hasStrokes || isBusy)
            Button(action: onClear) { Image(systemName: "trash") }
                .help(model.text(AppLocalizedPhrase.clearPaintedStrokes)).disabled(!hasStrokes || isBusy)
            Button(action: onResetAll) { Image(systemName: "eraser.fill") }
                .help(model.text(AppLocalizedPhrase.resetAppliedDefects)).disabled(!hasAppliedDefects || isBusy)
            Button(action: onApply) {
                if isBusy { ProgressView().controlSize(.small) }
                else { Label(model.text(AppLocalizedPhrase.removeDefects), systemImage: "wand.and.stars") }
            }
            .buttonStyle(.borderedProminent).disabled(!hasStrokes || isBusy)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .adaptiveCapsuleSurface(.ultraThin)
    }
}
