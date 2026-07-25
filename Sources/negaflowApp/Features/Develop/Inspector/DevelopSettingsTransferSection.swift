import SwiftUI
import Chromabase

struct DevelopSettingsTransferSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @State private var pasteScope = DevelopSettingsPasteScope.all

    var isPasteDisabled: Bool {
        model.copiedDevelopSettings == nil || pasteScope.isEmpty
    }

    var body: some View {
        Section {
            HStack(spacing: 8) {
                TransferButton(
                    title: model.text(AppLocalizedPhrase.copy),
                    systemName: "doc.on.doc",
                    help: model.text(AppLocalizedPhrase.copyDevelopSettingsHelp)
                ) {
                    model.copyDevelopSettings(from: frame)
                }
                TransferButton(
                    title: model.text(AppLocalizedPhrase.paste),
                    systemName: "clipboard",
                    help: model.text(AppLocalizedPhrase.pasteDevelopSettingsHelp),
                    isDisabled: isPasteDisabled
                ) {
                    model.pasteDevelopSettings(to: frame, scope: pasteScope)
                }
            }

            LabeledContent(model.text(AppLocalizedPhrase.pasteScope)) {
                Menu {
                    Button {
                        pasteScope = .all
                    } label: {
                        Label(model.text(AppLocalizedPhrase.allSettings), systemImage: pasteScope.isFullDevelopScope ? "checkmark" : "circle")
                    }
                    Divider()
                    Toggle(model.text(AppLocalizedPhrase.baseSection), isOn: scopeBinding(\.base))
                    Toggle(model.text(AppLocalizedPhrase.basicTone), isOn: scopeBinding(\.tone))
                    Toggle(model.text(AppLocalizedPhrase.color), isOn: scopeBinding(\.color))
                    Toggle(model.text(AppLocalizedPhrase.detailEffects), isOn: scopeBinding(\.detail))
                } label: {
                    Text(pasteScope.displayName(language: model.appLanguage))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(model.text(AppLocalizedPhrase.pasteScopeHelp))
            }
        } header: {
            sectionHeader(model.text(AppLocalizedPhrase.copyPaste), systemImage: "doc.on.doc")
        }
    }

    func scopeBinding(_ keyPath: WritableKeyPath<DevelopSettingsPasteScope, Bool>) -> Binding<Bool> {
        Binding(
            get: { pasteScope[keyPath: keyPath] },
            set: { pasteScope[keyPath: keyPath] = $0 }
        )
    }
}

/// 좌측탭 액션 버튼 공통 스타일 — 네이티브 bordered(평면, 그림자 없음), 풀폭.
struct TransferButton: View {
    let title: String
    let systemName: String
    let help: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isDisabled)
        .help(help)
        .accessibilityLabel(help)
    }
}
