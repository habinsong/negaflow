import SwiftUI

struct AppMetadataOverlayEditor: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var frame: ScanFrame
    @State private var draft = AppMetadataOverlayDraft()

    private var hasConflict: Bool {
        frame.appMetadataOverlay?.conflicts(with: frame.sourceMetadata) == true
    }

    var body: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 8) {
                InspectorCardHeader(title: localized(.title), systemImage: "square.and.pencil")
                TextField(localized(.fieldTitle), text: $draft.title)
                TextField(localized(.caption), text: $draft.caption)
                TextField(localized(.keywords), text: $draft.keywords)
                TextField(localized(.copyright), text: $draft.copyright)
                if hasConflict {
                    HStack(spacing: 6) {
                        Label(localized(.conflict), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(localized(.resolve)) {
                            if model.resolveAppMetadataOverlayConflict(for: frame) { loadDraft() }
                        }
                    }
                    .font(.caption)
                }
                HStack(spacing: 8) {
                    Button(localized(.save)) {
                        if model.applyAppMetadataOverlay(draft, to: [frame]) { loadDraft() }
                    }
                    if model.actionableSelectedFrames.count > 1 {
                        Button(localized(.applySelection)) {
                            if model.applyAppMetadataOverlay(
                                draft,
                                to: model.actionableSelectedFrames
                            ) { loadDraft() }
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .onAppear { loadDraft() }
        .onChange(of: frame.id) { _, _ in loadDraft() }
        .onChange(of: frame.appMetadataOverlay) { _, _ in loadDraft() }
    }

    private func loadDraft() {
        draft = AppMetadataOverlayDraft(frame.appMetadataOverlay)
    }

    private func localized(_ text: AppMetadataOverlayLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}
