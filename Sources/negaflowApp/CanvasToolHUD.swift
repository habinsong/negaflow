import SwiftUI

struct CanvasToolHUD: View {
    let zoomText: String
    let cropMode: Bool
    let brushMode: Bool
    let regionICEMode: Bool
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onFit: () -> Void
    let onActualSize: () -> Void
    let onCrop: () -> Void
    let onBrush: () -> Void
    let onRegionICE: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            CanvasToolButton(systemName: "minus.magnifyingglass", help: "축소", action: onZoomOut)
            CanvasToolButton(systemName: "plus.magnifyingglass", help: "확대", action: onZoomIn)
            Button(action: onFit) {
                Text(zoomText)
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .frame(width: 46, height: 28)
            }
            .buttonStyle(.plain)
            .help("화면에 맞추기")
            CanvasToolButton(systemName: "1.magnifyingglass", help: "원본 크기", action: onActualSize)
            Divider().frame(height: 18).padding(.horizontal, 1)
            CanvasToolButton(systemName: "crop", help: "크롭", isActive: cropMode, action: onCrop)
            CanvasToolButton(systemName: "paintbrush.pointed.fill",
                             help: "결함 브러시 — 먼지/스크래치 위를 칠하면 그 안에서만 제거",
                             isActive: brushMode,
                             activeTint: .red,
                             action: onBrush)
            CanvasToolButton(systemName: "scope",
                             help: "영역 ICE — 영역을 드래그하면 결함을 자동 검출(빨강), 클릭 제외 후 제거",
                             isActive: regionICEMode,
                             activeTint: .red,
                             action: onRegionICE)
        }
        .padding(4)
        .liquidSurface(cornerRadius: 10, interactive: true)
    }
}

struct CanvasToolButton: View {
    let systemName: String
    let help: String
    var isActive: Bool = false
    var activeTint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(isActive ? .white : Color.primary)
                .background(isActive ? activeTint : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
