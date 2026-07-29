import AppKit
import SwiftUI

/// 캔버스 위의 두 손가락 스크롤(과 마우스 휠)을 뷰포트 이동으로 넘긴다.
///
/// 드래그는 프레임 그리기·크롭·브러시·결함 도구가 먼저 가져가므로, 도구를 켜면 확대한 이미지를
/// 옮길 방법이 남지 않는다. 스크롤은 어느 도구와도 겹치지 않아 이동 전용 입력으로 쓸 수 있다.
struct CanvasScrollPanBridge: NSViewRepresentable {
    let onPan: (CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.onPan = onPan
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onPan = onPan
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        /// 라인 단위로 오는 일반 마우스 휠 델타를 픽셀 이동으로 환산하는 배율.
        static let wheelLineScrollMultiplier: CGFloat = 16

        var onPan: ((CGSize) -> Void)?
        private weak var bridgeView: NSView?
        private var eventMonitor: Any?

        func attach(to view: NSView) {
            bridgeView = view
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { @MainActor [weak self] event in
                guard let self,
                      let translation = self.panTranslation(for: event) else { return event }
                self.onPan?(translation)
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

        /// 캔버스 영역 안에서 발생한, 수식 키 없는 스크롤만 이동으로 해석한다.
        /// 그 밖의 이벤트는 시스템/다른 스크롤뷰 몫으로 그대로 흘려보낸다.
        private func panTranslation(for event: NSEvent) -> CGSize? {
            guard !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.control),
                  let view = bridgeView,
                  let window = view.window,
                  event.window === window,
                  view.bounds.contains(view.convert(event.locationInWindow, from: nil))
            else { return nil }
            let scale = event.hasPreciseScrollingDeltas ? 1 : Self.wheelLineScrollMultiplier
            let translation = CGSize(
                width: event.scrollingDeltaX * scale,
                height: event.scrollingDeltaY * scale
            )
            return translation == .zero ? nil : translation
        }
    }
}
