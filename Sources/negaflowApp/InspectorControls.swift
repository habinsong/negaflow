import SwiftUI
import Chromabase

enum InspectorSliderFocus: Hashable {
    case exposure
    case contrast
    case highlight
    case shadow
    case whites
    case blacks
    case density
    case curveHighlights
    case curveLights
    case curveDarks
    case curveShadows
    case warmth
    case tint
    case vibrance
    case saturation
    case colorDepth
    case redPrimary
    case greenPrimary
    case bluePrimary
    case noiseReduction
    case grain
    case sharpness
    case clarity
    case halation
    case vignette
}

/// 우측 Develop 패널 공통 평면 카드 — 둥근 모서리 + 은은한 면, 그림자 없음.
/// 내부 컨트롤(특히 Slider)이 항상 좌우 풀폭이 되도록 Form 2단 레이아웃을 쓰지 않는다.
struct InspectorCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

/// 카드 헤더 — 아이콘 + 제목 + (선택) 우측 보조 텍스트.
struct InspectorCardHeader: View {
    let title: String
    let systemImage: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 라벨 좌측 + 컨트롤 우측 행. Slider 같은 풀폭 요소는 이 행을 쓰지 말고 직접 둘 것.
struct InspectorRow<Control: View>: View {
    let label: String
    let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            control
        }
        .frame(maxWidth: .infinity, minHeight: 26)
    }
}

struct WorkflowSection<Content: View>: View {
    let title: String
    let systemImage: String
    let isExpanded: Bool
    let toggle: () -> Void
    let reset: (() -> Void)?
    let contentDisabled: Bool
    let content: Content

    init(
        title: String,
        systemImage: String,
        isExpanded: Bool,
        toggle: @escaping () -> Void,
        reset: (() -> Void)? = nil,
        contentDisabled: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isExpanded = isExpanded
        self.toggle = toggle
        self.reset = reset
        self.contentDisabled = contentDisabled
        self.content = content()
    }

    var body: some View {
        InspectorCard {
            HStack(spacing: 8) {
                Button(action: toggle) {
                    HStack(spacing: 8) {
                        Image(systemName: systemImage)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let reset {
                    Button(action: reset) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(contentDisabled)
                    .help("\(title) 초기화")
                    .accessibilityLabel("\(title) 초기화")
                }
            }

            if isExpanded {
                content
                    .disabled(contentDisabled)
                    .opacity(contentDisabled ? 0.55 : 1)
            }
        }
    }
}

struct InspectorSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let focusID: InspectorSliderFocus?
    let focusedSlider: FocusState<InspectorSliderFocus?>.Binding?

    init(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        focusID: InspectorSliderFocus? = nil,
        focusedSlider: FocusState<InspectorSliderFocus?>.Binding? = nil
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.focusID = focusID
        self.focusedSlider = focusedSlider
    }

    @ViewBuilder
    var body: some View {
        if let focusID, let focusedSlider {
            sliderContent
                .focusable(true)
                .focused(focusedSlider, equals: focusID)
                .onTapGesture { focusedSlider.wrappedValue = focusID }
                .overlay {
                    if focusedSlider.wrappedValue == focusID {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                    }
                }
                .help("방향키로 0.01, Shift+방향키로 0.10 조정")
        } else {
            sliderContent
        }
    }

    private var sliderContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(signedControlText(value))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
        .padding(.vertical, focusID == nil ? 0 : 2)
        .padding(.horizontal, focusID == nil ? 0 : 4)
    }
}

func signedControlText(_ value: Double) -> String {
    abs(value) < 0.005 ? "0.00" : String(format: "%+.2f", value)
}
