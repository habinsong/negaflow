import SwiftUI

/// 설정창은 순정 `Form(.grouped)`을 쓴다. 시스템 설정과 같은 그룹 여백·라벨 정렬·행 높이를
/// 공짜로 얻고, 라벨 폭을 하드코딩하지 않으므로 언어가 바뀌어도 오와열이 깨지지 않는다.
struct AppSettingsPane<Content: View>: View {
    let accessibilityIdentifier: String
    let content: Content

    init(
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .adaptivePanelSurface(.regular)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct AppSettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            Text(title)
        }
    }
}

/// 라벨 + 컨트롤 한 행. `LabeledContent`가 macOS 라벨 정렬 기준선을 그대로 따른다.
struct AppSettingsRow<Control: View>: View {
    let label: String
    let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        LabeledContent {
            control
        } label: {
            Text(label)
        }
    }
}

struct AppSettingsToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var isDisabled = false

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .disabled(isDisabled)
    }
}

struct AppSettingsValueRow: View {
    let label: String
    let value: String
    var supported = true
    var reason: String?

    var body: some View {
        AppSettingsRow(label) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .foregroundStyle(supported ? .primary : .secondary)
                    .multilineTextAlignment(.trailing)
                if !supported, let reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

/// 행 아래 붙는 보조 설명. 들여쓰기를 라벨 폭에 맞춰 하드코딩하지 않는다 —
/// 라벨이 길어지는 언어에서 곧바로 오와열이 어긋나기 때문이다.
struct AppSettingsHelpText: View {
    let text: String
    var color: Color = .secondary

    init(_ text: String) {
        self.text = text
    }

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 라벨 + 수치는 윗줄, 슬라이더는 아랫줄 전폭. 라벨 열 오른쪽에 슬라이더를 밀어 넣으면
/// 트랙이 짧아져 조작 정밀도가 떨어진다.
struct AppSettingsSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                Spacer(minLength: 8)
                Text(verbatim: valueText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            // `step:`을 주면 슬라이더가 눈금을 전부 그려 노이즈만 늘어난다. 값만 스텝에 맞춘다.
            Slider(value: steppedValue, in: range)
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

/// 값 표시 + 액션 버튼이 함께 있는 행에서 쓰는 경로/이름 텍스트.
struct AppSettingsPathText: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
