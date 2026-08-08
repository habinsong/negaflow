import Foundation

struct AppMenuCatalog {
    struct Menu: Equatable {
        let title: String
        let commands: [Command]
    }

    struct Command: Equatable {
        let title: String
    }

    let language: AppLanguage

    var menus: [Menu] {
        [
            menu(.menuFile, [.commandImportImages, .commandRefreshLibrary, .loadScanner, .commandQuickExport, .commandExport]),
            menu(.menuEdit, [.commandCopyDevelopSettings, .commandPasteDevelopSettings, .commandPick, .commandReject, .commandDeletePhoto]),
            menu(.menuView, [.commandShowHideSidebar, .commandShowHideFilmstrip, .commandShowHideInspector, .commandToggleFullScreen]),
            menu(.menuWindow, [.commandSettings]),
            menu(.menuHelp, [.commandKeyboardShortcuts, .commandNegaflowHelp]),
            menu(.menuLibrary, [.commandImportImages, .commandRefreshLibrary, .loadScanner]),
            menu(.menuPhoto, [.commandPick, .commandReject, .commandDeletePhoto]),
            menu(.menuDevelop, [.commandAutoTone, .commandAutoWhiteBalance, .commandResetAdjustments, .commandCopyDevelopSettings, .commandPasteDevelopSettings]),
            menu(.menuScanner, [.commandDetectScanners, .commandToggleScannerSimulator, .commandPreviewScan, .commandScanFrame]),
            menu(.menuExport, [.commandQuickExport, .commandExport]),
        ]
    }

    private func menu(_ title: AppLocalizedText, _ commands: [AppLocalizedText]) -> Menu {
        Menu(
            title: AppLocalization.text(title, language: language),
            commands: commands.map { Command(title: AppLocalization.text($0, language: language)) }
        )
    }
}
