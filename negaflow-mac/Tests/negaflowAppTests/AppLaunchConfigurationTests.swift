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
            "NEGAFLOW_UI_TEST_DEMO": "1",
            "NEGAFLOW_UI_TEST_AUTO_DEVELOP": "1",
            "NEGAFLOW_UI_TEST_SELECT_ALL": "1"
        ])

        XCTAssertEqual(configuration?.uiTestRoot.path, "/tmp/negaflow-e2e")
        XCTAssertEqual(configuration?.importsSyntheticNegative, true)
        XCTAssertEqual(configuration?.enablesDemoScanner, true)
        XCTAssertEqual(configuration?.preparesCorruptCatalog, false)
        XCTAssertEqual(configuration?.developsImportsAutomatically, true)
        XCTAssertEqual(configuration?.selectsAllFrames, true)
    }

    /// `open` 은 부른 쪽의 환경을 새 앱에 넘긴다. 격리 루트는 이어져야 하고, 한 번만 할 유지보수
    /// 지시는 빠져야 한다 — 남으면 재실행할 때마다 복구가 다시 돌아 끝나지 않았다(실측).
    func testRelaunchKeepsTheTestRootButNotTheMaintenanceRequest() {
        let environment = [
            "NEGAFLOW_UI_TEST_MODE": "1",
            "NEGAFLOW_UI_TEST_ROOT": "/tmp/negaflow-e2e",
            "NEGAFLOW_UI_TEST_DEMO": "1",
            "NEGAFLOW_UI_TEST_MAINTENANCE": "repair",
            "HOME": "/Users/someone",
        ]

        XCTAssertEqual(AppLaunchConfiguration.from(environment: environment)?.libraryMaintenance, .repair)
        XCTAssertEqual(AppLaunchConfiguration.relaunchEnvironment(from: environment), [
            "NEGAFLOW_UI_TEST_MODE": "1",
            "NEGAFLOW_UI_TEST_ROOT": "/tmp/negaflow-e2e",
            "NEGAFLOW_UI_TEST_DEMO": "1",
            "HOME": "/Users/someone",
        ])
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
            createsDropTargetFolder: false,
            developsImportsAutomatically: false,
            selectsAllFrames: false
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

    /// 저널이 사용자 Application Support 에 남으면 앞선 UI 테스트가 종료로 끊은 export
    /// transaction 이 산출물 없는 상태로 남아 다음 실행을 복구 화면으로 막는다.
    func testExportJournalDirectoryFollowsUITestRoot() {
        let root = URL(fileURLWithPath: "/tmp/negaflow-e2e-journal", isDirectory: true)
        let configuration = AppLaunchConfiguration(
            uiTestRoot: root,
            importsSyntheticNegative: false,
            enablesDemoScanner: false,
            preparesCorruptCatalog: false,
            createsDropTargetFolder: false,
            developsImportsAutomatically: false,
            selectsAllFrames: false
        )

        XCTAssertEqual(
            ExportArtifactCommitJournal.defaultDirectoryURL(launchConfiguration: configuration).path,
            root.appendingPathComponent("Library/ExportJournals").path
        )
        XCTAssertTrue(
            ExportArtifactCommitJournal.defaultDirectoryURL(launchConfiguration: nil).path
                .hasSuffix("negaflow/export-journals")
        )
    }

    @MainActor
    func testFactoryIsolatesWorkspacePresentationForUITestRoot() {
        let token = UUID().uuidString
        let firstRoot = URL(
            fileURLWithPath: "/tmp/negaflow-e2e-first-\(token)",
            isDirectory: true
        )
        let secondRoot = URL(
            fileURLWithPath: "/tmp/negaflow-e2e-second-\(token)",
            isDirectory: true
        )
        let firstConfiguration = AppLaunchConfiguration(
            uiTestRoot: firstRoot,
            importsSyntheticNegative: false,
            enablesDemoScanner: false,
            preparesCorruptCatalog: false,
            createsDropTargetFolder: false,
            developsImportsAutomatically: false,
            selectsAllFrames: false
        )
        let secondConfiguration = AppLaunchConfiguration(
            uiTestRoot: secondRoot,
            importsSyntheticNegative: false,
            enablesDemoScanner: false,
            preparesCorruptCatalog: false,
            createsDropTargetFolder: false,
            developsImportsAutomatically: false,
            selectsAllFrames: false
        )

        let first = AppModelFactory.makeWorkspacePresentationStore(
            configuration: firstConfiguration
        )
        first.module = .library

        XCTAssertEqual(
            AppModelFactory.makeWorkspacePresentationStore(
                configuration: firstConfiguration
            ).module,
            .library
        )
        XCTAssertEqual(
            AppModelFactory.makeWorkspacePresentationStore(
                configuration: secondConfiguration
            ).module,
            .develop
        )
    }
}
