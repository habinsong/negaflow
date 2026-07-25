import SwiftUI
import AppKit

/// 크기 조절 손잡이가 붙는 쪽 — 좌측 패널은 오른쪽 모서리, 우측 패널은 왼쪽 모서리를 잡는다.
enum WorkspacePanelResizeEdge {
    case trailing
    case leading
}

/// 폭을 사용자가 끌어서 조절하는 워크스페이스 패널.
///
/// HSplitView 는 분할 위치를 자기 내부 상태로 들고 있어서, 뷰를 갈아 끼우면(모듈 전환) 값이
/// 되돌아가고 저장한 폭을 다시 적용하기도 어렵다. 여기서는 폭을 호출측이 소유하는 저장값
/// (@AppStorage) 하나로 두고 그 값을 그대로 프레임에 적용한다 — 화면을 오가도, 앱을 껐다 켜도
/// 같은 폭이 유지된다. 저장값은 원본 그대로 두고 표시할 때만 현재 창에 맞게 clamp 한다(창을
/// 좁혔다가 다시 넓히면 원래 폭으로 돌아온다).
struct WorkspaceResizablePanel<Content: View>: View {
    @Binding var storedWidth: Double
    let range: ClosedRange<CGFloat>
    let edge: WorkspacePanelResizeEdge
    @ViewBuilder var content: Content

    /// 드래그 시작 시점의 폭. 손잡이가 폭을 따라 움직여도 기준이 흔들리지 않게 고정해 둔다.
    @State private var dragBaseWidth: CGFloat?
    /// 드래그 중에만 쓰는 폭. 끝날 때 한 번만 저장값에 반영한다 — 매 틱 UserDefaults 를 쓰면
    /// 상위 뷰가 통째로 다시 그려져 끌기가 무거워진다.
    @State private var dragWidth: CGFloat?
    @State private var isHoveringHandle = false

    private func clamped(_ width: CGFloat) -> CGFloat {
        min(max(width, range.lowerBound), range.upperBound)
    }

    private var displayWidth: CGFloat {
        clamped(dragWidth ?? CGFloat(storedWidth))
    }

    var body: some View {
        content
            .frame(width: displayWidth)
            .overlay(alignment: edge == .trailing ? .trailing : .leading) {
                handle
            }
            // 폭 변경에는 애니메이션을 붙이지 않는다 — 바깥에서 걸린 애니메이션이 끌기에 섞이면
            // 목표 폭을 뒤늦게 쫓아가며 좌우로 흔들린다.
            .animation(nil, value: displayWidth)
    }

    private var handle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                guard hovering != isHoveringHandle else { return }
                isHoveringHandle = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                // 좌표계는 반드시 전역이어야 한다. 기본(.local)은 손잡이 자신을 기준으로 재는데,
                // 손잡이는 폭을 따라 같이 움직이므로 이동량이 매 틱 다시 계산되며 폭이 좌우로
                // 진동한다(끌 때 떨리던 원인).
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = dragBaseWidth ?? displayWidth
                        if dragBaseWidth == nil { dragBaseWidth = base }
                        let translation = edge == .trailing
                            ? value.translation.width
                            : -value.translation.width
                        dragWidth = clamped(base + translation)
                    }
                    .onEnded { _ in
                        if let dragWidth { storedWidth = Double(dragWidth) }
                        dragBaseWidth = nil
                        dragWidth = nil
                    }
            )
            .accessibilityHidden(true)
    }
}
