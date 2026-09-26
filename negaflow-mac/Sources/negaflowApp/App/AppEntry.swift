import AppKit
import SwiftUI

@MainActor
final class NegaflowApplicationDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private var hasPendingTerminationReply = false

    override init() {
        model = AppModelFactory.make()
        super.init()
    }

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        TextEntryKeyRouter.install()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !hasPendingTerminationReply else { return .terminateLater }
        hasPendingTerminationReply = true
        let decision = model.beginApplicationTermination { [weak self] shouldTerminate in
            guard let self, self.hasPendingTerminationReply else { return }
            self.hasPendingTerminationReply = false
            if !shouldTerminate {
                self.model.isRelaunchRequested = false
                self.model.isLibraryReinstallPendingRelaunch = false
                self.model.reportError(self.model.libraryCatalogBlockMessage(.writeFailed))
            }
            sender.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        switch decision {
        case .terminateNow:
            hasPendingTerminationReply = false
            return .terminateNow
        case .terminateLater:
            return .terminateLater
        case .terminateCancel:
            hasPendingTerminationReply = false
            model.isRelaunchRequested = false
            model.isLibraryReinstallPendingRelaunch = false
            model.reportError(model.libraryCatalogBlockMessage(.writeFailed))
            return .terminateCancel
        }
    }

    /// 종료가 승인된 뒤에만 불린다. 재실행 요청은 여기서 실행해야 종료가 취소됐을 때 앱이
    /// 뒤늦게 다시 열리지 않는다.
    func applicationWillTerminate(_ notification: Notification) {
        guard model.isRelaunchRequested else { return }
        try? AppRelauncher.relaunchAfterExit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct negaflowApp: App {
    @NSApplicationDelegateAdaptor(NegaflowApplicationDelegate.self)
    private var applicationDelegate
    @StateObject private var localAdjustmentSession = LocalAdjustmentSession()

    private var model: AppModel { applicationDelegate.model }

    var body: some Scene {
        Window("negaflow", id: "main") {
            AppearanceSceneRoot(model: model) {
                ContentView()
                    .frame(minWidth: 900, minHeight: 640)
                    .environmentObject(model)
                    .environmentObject(localAdjustmentSession)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppMenuCommands(model: model)
        }

        Window(model.text(.commandAboutNegaflow), id: AboutNegaflowView.windowID) {
            AppearanceSceneRoot(model: model) {
                AboutNegaflowView(model: model)
            }
        }
        .windowResizability(.contentSize)

        Settings {
            AppearanceSceneRoot(model: model) {
                AppSettingsView()
                    .environmentObject(model)
            }
        }

        Window(model.text(.commandNegaflowHelp), id: QuickStartHelpScene.windowID) {
            AppearanceSceneRoot(model: model) {
                QuickStartHelpView()
                    .environmentObject(model)
            }
        }
        .defaultSize(width: 680, height: 560)
    }
}

@MainActor
private struct AppearanceSceneRoot<Content: View>: View {
    @ObservedObject var model: AppModel
    let content: Content

    init(model: AppModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    var body: some View {
        content.preferredColorScheme(model.appearanceMode.colorScheme)
    }
}
