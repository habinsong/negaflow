import AppKit
import SwiftUI

/// 평상시에는 투명하고 호버·선택 중에만 음영이 생기는 전폭 선택 행.
struct PrintInspectorPopupPicker<Value: Hashable>: View {
    struct Option: Equatable {
        let value: Value
        let title: String

        init(_ value: Value, title: String) {
            self.value = value
            self.title = title
        }
    }

    @Binding var selection: Value
    let options: [Option]
    let accessibilityLabel: String
    var isEnabled = true
    var horizontalPadding: CGFloat = 10
    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.regular)
        .font(.callout)
        .frame(maxWidth: .infinity)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
    }

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? "—"
    }
}

/// 클릭하면 숫자 입력으로 전환된다. Enter는 확정하고 Esc는 draft를 버린다.
private struct PrintInspectorEditableNumber: View {
    let displayText: String
    let inputText: String
    let width: CGFloat
    let onCommit: (String) -> Bool

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isInvalid = false
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField(text: $draft) {
                    EmptyView()
                }
                .font(.callout.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .foregroundStyle(isInvalid ? Color.red : Color.primary)
                .frame(width: width, alignment: .trailing)
                .padding(.horizontal, 6)
                .frame(minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                )
                .focused($isFocused)
                .onSubmit(commitDraft)
                .onExitCommand(perform: cancelEditing)
                .onChange(of: draft) { _, _ in
                    isInvalid = false
                }
                .onChange(of: isFocused) { _, focused in
                    guard !focused, isEditing else { return }
                    commitDraft(restoreFocusOnFailure: true)
                }
            } else {
                Button(action: beginEditing) {
                    Text(verbatim: displayText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: width, alignment: .trailing)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { isHovered = $0 }
    }

    private func beginEditing() {
        draft = inputText
        isInvalid = false
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
        guard onCommit(text) else {
            isInvalid = true
            NSSound.beep()
            if restoreFocusOnFailure {
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
            return
        }
        isInvalid = false
        isEditing = false
        isFocused = false
    }

    private func cancelEditing() {
        isInvalid = false
        isEditing = false
        isFocused = false
    }
}

private struct PrintInspectorEditableInt: View {
    let value: Int
    let displayValue: Int
    let range: ClosedRange<Int>
    var width: CGFloat = 38
    let onCommit: (Int) -> Void

    var body: some View {
        let offset = displayValue - value
        PrintInspectorEditableNumber(
            displayText: "\(displayValue)",
            inputText: "\(displayValue)",
            width: width
        ) { text in
            guard text.range(of: #"^[+-]?\d+$"#, options: .regularExpression) != nil,
                  let parsed = Int(text) else {
                return false
            }
            let storedValue = parsed - offset
            guard range.contains(storedValue) else { return false }
            onCommit(storedValue)
            return true
        }
    }
}

private struct PrintInspectorEditableDouble: View {
    let value: Double
    let displayText: String
    let range: ClosedRange<Double>
    let step: Double
    let inputScale: Double
    let inputFractionDigits: Int
    var width: CGFloat = 68
    let onCommit: (Double) -> Void

    var body: some View {
        PrintInspectorEditableNumber(
            displayText: displayText,
            inputText: String(
                format: "%.*f",
                inputFractionDigits,
                value * inputScale
            ),
            width: width
        ) { text in
            let pattern = #"^[+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)$"#
            guard text.range(of: pattern, options: .regularExpression) != nil,
                  let parsed = Double(text.replacingOccurrences(of: ",", with: ".")),
                  inputScale != 0 else {
                return false
            }
            let rawValue = parsed / inputScale
            guard range.contains(rawValue) else { return false }
            let committed = step > 0 ? (rawValue / step).rounded() * step : rawValue
            onCommit(min(max(committed, range.lowerBound), range.upperBound))
            return true
        }
    }
}

/// 라벨 + 수치를 윗줄에, 슬라이더를 아랫줄 전폭에 두는 행.
/// 좁은 패널에서 한 줄에 밀어 넣으면 슬라이더 트랙이 먼저 짜부라진다.
struct PrintInspectorSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String
    var inputScale: Double = 1
    var inputFractionDigits: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
                Spacer(minLength: 8)
                PrintInspectorEditableDouble(
                    value: value,
                    displayText: valueText,
                    range: range,
                    step: step,
                    inputScale: inputScale,
                    inputFractionDigits: inputFractionDigits
                ) {
                    value = $0
                }
            }
            // `step:`을 주면 macOS 슬라이더가 눈금을 전부 그린다(0...50이면 점선 50개).
            // 노이즈만 늘어나므로 눈금 없이 두고 값만 스텝에 맞춰 떨어뜨린다.
            Slider(value: steppedValue, in: range)
                .controlSize(.regular)
                .accessibilityLabel(label)
                .accessibilityValue(Text(verbatim: valueText))
        }
        .frame(maxWidth: .infinity)
    }

    private var steppedValue: Binding<Double> {
        Binding(
            get: { value },
            set: { raw in
                guard step > 0 else {
                    value = raw
                    return
                }
                value = (raw / step).rounded() * step
            }
        )
    }
}

