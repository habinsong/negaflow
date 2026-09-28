import AppKit
import SwiftUI

@MainActor
final class NegaflowApplicationDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private var hasPendingTerminationReply = false
    /// 종료 저장이 실패했을 때 저장 없이 끝낼지 묻는다. 테스트는 확인창 대신 답을 주입한다.
    var confirmQuitWithoutSaving: @MainActor (AppModel) -> Bool = NegaflowApplicationDelegate.askToQuitWithoutSaving

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
            sender.reply(toApplicationShouldTerminate: shouldTerminate || self.quitAfterFailedSave())
        }
        switch decision {
        case .terminateNow:
            hasPendingTerminationReply = false
            return .terminateNow
        case .terminateLater:
            return .terminateLater
        case .terminateCancel:
            hasPendingTerminationReply = false
            return quitAfterFailedSave() ? .terminateNow : .terminateCancel
        }
    }

    /// 저장이 실패해도 종료를 무조건 막으면 강제 종료 말고는 앱을 끌 수 없다. 재실행 요청은
    /// 거두고, 사용자가 고르면 저장 없이 끝낸다.
    private func quitAfterFailedSave() -> Bool {
        model.isRelaunchRequested = false
        model.isLibraryReinstallPendingRelaunch = false
        guard confirmQuitWithoutSaving(model) else {
            model.reportError(model.text(AppLocalizedPhrase.librarySaveFailed))
            return false
        }
        return true
    }

    /// 기본 단추는 취소다 — 실수로 눌러도 기록을 잃지 않는다.
    private static func askToQuitWithoutSaving(_ model: AppModel) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = model.text(AppLocalizedPhrase.librarySaveFailed)
        alert.addButton(withTitle: model.text(AppLocalizedPhrase.cancel))
        alert.addButton(withTitle: model.text(AppLocalizedPhrase.quitWithoutSaving))
        return alert.runModal() == .alertSecondButtonReturn
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
