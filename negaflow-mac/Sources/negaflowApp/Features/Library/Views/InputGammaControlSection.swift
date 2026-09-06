import SwiftUI
import Chromabase

struct InputGammaControlSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @State private var editingText = false
    @State private var draft: Double?
    @State private var pending: InputGammaInterpretation?
    @State private var lastManual: Double?
    @State private var requestID = UUID()

    private var gamma: InputGammaInterpretation { pending ?? frame.params.inputGamma }
    private var manual: Bool { gamma != .automatic }
    private var canEdit: Bool {
        sourceEditable && !frame.isApplyingInputGamma && pending == nil
    }
    private var sourceEditable: Bool {
        frame.inputGammaSupportChecked && frame.inputGammaSourceError == nil && !frame.defectEditsNeedRestore
    }
    private var shownValue: Double {
        InputGammaValueInput.rounded(draft ?? gamma.value ?? frame.inputGammaSourceInfo?.manualSeed ?? 2.2)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(model.text(.inputGamma)).font(.caption)
                Spacer(minLength: 4)
                if frame.isApplyingInputGamma { ProgressView().controlSize(.mini) }
                if manual {
                    if editingText {
                        InputGammaTextEditor(
                            original: InputGammaValueInput.formatted(shownValue),
                            help: model.text(.inputGammaHelp),
                            commit: { editingText = false; apply($0) },
                            cancel: { editingText = false }
                        ).frame(width: 72, height: 20)
                    } else {
                        Button(InputGammaValueInput.formatted(shownValue)) { editingText = true }
                            .buttonStyle(.plain).font(.caption.monospacedDigit())
                            .accessibilityLabel(model.text(.inputGamma))
                            .accessibilityValue(InputGammaValueInput.formatted(shownValue))
                            .disabled(!canEdit)
                    }
                } else {
                    Text(automaticText).font(.caption.monospacedDigit())
                        .accessibilityLabel(model.text(.inputGamma))
                        .accessibilityValue(automaticText)
                        .accessibilityIdentifier("negaflow.input.gamma.automatic")
                }
            }
            SegmentedPicker(options: [false, true],
                label: { model.text($0 ? .baseModeManual : .baseModeAuto) },
                selection: Binding(get: { manual }, set: { chooseManual($0) }))
                .disabled(pending != nil || frame.isApplyingInputGamma || (!canEdit && !manual))
            if manual {
                CommitSlider(value: shownValue, range: InputGammaInterpretation.range,
                    step: InputGammaValueInput.step, resetValue: 2.2, ownerID: frame.id,
                    label: model.text(.inputGamma), snapsToStep: true,
                    onDraft: { draft = $0 }, onCommit: { value in
                        if let next = try? InputGammaInterpretation.power(InputGammaValueInput.rounded(value)) { apply(next) }
                    })
                    .frame(height: 20).disabled(!sourceEditable)
            }
        }
        .frame(maxWidth: .infinity)
        .transaction { $0.animation = nil }
        .task(id: frame.sourceLocationRevision) { await model.checkInputGammaSupport(for: frame) }
        .help(model.text(frame.inputGammaSourceError == nil ? .inputGammaHelp : .inputGammaUnsupported))
        .onChange(of: frame.params.inputGamma) { _, value in
            editingText = false
            if let value = value.value { lastManual = value }
        }
        .onDisappear { requestID = UUID(); editingText = false; draft = nil; pending = nil }
    }

    private var automaticText: String {
        frame.inputGammaSourceInfo?.automaticValue.map(InputGammaValueInput.formatted) ?? "—"
    }

    private func chooseManual(_ manual: Bool) {
        if !manual {
            lastManual = gamma.value
            apply(.automatic)
        } else if canEdit, let value = try? InputGammaInterpretation.power(
            InputGammaValueInput.rounded(lastManual ?? frame.inputGammaSourceInfo?.manualSeed ?? 2.2)) {
            apply(value)
        }
    }

    private func apply(_ value: InputGammaInterpretation) {
        guard model.actionableFrame === frame, gamma != value else { return }
        editingText = false
        pending = value
        let request = UUID()
        requestID = request
        Task {
            _ = await model.setInputGamma(value, for: frame)
            guard requestID == request else { return }
            pending = nil
            draft = nil
        }
    }
}
