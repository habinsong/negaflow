import SwiftUI

struct AppStandardMenuCommands: Commands {
    @ObservedObject var model: AppModel
    @AppStorage("workspace.leftPanelVisible") private var isSidebarVisible = true
    @AppStorage("workspace.rightPanelVisible") private var isInspectorVisible = true
    @AppStorage("workspace.bottomStripVisible") private var isFilmstripVisible = true

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            OpenAboutNegaflowButton(
                title: model.text(.commandAboutNegaflow)
            )
        }

        CommandGroup(after: .newItem) {
            Button(model.text(.commandImportImages)) {
                model.performWorkflowShortcutAction(.importImages)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .importImages))

            Button(model.text(AppLocalizedPhrase.importFolder)) {
                model.performWorkflowShortcutAction(.importFolder)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .importFolder))

            Button(model.text(.commandRefreshLibrary)) {
                model.performWorkflowShortcutAction(.refreshLibrary)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .refreshLibrary))

            Button(model.text(.loadScanner)) {
                model.performWorkflowShortcutAction(.loadScanner)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .loadScanner))
        }

        CommandGroup(after: .importExport) {
            Button(model.text(.commandQuickExport)) {
                model.performWorkflowShortcutAction(.quickExport)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .quickExport))

            Button(model.text(.commandExport)) {
                model.performWorkflowShortcutAction(.exportPhoto)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .exportPhoto))
        }

        // 되돌리기/다시 실행은 앱 전체에서 이 두 항목만 받는다. 화면·도구별 ⌘Z 를 따로 두면
        // 마지막에 한 일이 아니라 그 화면이 아는 일을 되돌리게 된다.
        // 활성/비활성을 여기서 계산하지 않는 이유: UndoManager 의 스택 변화는 발행되지 않아
        // 메뉴가 옛 상태로 굳는다. 되돌릴 것이 없으면 동작이 조용히 아무 일도 하지 않는다.
        CommandGroup(replacing: .undoRedo) {
            Button(model.text(AppLocalizedPhrase.undo)) {
                model.performUndo()
            }
            .keyboardShortcut("z", modifiers: .command)

            Button(model.text(AppLocalizedPhrase.redo)) {
                model.performRedo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(after: .pasteboard) {
            Button(model.text(.commandCopyDevelopSettings)) {
                model.performWorkflowShortcutAction(.copyDevelopSettings)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .copyDevelopSettings))

            Button(model.text(.commandPasteDevelopSettings)) {
                model.performWorkflowShortcutAction(.pasteDevelopSettings)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .pasteDevelopSettings))
        }

        CommandGroup(after: .textEditing) {
            Button(model.text(.commandPick)) {
                model.performWorkflowShortcutAction(.pickPhoto)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .pickPhoto))

            Button(model.text(.commandReject)) {
                model.performWorkflowShortcutAction(.rejectPhoto)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .rejectPhoto))

            Button(model.text(.commandDeletePhoto), role: .destructive) {
                model.performWorkflowShortcutAction(.deletePhoto)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .deletePhoto))
        }

        CommandGroup(after: .sidebar) {
            Button(model.text(.commandShowHideSidebar)) {
                isSidebarVisible.toggle()
            }
            .workflowKeyboardShortcut(model.shortcut(for: .showHideSidebar))

            Button(model.text(.commandShowHideFilmstrip)) {
                isFilmstripVisible.toggle()
            }
            .workflowKeyboardShortcut(model.shortcut(for: .showHideFilmstrip))

            Button(model.text(.commandShowHideInspector)) {
                isInspectorVisible.toggle()
            }
            .workflowKeyboardShortcut(model.shortcut(for: .showHideInspector))
        }

        CommandGroup(after: .toolbar) {
            Button(model.text(.commandToggleFullScreen)) {
                model.performWorkflowShortcutAction(.toggleFullScreen)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .toggleFullScreen))

            Divider()

            Button(model.text(.menuLibrary)) {
                model.performWorkflowShortcutAction(.openLibraryWorkspace)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .openLibraryWorkspace))

            Button(model.text(.menuDevelop)) {
                model.performWorkflowShortcutAction(.openDevelopWorkspace)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .openDevelopWorkspace))

            Button(model.text(.menuPrint)) {
                model.performWorkflowShortcutAction(.openPrintWorkspace)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .openPrintWorkspace))
        }

        CommandGroup(after: .help) {
            OpenSettingsTabButton(
                title: model.text(.commandKeyboardShortcuts),
                tab: .shortcuts
            )

            OpenQuickStartHelpButton(
                title: model.text(.commandNegaflowHelp),
                shortcut: model.shortcut(for: .openHelp)
            )
        }
    }
}

private struct OpenAboutNegaflowButton: View {
    let title: String

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) {
            openWindow(id: AboutNegaflowView.windowID)
        }
    }
}

private struct OpenSettingsTabButton: View {
    let title: String
    let tab: AppSettingsTab

    @AppStorage(AppSettingsTab.defaultsKey)
    private var selectedTab: AppSettingsTab = .general
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(title) {
            selectedTab = tab
            openSettings()
        }
    }
}

private struct OpenQuickStartHelpButton: View {
    let title: String
    let shortcut: WorkflowShortcut

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) {
            openWindow(id: QuickStartHelpScene.windowID)
        }
        .workflowKeyboardShortcut(shortcut)
    }
}
