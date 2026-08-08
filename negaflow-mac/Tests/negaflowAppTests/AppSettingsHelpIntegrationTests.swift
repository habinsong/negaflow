import Chromabase
import XCTest
@testable import negaflowApp

final class AppSettingsHelpIntegrationTests: XCTestCase {
    func testSettingsTabsHaveStableUniquePersistenceValues() {
        XCTAssertEqual(AppSettingsTab.defaultsKey, "settings.selectedTab")
        XCTAssertEqual(AppSettingsTab.allCases.count, 8)
        XCTAssertEqual(Set(AppSettingsTab.allCases.map(\.rawValue)).count, 8)
        XCTAssertTrue(AppSettingsTab.allCases.contains(.shortcuts))
    }

    func testQuickStartIsCompleteAndLocalizedForEverySupportedLanguage() {
        for language in AppLanguage.allCases where language != .system {
            let content = QuickStartHelpContent.localized(for: language)
            XCTAssertFalse(content.title.isEmpty, language.rawValue)
            XCTAssertFalse(content.introduction.isEmpty, language.rawValue)
            XCTAssertEqual(content.steps.map(\.id), [1, 2, 3], language.rawValue)
            XCTAssertTrue(content.steps.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
            XCTAssertFalse(content.versionLabel.isEmpty, language.rawValue)
            XCTAssertTrue(content.shortcutNote.contains("Command-Shift-H"), language.rawValue)
        }
    }

    func testQuickStartDocumentUsesSharedProductVersion() {
        let document = QuickStartHelpDocument.current(for: .english)

        XCTAssertEqual(document.version, NegaflowProductVersion.applicationVersion())
        XCTAssertNotEqual(document.version, "unknown")
    }

    @MainActor
    func testHelpShortcutAvoidsSystemHelpMenuShortcut() {
        let shortcut = WorkflowShortcutAction.openHelp.defaultShortcut

        XCTAssertEqual(shortcut.key, "h")
        XCTAssertEqual(shortcut.modifiers, [.command, .shift])
    }
}
