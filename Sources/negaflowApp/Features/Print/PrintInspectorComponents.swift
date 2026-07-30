import SwiftUI

enum PrintInspectorMetrics {
    /// 우측 컨트롤 열의 고정 폭. 모든 행이 같은 트레일링 경계를 공유해야 오와열이 맞는다.
    /// 컨트롤을 남는 폭 전체로 늘리면 패널이 넓어질수록 라벨과 컨트롤이 좌우로 갈라진다.
    static let controlWidth: CGFloat = 148
    static let labelMinimumWidth: CGFloat = 84
    static let horizontalSpacing: CGFloat = 10
    static let verticalSpacing: CGFloat = 10
    static let rowMinimumHeight: CGFloat = 30
}

/// 인화 인스펙터의 섹션 컨테이너. 현상 인스펙터와 같은 카드 언어를 공유한다.
struct PrintInspectorSection<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        InspectorCard {
            InspectorCardHeader(title: title, systemImage: systemImage)
            content
        }
    }
}

/// 라벨(좌) + 컨트롤(우) 행. 컨트롤은 고정 폭이라 섹션 안의 모든 행이 같은 열에 정렬된다.
struct PrintInspectorRow<Control: View>: View {
    let label: String
    let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PrintInspectorMetrics.horizontalSpacing) {
                rowLabel
                Spacer(minLength: PrintInspectorMetrics.horizontalSpacing)
                control
                    .frame(width: PrintInspectorMetrics.controlWidth, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 5) {
                rowLabel
                control
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, minHeight: PrintInspectorMetrics.rowMinimumHeight)
    }

    private var rowLabel: some View {
        Text(label)
            .font(.callout)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(AppTypography.minimumScaleFactor)
            .frame(minWidth: PrintInspectorMetrics.labelMinimumWidth, alignment: .leading)
    }
}

/// 현상 탭의 타깃 선택처럼 라벨 아래에 풀폭 컨트롤을 놓는 필드.
/// 선택지가 여러 개인 컨트롤을 우측 고정 열에 압축하지 않아 좌우 균형을 유지한다.
struct PrintInspectorStackedField<Control: View>: View {
    let label: String
    let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)
            control
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 라벨과 컨트롤을 같은 줄에 두는 인화 인스펙터 행.
struct PrintInspectorInlineField<Control: View>: View {
    let title: String
    let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)
            control
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 30)
    }
}

/// 서로 연관된 두 필드를 한 행에서 좌우 1:1로 나누는 인화 인스펙터 행.
struct PrintInspectorPairedInlineFields<LeadingControl: View, TrailingControl: View>: View {
    let leadingTitle: String
    let leadingControl: LeadingControl
    let trailingTitle: String
    let trailingControl: TrailingControl

    init(
        leadingTitle: String,
        @ViewBuilder leadingControl: () -> LeadingControl,
        trailingTitle: String,
        @ViewBuilder trailingControl: () -> TrailingControl
    ) {
        self.leadingTitle = leadingTitle
        self.leadingControl = leadingControl()
        self.trailingTitle = trailingTitle
        self.trailingControl = trailingControl()
    }

    var body: some View {
        HStack(spacing: 10) {
            PrintInspectorInlineField(leadingTitle) {
                leadingControl
            }

            Divider()
                .frame(height: 30)
                .opacity(0.45)

            PrintInspectorInlineField(trailingTitle) {
                trailingControl
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32)
    }
}

struct PrintInspectorTransientButtonStyle: ButtonStyle {
    var foregroundStyle = Color.primary
    var cornerRadius: CGFloat = 8
    var horizontalPadding: CGFloat = 10
    var minimumHeight: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        TransientButtonBody(
            configuration: configuration,
            foregroundStyle: foregroundStyle,
            cornerRadius: cornerRadius,
            horizontalPadding: horizontalPadding,
            minimumHeight: minimumHeight
        )
    }

    private struct TransientButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let foregroundStyle: Color
        let cornerRadius: CGFloat
        let horizontalPadding: CGFloat
        let minimumHeight: CGFloat
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.callout)
                .foregroundStyle(foregroundStyle)
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: minimumHeight)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            Color.primary.opacity(
                                configuration.isPressed ? 0.12 : (isHovered ? 0.08 : 0)
                            )
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .onHover { isHovered = $0 }
        }
    }
}

struct PrintInspectorTextField: View {
    let prompt: String
    @Binding var text: String
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(prompt, text: $text)
            .font(.callout)
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isFocused ? 0.10 : (isHovered ? 0.08 : 0)))
            )
            .focused($isFocused)
            .onHover { isHovered = $0 }
    }
}

struct PrintInspectorSegmentedPicker<Value: Hashable>: View {
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        SegmentedPicker(
            options: options,
            label: label,
            selection: $selection
        )
    }
}

struct PrintInspectorBooleanSegmentedField: View {
    @EnvironmentObject private var model: AppModel
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        PrintInspectorStackedField(label) {
            PrintInspectorSegmentedPicker(
                options: [false, true],
                label: { model.accessibilityText($0 ? .on : .off) },
                selection: $isOn
            )
        }
    }
}

/// 값만 보여주는 행. 편집 컨트롤이 없는 정보 행도 같은 열에 맞춘다.
struct PrintInspectorValueRow: View {
    let label: String
    let value: String

    var body: some View {
        PrintInspectorRow(label) {
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// 섹션 안의 보조 설명. 카드 폭 전체를 쓰고 들여쓰기를 하드코딩하지 않는다.
struct PrintInspectorHelpText: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.callout)
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
