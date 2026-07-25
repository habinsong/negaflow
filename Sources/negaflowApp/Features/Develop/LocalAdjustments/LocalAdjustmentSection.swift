import SwiftUI
import Chromabase

struct LocalAdjustmentSection: View {
    @ObservedObject var frame: ScanFrame
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: LocalAdjustmentSession
    @Binding var cropMode: Bool
    @Binding var brushMode: Bool
    @Binding var regionDefectMode: Bool
    @Binding var cloneStampMode: Bool
    @Binding var basePickerMode: Bool

    @State private var editBaseline: [LocalDodgeBurnAdjustment]?
    @State private var hoveredMode: LocalDodgeBurnMode?

    var body: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 9) {
                InspectorCardHeader(title: localized(.title), systemImage: "circle.lefthalf.striped.horizontal")
                maskPicker
                modePicker
                newMaskControls
                adjustmentList
            }
        }
        .onChange(of: frame.id) { _, _ in
            if session.activeFrameID != frame.id { session.deactivate() }
        }
    }

    private var maskPicker: some View {
        HStack(spacing: 5) {
            ForEach(LocalDodgeBurnMask.Kind.allCases, id: \.rawValue) { kind in
                Button {
                    toggleDrawing(kind)
                } label: {
                    Image(systemName: kind.systemImage)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            isDrawing(kind) ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .help(kind.localizedName(language: model.appLanguage))
                .accessibilityLabel(kind.localizedName(language: model.appLanguage))
                .accessibilitySelectionState(
                    isDrawing(kind),
                    selectedValue: model.accessibilityText(.selected),
                    unselectedValue: model.accessibilityText(.notSelected),
                    unselectedHint: model.accessibilityText(.select)
                )
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            modeButton(.dodge, title: localized(.dodge))
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)
            modeButton(.burn, title: localized(.burn))
        }
        .padding(2)
        .liquidSurface(cornerRadius: 16, interactive: true)
    }

    private func modeButton(_ mode: LocalDodgeBurnMode, title: String) -> some View {
        Button {
            session.mode = mode
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .padding(.horizontal, 6)
                .background(
                    modeBackground(mode),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .onHover { hoveredMode = $0 ? mode : nil }
        .accessibilitySelectionState(
            session.mode == mode,
            selectedValue: model.accessibilityText(.selected),
            unselectedValue: model.accessibilityText(.notSelected),
            unselectedHint: model.accessibilityText(.select)
        )
    }

    private func modeBackground(_ mode: LocalDodgeBurnMode) -> Color {
        if session.mode == mode { return Color.accentColor.opacity(0.18) }
        if hoveredMode == mode { return Color.primary.opacity(0.12) }
        return .clear
    }

    private var newMaskControls: some View {
        VStack(spacing: 6) {
            sliderRow(localized(.amount), value: $session.amount, range: 0...1)
            sliderRow(localized(.feather), value: $session.feather, range: 0...1)
            if session.maskKind == .brush {
                sliderRow(localized(.size), value: $session.brushThickness, range: 0.005...0.25)
            }
        }
    }

    @ViewBuilder
    private var adjustmentList: some View {
        if frame.params.localDodgeBurn.isEmpty {
            Text(localized(.empty))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Divider()
            ForEach(Array(frame.params.localDodgeBurn.enumerated()), id: \.element.id) { index, adjustment in
                adjustmentRow(index: index, adjustment: adjustment)
            }
        }
    }

    private func adjustmentRow(index: Int, adjustment: LocalDodgeBurnAdjustment) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Button {
                    session.selectedAdjustmentID = adjustment.id
                } label: {
                    Label(
                        "\(index + 1) · \(adjustment.mask.kind.localizedName(language: model.appLanguage))",
                        systemImage: adjustment.mask.kind.systemImage
                    )
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(session.selectedAdjustmentID == adjustment.id ? Color.accentColor : Color.primary)
                .accessibilitySelectionState(
                    session.selectedAdjustmentID == adjustment.id,
                    selectedValue: model.accessibilityText(.selected),
                    unselectedValue: model.accessibilityText(.notSelected),
                    unselectedHint: model.accessibilityText(.select)
                )
                Spacer()
                Button {
                    model.updateLocalAdjustment(id: adjustment.id, on: frame) { $0.isEnabled.toggle() }
                } label: {
                    Image(systemName: adjustment.isEnabled ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(localized(.visibility))
                .accessibilityLabel(localized(.visibility))
                .accessibilityToggleState(
                    adjustment.isEnabled,
                    onValue: model.accessibilityText(.on),
                    offValue: model.accessibilityText(.off),
                    onHint: model.accessibilityText(.turnOff),
                    offHint: model.accessibilityText(.turnOn)
                )
                Menu {
                    Button(localized(.copy)) { session.copy(adjustment) }
                    Button(localized(.paste), action: pasteAdjustment)
                        .disabled(session.copiedAdjustment == nil)
                    Divider()
                    Button(localized(.delete), role: .destructive) {
                        model.removeLocalAdjustment(id: adjustment.id, from: frame)
                        if session.selectedAdjustmentID == adjustment.id { session.selectedAdjustmentID = nil }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if session.selectedAdjustmentID == adjustment.id {
                selectedControls(adjustment)
            }
        }
    }

    private func selectedControls(_ adjustment: LocalDodgeBurnAdjustment) -> some View {
        VStack(spacing: 6) {
            sliderRow(
                localized(.amount),
                value: Binding(
                    get: { currentAdjustment(adjustment.id)?.amount ?? adjustment.amount },
                    set: { value in model.updateLocalAdjustment(id: adjustment.id, on: frame, recordsUndo: false) { $0.amount = value } }
                ),
                range: 0...1,
                onEditingChanged: captureEditBoundary
            )
            sliderRow(
                localized(.feather),
                value: Binding(
                    get: { currentAdjustment(adjustment.id)?.normalizedFeather ?? adjustment.normalizedFeather },
                    set: { value in model.updateLocalAdjustment(id: adjustment.id, on: frame, recordsUndo: false) { $0.setNormalizedFeather(value) } }
                ),
                range: 0...1,
                onEditingChanged: captureEditBoundary
            )
        }
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).frame(width: 52, alignment: .leading)
            Slider(value: value, in: range, onEditingChanged: onEditingChanged)
            Text(String(format: "%.0f", value.wrappedValue * 100))
                .font(.caption2.monospacedDigit())
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func isDrawing(_ kind: LocalDodgeBurnMask.Kind) -> Bool {
        session.isActive(for: frame) && session.maskKind == kind
    }

    private func toggleDrawing(_ kind: LocalDodgeBurnMask.Kind) {
        if isDrawing(kind) {
            session.deactivate()
        } else {
            cropMode = false
            brushMode = false
            regionDefectMode = false
            cloneStampMode = false
            basePickerMode = false
            session.maskKind = kind
            session.activate(for: frame)
            session.selectedAdjustmentID = nil
        }
    }

    private func pasteAdjustment() {
        guard let pasted = session.pastedAdjustment() else { return }
        model.addLocalAdjustment(pasted, to: frame)
        session.selectedAdjustmentID = pasted.id
    }

    private func captureEditBoundary(_ editing: Bool) {
        if editing {
            if editBaseline == nil { editBaseline = frame.params.localDodgeBurn }
        } else if let baseline = editBaseline {
            editBaseline = nil
            model.registerLocalAdjustmentUndo(from: baseline, on: frame)
        }
    }

    private func currentAdjustment(_ id: UUID) -> LocalDodgeBurnAdjustment? {
        frame.params.localDodgeBurn.first { $0.id == id }
    }

    private func localized(_ text: LocalAdjustmentLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}
