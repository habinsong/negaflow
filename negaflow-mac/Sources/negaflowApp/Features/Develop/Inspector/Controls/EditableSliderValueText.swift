import SwiftUI
import AppKit
import Chromabase

struct EditableSliderValueText: View {
    let value: Double
    let displayText: String
    let inputRange: ClosedRange<Double>
    var inputText: (Double) -> String = { sliderInputText($0) }
    var width: CGFloat = 54
    let onCommit: (Double) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isInvalid = false
    @State private var draftEdited = false
    @State private var syncingDraft = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField(text: $draft) {
                    EmptyView()
                }
                    .font(.caption2.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .foregroundStyle(isInvalid ? Color.red : Color.primary)
                    .frame(width: width, alignment: .trailing)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .focused($isFocused)
                    .onSubmit(commitDraft)
                    .onChange(of: draft) { oldValue, newValue in
                        isInvalid = false
                        if oldValue != newValue, !syncingDraft {
                            draftEdited = true
                        }
                    }
                    .onChange(of: value) { _, newValue in
                        if isEditing {
                            syncDraft(with: newValue)
                        }
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused, isEditing {
                            if draftEdited {
                                commitDraft(restoreFocusOnFailure: true)
                            } else {
                                cancelEditing()
                            }
                        }
                    }
            } else {
                Button(action: beginEditing) {
                    Text(displayText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: width, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func beginEditing() {
        syncDraft(with: value)
        isInvalid = false
        draftEdited = false
        isEditing = true
        DispatchQueue.main.async {
            isFocused = true
        }
    }

    private func commitDraft() {
        commitDraft(restoreFocusOnFailure: false)
    }

    private func commitDraft(restoreFocusOnFailure: Bool) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Self.parseNumber(text), inputRange.contains(parsed) else {
            isInvalid = true
            NSSound.beep()
            if restoreFocusOnFailure {
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
            return
        }
        onCommit(parsed)
        isInvalid = false
        draftEdited = false
        isEditing = false
        isFocused = false
    }

    private func cancelEditing() {
        isEditing = false
        isInvalid = false
        draftEdited = false
    }

    private func syncDraft(with value: Double) {
        syncingDraft = true
        draft = inputText(value)
        draftEdited = false
        DispatchQueue.main.async {
            syncingDraft = false
        }
    }

    private static func parseNumber(_ text: String) -> Double? {
        let pattern = #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$"#
        guard text.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }
        return Double(text)
    }
}
