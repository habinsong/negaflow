import SwiftUI
import AppKit
import Chromabase

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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                headerTitle
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                headerTitle
            }
        }
    }

    private var headerTitle: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
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
                .lineLimit(1)
            Spacer(minLength: 12)
            control
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, minHeight: 26)
    }
}

struct WorkflowSection<Content: View>: View {
    @EnvironmentObject private var model: AppModel
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
                    .help(model.text(AppLocalizedPhrase.resetSectionFormat, title))
                    .accessibilityLabel(model.text(AppLocalizedPhrase.resetSectionFormat, title))
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
