import XCTest
@testable import negaflowApp

final class UITestDiskFixturePreparerTests: XCTestCase {
    @MainActor
    func testModelFactoryIsolatesPrintSettingsByUITestRoot() {
        let firstRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-print-fixture-\(UUID().uuidString)",
            isDirectory: true
        )
        let secondRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-print-fixture-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            isolatedDefaults(for: firstRoot).removePersistentDomain(
                forName: isolatedDefaultsSuiteName(for: firstRoot)
            )
            isolatedDefaults(for: secondRoot).removePersistentDomain(
                forName: isolatedDefaultsSuiteName(for: secondRoot)
            )
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        let firstConfiguration = configuration(root: firstRoot)
        let secondConfiguration = configuration(root: secondRoot)

        let first = AppModelFactory.make(configuration: firstConfiguration)
        first.printWorkspaceSettingsStore.layoutMode = .contactSheet
        first.printWorkspaceSettingsStore.sheetColor = .gray

        let restored = AppModelFactory.make(configuration: firstConfiguration)
        XCTAssertEqual(restored.printWorkspaceSettingsStore.layoutMode, .contactSheet)
        XCTAssertEqual(restored.printWorkspaceSettingsStore.sheetColor, .gray)

        let independent = AppModelFactory.make(configuration: secondConfiguration)
        XCTAssertEqual(independent.printWorkspaceSettingsStore.layoutMode, .singleImage)
        XCTAssertEqual(independent.printWorkspaceSettingsStore.sheetColor, .white)
    }

    func testCreatesValidatedBackupBeforeCorruptingPrimaryCatalog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-corrupt-fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = root.appendingPathComponent("Library/catalog.sqlite")
        try FileManager.default.createDirectory(
            at: catalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(LibraryCatalogFile.writeSync(
            try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog())),
            to: catalogURL
        ))
        let configuration = AppLaunchConfiguration(
            uiTestRoot: root,
            importsSyntheticNegative: false,
            enablesDemoScanner: false,
            preparesCorruptCatalog: true,
            createsDropTargetFolder: false,
            developsImportsAutomatically: false,
            selectsAllFrames: false
        )

        UITestDiskFixturePreparer.prepare(configuration)

        XCTAssertNil(LibraryCatalogFile.loadPrimary(from: catalogURL))
        XCTAssertNotNil(LibraryBackupStore.latestValidSnapshot(
            in: root.appendingPathComponent("Library/Backups", isDirectory: true)
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("fixture-error.txt").path
        ))
    }

    private func configuration(root: URL) -> AppLaunchConfiguration {
        AppLaunchConfiguration(
            uiTestRoot: root,
            importsSyntheticNegative: false,
            enablesDemoScanner: false,
            preparesCorruptCatalog: false,
            createsDropTargetFolder: false,
            developsImportsAutomatically: false,
            selectsAllFrames: false
        )
    }

    private func isolatedDefaults(for root: URL) -> UserDefaults {
        UserDefaults(suiteName: isolatedDefaultsSuiteName(for: root))!
    }

    private func isolatedDefaultsSuiteName(for root: URL) -> String {
        let identifier = root.path.data(using: .utf8)?.base64EncodedString()
            ?? UUID().uuidString
        let safeIdentifier = identifier
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "+", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "com.negaflow.ui-tests.\(safeIdentifier)"
    }
}
