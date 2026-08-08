import SwiftUI
import AppKit
import Chromabase

struct RollToolbarStrip: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var frame: ScanFrame

    var body: some View {
        HStack(spacing: 8) {
            Label(frame.compactDisplayName(language: model.appLanguage), systemImage: "film.stack")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)

            if selectedFrames.count > 1 {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(selectedFrames.count, format: .number)
                }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }

            Divider().frame(height: 16)

            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        let nextValue = selectedFrames.allSatisfy { $0.rating == value } ? 0 : value
                        selectedFrames.forEach { $0.setRating(nextValue) }
                    } label: {
                        Image(systemName: value <= frame.rating ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundStyle(value <= frame.rating ? Color.blue : Color.secondary.opacity(0.45))
                            .frame(width: 16, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(model.text(AppLocalizedPhrase.starHelpFormat, value))
                    .accessibilityLabel(model.text(AppLocalizedPhrase.starHelpFormat, value))
                    .accessibilitySelectionState(
                        selectedFrames.allSatisfy { $0.rating == value },
                        selectedValue: model.accessibilityText(.selected),
                        unselectedValue: model.accessibilityText(.notSelected),
                        unselectedHint: model.accessibilityText(.select)
                    )
                }
            }

            Button {
                let nextState: FramePickState = selectedFrames.allSatisfy { $0.pickState == .picked } ? .unflagged : .picked
                selectedFrames.forEach { $0.pickState = nextState }
            } label: {
                Image(systemName: frame.pickState == .picked ? "flag.fill" : "flag")
                    .foregroundStyle(frame.pickState == .picked ? Color.green : Color.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(frame.pickState == .picked ? model.text(AppLocalizedPhrase.clearPick) : model.text(AppLocalizedPhrase.picked))
            .accessibilityLabel(model.text(AppLocalizedPhrase.picked))
            .accessibilitySelectionState(
                selectedFrames.allSatisfy { $0.pickState == .picked },
                selectedValue: model.accessibilityText(.selected),
                unselectedValue: model.accessibilityText(.notSelected),
                selectedHint: model.text(AppLocalizedPhrase.clearPick),
                unselectedHint: model.accessibilityText(.select)
            )

            Button {
                let nextState: FramePickState = selectedFrames.allSatisfy { $0.pickState == .rejected } ? .unflagged : .rejected
                selectedFrames.forEach { $0.pickState = nextState }
            } label: {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(frame.pickState == .rejected ? Color.red : Color.secondary.opacity(0.5))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(frame.pickState == .rejected ? model.text(AppLocalizedPhrase.clearReject) : model.text(AppLocalizedPhrase.rejected))
            .accessibilityLabel(model.text(AppLocalizedPhrase.rejected))
            .accessibilitySelectionState(
                selectedFrames.allSatisfy { $0.pickState == .rejected },
                selectedValue: model.accessibilityText(.selected),
                unselectedValue: model.accessibilityText(.notSelected),
                selectedHint: model.text(AppLocalizedPhrase.clearReject),
                unselectedHint: model.accessibilityText(.select)
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .frame(maxWidth: 420)
    }

    private var selectedFrames: [ScanFrame] {
        model.actionableSelectedFrames.isEmpty ? [frame] : model.actionableSelectedFrames
    }
}
