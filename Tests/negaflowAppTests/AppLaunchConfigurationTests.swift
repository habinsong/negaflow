import XCTest
@testable import negaflowApp

final class AppLaunchConfigurationTests: XCTestCase {
    func testRequiresExplicitModeAndAbsoluteRoot() {
        XCTAssertNil(AppLaunchConfiguration.from(environment: [:]))
        XCTAssertNil(AppLaunchConfiguration.from(environment: [
            "NEGAFLOW_UI_TEST_MODE": "1",
            "NEGAFLOW_UI_TEST_ROOT": "relative/path"
        ]))
    }

    func testParsesFixtureFlags() {
        let configuration = AppLaunchConfiguration.from(environment: [
            "NEGAFLOW_UI_TEST_MODE": "1",
            "NEGAFLOW_UI_TEST_ROOT": "/tmp/negaflow-e2e",
            "NEGAFLOW_UI_TEST_IMPORT_SYNTHETIC": "1",
            "NEGAFLOW_UI_TEST_DEMO": "1"
        ])

        XCTAssertEqual(configuration?.uiTestRoot.path, "/tmp/negaflow-e2e")
        XCTAssertEqual(configuration?.importsSyntheticNegative, true)
        XCTAssertEqual(configuration?.enablesDemoScanner, true)
        XCTAssertEqual(configuration?.preparesCorruptCatalog, false)
    }

    @MainActor
    func testFactoryIsolatesPersistentPaths() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-model-factory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = AppLaunchConfiguration(
            uiTestRoot: root,
            importsSyntheticNegative: false,
            enablesDemoScanner: true,
            preparesCorruptCatalog: false,
            createsDropTargetFolder: false
        )

        let model = AppModelFactory.make(configuration: configuration)

        XCTAssertEqual(model.libraryCatalogURL.path, root.appendingPathComponent("Library/catalog.sqlite").path)
        XCTAssertEqual(model.libraryDefectDirectoryURL.path, root.appendingPathComponent("Library/Defects").path)
        XCTAssertEqual(model.libraryBackupDirectoryURL.path, root.appendingPathComponent("Library/Backups").path)
        XCTAssertEqual(model.exportFolderURL.path, root.appendingPathComponent("Exports").path)
        XCTAssertEqual(model.diskStorage.scansURL.path, root.appendingPathComponent("Scans").path)
        XCTAssertNil(model.scannerPluginTrustStore)
        XCTAssertEqual(model.appLanguage, .english)
        XCTAssertTrue(model.demoMode)
    }
}
