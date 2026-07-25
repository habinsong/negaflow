import SwiftUI
import AppKit
import Chromabase

struct ResettableSlider: View {
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let resetValue: Double?

    init(value: Binding<Double>, in range: ClosedRange<Double>, resetValue: Double? = 0) {
        self.value = value
        self.range = range
        self.resetValue = resetValue
    }

    var body: some View {
        Slider(value: value, in: range)
            .overlay {
                if let resetValue {
                    DoubleClickResetOverlay {
                        value.wrappedValue = resetValue
                    }
                }
            }
    }
}
private struct DoubleClickResetOverlay: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DoubleClickResetNSView {
        let view = DoubleClickResetNSView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DoubleClickResetNSView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}

private final class DoubleClickResetNSView: NSView {
    var onDoubleClick: () -> Void = {}
    private var monitor: Any?
    private let hitOutset: CGFloat = 8

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard
                    let self,
                    let window = self.window,
                    event.window === window,
                    event.clickCount == 2
                else {
                    return event
                }

                let location = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.insetBy(dx: -hitOutset, dy: -hitOutset).contains(location) else {
                    return event
                }

                self.onDoubleClick()
                return nil
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
