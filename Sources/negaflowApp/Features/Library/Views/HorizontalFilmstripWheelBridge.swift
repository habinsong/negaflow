import AppKit
import SwiftUI

/// 필름스트립 위에서 일반 마우스 휠의 세로 델타를 가로 이동으로 바꾼다.
/// 트랙패드의 이미 가로인 델타와 modifier 조합은 시스템 기본 동작을 보존한다.
struct HorizontalFilmstripWheelBridge: NSViewRepresentable {
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isActive = isActive
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        /// 일반 마우스 휠 한 노치(라인 델타)를 픽셀 이동으로 환산하는 배율.
        static let wheelLineScrollMultiplier: CGFloat = 48

        var isActive = false
        weak var bridgeView: NSView?
        private var eventMonitor: Any?

        func attach(to view: NSView) {
            bridgeView = view
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { @MainActor [weak self] event in
                guard let self, self.isActive,
                      abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                      !event.modifierFlags.contains(.command),
                      !event.modifierFlags.contains(.option),
                      !event.modifierFlags.contains(.control),
                      let bridgeView = self.bridgeView,
                      event.window === bridgeView.window,
                      let scrollView = self.filmstripScrollView(for: event),
                      let documentView = scrollView.documentView
                else { return event }

                let clipView = scrollView.contentView
                let maximumX = max(0, documentView.bounds.width - clipView.bounds.width)
                guard maximumX > 0 else { return event }
                // 트랙패드/매직마우스는 정밀 델타(픽셀)라 1:1로 쓴다. 일반 마우스 휠은
                // 라인 단위의 작은 델타라 그대로 쓰면 한 노치에 몇 px만 움직인다 →
                // 노치당 체감 이동이 나오도록 배율을 곱한다.
                let delta = event.hasPreciseScrollingDeltas
                    ? event.scrollingDeltaY
                    : event.scrollingDeltaY * Self.wheelLineScrollMultiplier
                let nextX = min(max(0, clipView.bounds.origin.x - delta), maximumX)
                clipView.scroll(to: NSPoint(x: nextX, y: clipView.bounds.origin.y))
                scrollView.reflectScrolledClipView(clipView)
                return nil
            }
        }

        func detach() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            bridgeView = nil
        }

        /// 필름스트립의 가로 `NSScrollView`를 찾는다.
        /// 브리지 NSView는 스크롤뷰의 `.background`로 설치되므로 같은 컨테이너의
        /// 형제로 존재한다. 좌표/hit-test에 의존하지 않고 뷰 트리를 위로 올라가며
        /// 서브트리에서 가로 스크롤뷰를 찾는다(가장 가까운 것이 필름스트립).
        private func filmstripScrollView(for event: NSEvent) -> NSScrollView? {
            var ancestor: NSView? = bridgeView
            while let node = ancestor {
                if let found = Self.horizontalScrollView(in: node) { return found }
                ancestor = node.superview
            }
            // 예비 경로: 커서 위치 기준 hit-test(윈도우 좌표를 그대로 넘긴다).
            var hit = event.window?.contentView?.hitTest(event.locationInWindow)
            while let candidate = hit {
                if let scrollView = candidate as? NSScrollView { return scrollView }
                hit = candidate.superview
            }
            return nil
        }

        private static func horizontalScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView,
               let documentView = scrollView.documentView,
               documentView.bounds.width > scrollView.contentView.bounds.width {
                return scrollView
            }
            for subview in view.subviews {
                if let found = horizontalScrollView(in: subview) { return found }
            }
            return nil
        }
    }
}
