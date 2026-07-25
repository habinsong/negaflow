import SwiftUI
import AppKit
import Chromabase

struct DevelopInspectorTabLabel: View {
    let title: String
    let systemImages: [String]
    let isSelected: Bool
    @State private var hovered = false

    var body: some View {
        iconGroup
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 6)
            .background {
                if isSelected {
                    // 선택: 리퀴드 글라스.
                    Color.clear
                        .liquidSurface(cornerRadius: 15, interactive: true)
                } else if hovered {
                    // 호버: 은은한 음영(순정 hover 하이라이트).
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .onHover { hovered = $0 }
    }

    private var iconGroup: some View {
        HStack(spacing: 2) {
            ForEach(systemImages, id: \.self) { systemImage in
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
    }
}
