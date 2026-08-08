import SwiftUI
import AppKit
import Chromabase
import ScannerKit
import CoreImage
import UniformTypeIdentifiers

struct MainWindowChromeConfigurator: NSViewRepresentable {
    /// 창이 전체화면인지. 상단 탭바가 인라인 타이틀바 영역에 그려지므로 전체화면 여부에 따라
    /// 신호등 자리 예약과 AppKit 툴바 표시를 바꿔야 한다.
    @Binding var isFullScreen: Bool

    final class Coordinator {
        var observedWindow: NSWindow?
        var observers: [NSObjectProtocol] = []

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window, coordinator: context.coordinator)
        }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        observeFullScreenTransitions(of: window, coordinator: coordinator)
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unifiedCompact

        let toolbarIdentifier = NSToolbar.Identifier("negaflow.inlineTitlebar")
        if window.toolbar?.identifier != toolbarIdentifier {
            let toolbar = NSToolbar(identifier: toolbarIdentifier)
            toolbar.displayMode = .iconOnly
            toolbar.sizeMode = .small
            toolbar.showsBaselineSeparator = false
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            window.toolbar = toolbar
        }
        applyFullScreenChrome(to: window)
    }

    /// 전체화면에서는 비어 있는 인라인 툴바가 화면 상단을 차지해 우리 탭바를 덮어 버린다(빈 띠).
    /// 이 툴바는 창 모드에서 인라인 타이틀바 높이를 확보하려고만 두는 것이므로 전체화면에선 숨긴다.
    private func applyFullScreenChrome(to window: NSWindow) {
        let fullScreen = window.styleMask.contains(.fullScreen)
        window.toolbar?.isVisible = !fullScreen
        if isFullScreen != fullScreen { isFullScreen = fullScreen }
    }

    private func observeFullScreenTransitions(of window: NSWindow, coordinator: Coordinator) {
        guard coordinator.observedWindow !== window else { return }
        coordinator.observers.forEach(NotificationCenter.default.removeObserver)
        coordinator.observers = []
        coordinator.observedWindow = window

        for name in [NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification] {
            let observer = NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow else { return }
                MainActor.assumeIsolated { applyFullScreenChrome(to: window) }
            }
            coordinator.observers.append(observer)
        }
    }
}
