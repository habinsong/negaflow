import AppKit
import SwiftUI

/// 좌/우·상/하 비교의 분할선. 끌어서 경계를 옮긴다.
///
/// 선 자체는 1px이라 잡기 어려우므로 투명한 손잡이 폭을 따로 두고, 가운데에 잡는 곳임을 알리는
/// 표식을 둔다. 위치는 이미지 기준 비율이라 확대/축소·창 크기와 무관하게 유지된다.
struct CanvasCompareDivider: View {
    static let minimumFraction: CGFloat = 0.02
    static let maximumFraction: CGFloat = 0.98
    private static let grabThickness: CGFloat = 18
    private static let adjustmentStep: CGFloat = 0.05

    let imageFrame: CGRect
    let orientation: CanvasCompareOrientation
    let accessibilityLabel: String
    @Binding var fraction: CGFloat
    /// 잡은 순간의 포인터와 선 사이 간격. 손잡이를 가장자리에서 잡아도 선이 포인터로
    /// 튀지 않고, 움직이지 않은 클릭은 선을 그대로 둔다.
    @State private var grabOffset: CGFloat?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(0.75))
                .frame(width: lineSize.width, height: lineSize.height)
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(.black.opacity(0.25))
                }
                .frame(width: handleSize.width, height: handleSize.height)
        }
        .frame(width: grabSize.width, height: grabSize.height)
        .contentShape(Rectangle())
        .overlay { CanvasCursorRect(cursor: cursor) }
        .position(position)
        .gesture(dragGesture)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(verbatim: "\(Int((fraction * 100).rounded()))%"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setFraction(fraction + Self.adjustmentStep)
            case .decrement: setFraction(fraction - Self.adjustmentStep)
            @unknown default: break
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                let pointer = orientation == .vertical ? value.location.x : value.location.y
                // 이동량이 0인 첫 이벤트에서 간격을 다시 잰다. 드래그가 취소되어 onEnded 를
                // 놓쳐도 남은 간격이 다음 드래그의 시작을 밀어내지 않는다.
                let measured = pointer - linePosition
                let offset = value.translation == .zero ? measured : (grabOffset ?? measured)
                grabOffset = offset
                setFraction((pointer - offset - axisOrigin) / axisLength)
            }
            .onEnded { _ in grabOffset = nil }
    }

    private var axisOrigin: CGFloat {
        orientation == .vertical ? imageFrame.minX : imageFrame.minY
    }

    private var axisLength: CGFloat {
        max(orientation == .vertical ? imageFrame.width : imageFrame.height, 1)
    }

    private var linePosition: CGFloat {
        axisOrigin + axisLength * fraction
    }

    private func setFraction(_ value: CGFloat) {
        guard value.isFinite else { return }
        fraction = min(max(value, Self.minimumFraction), Self.maximumFraction)
    }

    private var position: CGPoint {
        switch orientation {
        case .vertical: return CGPoint(x: linePosition, y: imageFrame.midY)
        case .horizontal: return CGPoint(x: imageFrame.midX, y: linePosition)
        }
    }

    private var lineSize: CGSize {
        switch orientation {
        case .vertical: return CGSize(width: 1, height: imageFrame.height)
        case .horizontal: return CGSize(width: imageFrame.width, height: 1)
        }
    }

    private var grabSize: CGSize {
        switch orientation {
        case .vertical: return CGSize(width: Self.grabThickness, height: imageFrame.height)
        case .horizontal: return CGSize(width: imageFrame.width, height: Self.grabThickness)
        }
    }

    private var handleSize: CGSize {
        switch orientation {
        case .vertical: return CGSize(width: 4, height: 34)
        case .horizontal: return CGSize(width: 34, height: 4)
        }
    }

    private var cursor: NSCursor {
        switch orientation {
        case .vertical: return .resizeLeftRight
        case .horizontal: return .resizeUpDown
        }
    }
}

/// 커서 모양을 AppKit 의 cursor rect 에 맡긴다.
///
/// `onHover` + `NSCursor.push()/pop()` 는 hover 종료를 한 번이라도 놓치면 — 끌던 중 선이
/// 포인터를 앞질러 뷰가 다시 만들어지거나 창이 비활성화될 때 — 눌린 커서가 스택에 남아
/// 리사이즈 모양(`< | >`)으로 굳는다. cursor rect 는 포인터가 사각형을 벗어나는 순간
/// AppKit 이 스스로 되돌리므로 남을 상태가 없다.
private struct CanvasCursorRect: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> NSView { CursorRectView(cursor: cursor) }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CursorRectView, view.cursor !== cursor else { return }
        view.cursor = cursor
        view.window?.invalidateCursorRects(for: view)
    }

    private final class CursorRectView: NSView {
        var cursor: NSCursor

        init(cursor: NSCursor) {
            self.cursor = cursor
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { return nil }

        // 커서만 담당하는 뷰다. 마우스 이벤트는 아래의 SwiftUI 제스처가 그대로 받아야 한다.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override var frame: NSRect {
            didSet {
                guard frame != oldValue else { return }
                window?.invalidateCursorRects(for: self)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: cursor)
        }
    }
}
