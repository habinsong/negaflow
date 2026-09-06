import AppKit
import SwiftUI
import Chromabase

/// 편집 중에도 한 자리 문법을 적용합니다. 잘못된 입력은 직전 draft로 되돌립니다.
struct InputGammaTextEditor: View {
    let original: String
    let help: String
    let commit: (InputGammaInterpretation) -> Void
    let cancel: () -> Void
    @State private var draft = ""
    @State private var invalid = false
    @State private var completed = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(text: $draft) { EmptyView() }
            .font(.caption.monospacedDigit())
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.plain)
            .foregroundStyle(invalid ? Color.red : Color.primary)
            .focused($focused)
            .accessibilityLabel(help)
            .help(help)
            .onAppear {
                draft = original
                DispatchQueue.main.async { focused = true }
            }
            .onChange(of: draft) { previous, value in
                guard InputGammaValueInput.accepts(value) else {
                    draft = previous
                    NSSound.beep()
                    return
                }
                invalid = false
            }
            .onSubmit {
                guard InputGammaValueInput.accepts(draft),
                      let gamma = InputGammaValueInput.value(draft) else {
                    invalid = true
                    NSSound.beep()
                    return
                }
                completed = true
                commit(gamma)
            }
            .onExitCommand { completed = true; cancel() }
            .onChange(of: focused) { _, value in
                if !value && !completed { completed = true; cancel() }
            }
    }

}