struct PrintInspectorStepperRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var displayedValue: Int?

    var body: some View {
        PrintInspectorStackedField(label) {
            HStack(spacing: 8) {
                PrintInspectorEditableInt(
                    value: value,
                    displayValue: displayedValue ?? value,
                    range: range
                ) {
                    value = $0
                }
                Spacer(minLength: 8)
                PrintInspectorStepButtons(
                    canDecrease: value > range.lowerBound,
                    canIncrease: value < range.upperBound,
                    decrease: { value -= 1 },
                    increase: { value += 1 }
                )
            }
        }
    }
}

/// 행/열처럼 짝을 이루는 수치 두 개. 두 칸이 같은 폭을 가져 좌우 무게가 같다.
struct PrintInspectorPairedSteppers: View {
    let leadingTitle: String
    @Binding var leadingValue: Int
    let trailingTitle: String
    @Binding var trailingValue: Int
    let range: ClosedRange<Int>

    var body: some View {
        PrintInspectorPairedInlineFields(
            leadingTitle: leadingTitle,
            leadingControl: {
                compactStepper(value: $leadingValue)
            },
            trailingTitle: trailingTitle,
            trailingControl: {
                compactStepper(value: $trailingValue)
            }
        )
    }

    private func compactStepper(value: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            PrintInspectorEditableInt(
                value: value.wrappedValue,
                displayValue: value.wrappedValue,
                range: range
            ) {
                value.wrappedValue = $0
            }
            Spacer(minLength: 2)
            PrintInspectorStepButtons(
                canDecrease: value.wrappedValue > range.lowerBound,
                canIncrease: value.wrappedValue < range.upperBound,
                decrease: { value.wrappedValue -= 1 },
                increase: { value.wrappedValue += 1 }
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PrintInspectorStepButtons: View {
    let canDecrease: Bool
    let canIncrease: Bool
    let decrease: () -> Void
    let increase: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: decrease) {
                Image(systemName: "minus")
                    .frame(width: 14)
            }
            .buttonStyle(
                PrintInspectorTransientButtonStyle(
                    horizontalPadding: 7,
                    minimumHeight: 30
                )
            )
            .disabled(!canDecrease)

            Button(action: increase) {
                Image(systemName: "plus")
                    .frame(width: 14)
            }
            .buttonStyle(
                PrintInspectorTransientButtonStyle(
                    horizontalPadding: 7,
                    minimumHeight: 30
                )
            )
            .disabled(!canIncrease)
        }
    }
}

struct PrintInspectorIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var role: ButtonRole?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.callout)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(
            PrintInspectorTransientButtonStyle(
                foregroundStyle: role == .destructive ? Color.red : Color.primary,
                minimumHeight: 30
            )
        )
        .frame(maxWidth: .infinity)
        .disabled(isDisabled)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// 카드 안에서 쓰는 접이식 그룹. 카드 안에 또 상자를 그리지 않고 제목 행 + 내용으로만 구분한다.
struct PrintInspectorDisclosure<Label: View, Content: View>: View {
    @Binding var isExpanded: Bool
    let accessibilityLabel: String
    let label: Label
    let content: Content

    init(
        isExpanded: Binding<Bool>,
        accessibilityLabel: String,
        @ViewBuilder label: () -> Label,
        @ViewBuilder content: () -> Content
    ) {
        _isExpanded = isExpanded
        self.accessibilityLabel = accessibilityLabel
        self.label = label()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PrintInspectorMetrics.verticalSpacing) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)
                    label
                    Spacer(minLength: 8)
                }
                .frame(minHeight: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(
                PrintInspectorTransientButtonStyle(
                    horizontalPadding: 6,
                    minimumHeight: 30
                )
            )
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                content
                    .padding(.leading, 17)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 인화 인스펙터 상단 탭. 스트립 하나만 유리로 띄우고 선택 상태는 fill로 표현한다.
struct PrintInspectorTabButton: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilitySelectionState(
            isSelected,
            selectedValue: model.accessibilityText(.selected),
            unselectedValue: model.accessibilityText(.notSelected),
            unselectedHint: model.accessibilityText(.select)
        )
    }

    /// 좌측 탭 레일(`PrintSidebarTabButton`)과 같은 선택 표현을 쓴다.
    private var backgroundFill: Color {
        if isSelected { return Color.accentColor.opacity(0.16) }
        return Color.primary.opacity(isHovered ? 0.08 : 0)
    }
}
