import SwiftUI

struct LibraryCullingFrameSurface: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var frame: ScanFrame
    let role: AppCullingText?
    let isActive: Bool
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            ZStack {
                Color.black.opacity(0.94)
                if let image = FrameStripPresentationMode.developed.previewImage(for: frame) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(10)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .topLeading) {
                if let role {
                    Text(model.cullingText(role))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .adaptiveRoundedSurface(cornerRadius: 6, material: .regular)
                        .padding(10)
                }
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 8) {
                    Text(verbatim: frame.compactDisplayName(language: model.appLanguage))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if frame.rating > 0 {
                        Label(frame.rating.formatted(), systemImage: "star.fill")
                    }
                    Image(systemName: frame.pickState.systemImage)
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(.black.opacity(0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isActive ? Color.accentColor : Color.white.opacity(0.16), lineWidth: isActive ? 2 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(frame.compactDisplayName(language: model.appLanguage))
        .accessibilitySelectionState(
            isActive,
            selectedValue: model.accessibilityText(.selected),
            unselectedValue: model.accessibilityText(.notSelected),
            unselectedHint: model.accessibilityText(.select)
        )
    }
}
