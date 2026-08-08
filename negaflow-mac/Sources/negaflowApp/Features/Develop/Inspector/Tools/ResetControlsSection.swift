import SwiftUI
import Chromabase

struct ResetControlsSection: View {
    @EnvironmentObject private var model: AppModel
    let canResetPhotoAngle: Bool
    let onResetAllAdjustments: () -> Void
    let onResetPhotoAngle: () -> Void

    var body: some View {
        InspectorCard {
            InspectorCardHeader(title: model.text(AppLocalizedPhrase.reset), systemImage: "arrow.counterclockwise.circle")
            VStack(spacing: 8) {
                Button(role: .destructive, action: onResetAllAdjustments) {
                    Label(model.text(.commandResetAdjustments), systemImage: "slider.horizontal.3")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .help(model.text(AppLocalizedPhrase.resetAdjustmentsHelp))

                Button(action: onResetPhotoAngle) {
                    Label(model.text(AppLocalizedPhrase.resetPhotoAngle), systemImage: "crop.rotate")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .disabled(!canResetPhotoAngle)
                .help(model.text(AppLocalizedPhrase.resetPhotoAngle))
            }
        }
    }
}

struct ToolDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.38))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 2)
    }
}
