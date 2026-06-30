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
                    title: "Copy",
                    systemName: "doc.on.doc",
                    help: "현재 프레임 현상 설정 복사"
                ) {
                    model.copyDevelopSettings(from: frame)
                }
                TransferButton(
                    title: "Paste",
                    systemName: "clipboard",
                    help: "복사한 현상 설정 붙여넣기",
                    isDisabled: isPasteDisabled
                ) {
                    model.pasteDevelopSettings(to: frame, scope: pasteScope)
                }
            }

            LabeledContent("Paste Scope") {
                Menu {
                    Button {
                        pasteScope = .all
                    } label: {
                        Label("All Settings", systemImage: pasteScope.isFullDevelopScope ? "checkmark" : "circle")
                    }
                    Divider()
                    Toggle("Base", isOn: scopeBinding(\.base))
                    Toggle("Tone", isOn: scopeBinding(\.tone))
                    Toggle("Color", isOn: scopeBinding(\.color))
                    Toggle("Detail", isOn: scopeBinding(\.detail))
                } label: {
                    Text(pasteScope.displayName)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("붙여넣을 현상 설정 범위 선택")
            }
        } header: {
            sectionHeader("Copy / Paste", systemImage: "doc.on.doc")
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
