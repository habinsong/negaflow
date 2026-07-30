import XCTest

final class NegaflowWorkflowUITests: XCTestCase {
    private var app: XCUIApplication!
    private var fixtureRoot: URL!

    override func tearDown() {
        app?.terminate()
        if let fixtureRoot {
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
        app = nil
        fixtureRoot = nil
        super.tearDown()
    }

    func testImportedNegativeWaitsForFolderBatchDevelopmentAndExports() throws {
        launch(importSyntheticNegative: true, demoScanner: false)

        let export = app.buttons["negaflow.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 15))
        XCTAssertFalse(export.isEnabled)

        let library = app.buttons["negaflow.workspace.library"]
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        library.click()

        let folders = app.buttons["Folders"]
        XCTAssertTrue(folders.waitForExistence(timeout: 10))
        folders.click()

        let apply = app.buttons
            .matching(identifier: "negaflow.library.folder-develop-apply")
            .firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 5) { apply.isEnabled })
        apply.click()
        XCTAssertTrue(waitUntil(timeout: 90) { export.isEnabled })

        let develop = app.buttons["negaflow.workspace.develop"]
        XCTAssertTrue(develop.waitForExistence(timeout: 10))
        develop.click()
        try waitForDevelopedCanvas()
        try exportAndWaitForArtifact()
    }

    func testDemoScanDevelopsAndExports() throws {
        launch(importSyntheticNegative: false, demoScanner: true)

        let scanButton = app.buttons["negaflow.scan"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil(timeout: 15) { scanButton.isEnabled })
        scanButton.click()

        try waitForDevelopedCanvas()
        try exportAndWaitForArtifact()
    }

    func testWorkspaceSelectionAndPanelToggleExposeState() {
        launch(importSyntheticNegative: true, demoScanner: false)

        let library = app.buttons["negaflow.workspace.library"]
        let develop = app.buttons["negaflow.workspace.develop"]
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        XCTAssertTrue(develop.waitForExistence(timeout: 15))
        XCTAssertFalse(library.isSelected)
        XCTAssertTrue(develop.isSelected)

        library.click()
        XCTAssertTrue(waitUntil(timeout: 5) { library.isSelected && !develop.isSelected })
        develop.click()
        XCTAssertTrue(waitUntil(timeout: 5) { develop.isSelected && !library.isSelected })

        let sidebar = app.buttons["negaflow.panel.sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        let initialValue = String(describing: sidebar.value)
        sidebar.click()
        XCTAssertTrue(waitUntil(timeout: 5) {
            String(describing: sidebar.value) != initialValue
        })
    }

    func testPrintInspectorExposesLayoutContentAndCPrintOutput() throws {
        launch(importSyntheticNegative: true, demoScanner: false, autoDevelopImports: true)
        try waitForDevelopedCanvas()

        let print = app.buttons["negaflow.workspace.print"]
        XCTAssertTrue(print.waitForExistence(timeout: 15))
        print.click()

        let inspector = app.descendants(matching: .any)["negaflow.print.inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["negaflow.print.inspector.layout"]
                .waitForExistence(timeout: 10)
        )

        let layoutMode = app.descendants(matching: .any)["negaflow.print.layout.mode"]
        XCTAssertTrue(layoutMode.waitForExistence(timeout: 10))
        layoutMode.click()
        let contactSheet = app.menuItems.element(boundBy: 1)
        XCTAssertTrue(contactSheet.waitForExistence(timeout: 5))
        contactSheet.click()

        let tabs = app.descendants(matching: .any)["negaflow.print.inspector.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(tabs.buttons.count, 3)
        tabs.buttons.element(boundBy: 1).click()
        XCTAssertTrue(
            app.descendants(matching: .any)["negaflow.print.inspector.content"]
                .waitForExistence(timeout: 10)
        )

        tabs.buttons.element(boundBy: 2).click()
        XCTAssertTrue(
            app.descendants(matching: .any)["negaflow.print.inspector.output"]
                .waitForExistence(timeout: 10)
        )
        let outputProcess = app.descendants(matching: .any)["negaflow.print.output.process"]
        XCTAssertTrue(outputProcess.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(outputProcess.buttons.count, 2)
        outputProcess.buttons.element(boundBy: 1).click()

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Print inspector — C-print output"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testHelpMenuDeepLinksToShortcutsAndCommandShiftHOpensQuickStart() {
        launch(importSyntheticNegative: false, demoScanner: false)

        let helpMenu = app.menuBars.menuBarItems.element(
            boundBy: app.menuBars.menuBarItems.count - 1
        )
        XCTAssertTrue(helpMenu.exists)
        helpMenu.click()
        let shortcuts = app.menuItems["Keyboard Shortcuts"]
        XCTAssertTrue(shortcuts.waitForExistence(timeout: 5))
        shortcuts.click()
        let shortcutSettings = app.descendants(matching: .any)["settings.shortcuts"]
        XCTAssertTrue(shortcutSettings.waitForExistence(timeout: 10))

        app.typeKey("w", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 10) { !shortcutSettings.exists })
        app.activate()
        app.windows.firstMatch.click()
        app.typeKey("h", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            app.descendants(matching: .any)["help.quickStart"]
                .waitForExistence(timeout: 10)
        )
    }

    func testCorruptCatalogRecoversFromBackupAndSurvivesRelaunch() throws {
        launch(importSyntheticNegative: true, demoScanner: false, autoDevelopImports: true)
        try waitForDevelopedCanvas()
        try waitForCatalogPersistence()
        terminateForRelaunch()

        launch(importSyntheticNegative: false, demoScanner: false, corruptCatalog: true)
        let recovery = app.descendants(matching: .any)["negaflow.recovery"]
        XCTAssertFalse(recovery.exists)
        try waitForDevelopedCanvas()
        terminateForRelaunch()

        launch(importSyntheticNegative: false, demoScanner: false)
        XCTAssertFalse(recovery.exists)
        try waitForDevelopedCanvas()
    }

    func testOfflineSourceRelinksAndSurvivesRelaunch() throws {
        launch(importSyntheticNegative: true, demoScanner: false, autoDevelopImports: true)
        try waitForDevelopedCanvas()
        try waitForCatalogPersistence()
        terminateForRelaunch()

        let original = fixtureRoot.appendingPathComponent("Fixtures/synthetic-negative.tiff")
        let replacement = fixtureRoot.appendingPathComponent("Fixtures/relinked-negative.tiff")
        try FileManager.default.copyItem(at: original, to: replacement)
        try FileManager.default.removeItem(at: original)
        launch(importSyntheticNegative: false, demoScanner: false)

        let frameCard = app.descendants(matching: .any)
            .matching(identifier: "negaflow.frame-card").firstMatch
        XCTAssertTrue(frameCard.waitForExistence(timeout: 20))
        XCTAssertTrue(waitUntil(timeout: 10) { frameCard.value as? String == "offline" })
        let export = app.buttons["negaflow.export"]
        XCTAssertFalse(export.isEnabled)

        frameCard.rightClick()
        let relink = app.menuItems["Locate Original"]
        XCTAssertTrue(relink.waitForExistence(timeout: 10))
        relink.click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(replacement.path)
        app.typeKey(.enter, modifierFlags: [])
        app.typeKey(.enter, modifierFlags: [])

        XCTAssertTrue(waitUntil(timeout: 30) { frameCard.value as? String == "online" })
        frameCard.click()
        try waitForDevelopedCanvas()
        terminateForRelaunch()

        launch(importSyntheticNegative: false, demoScanner: false)
        let restoredCard = app.descendants(matching: .any)
            .matching(identifier: "negaflow.frame-card").firstMatch
        XCTAssertTrue(restoredCard.waitForExistence(timeout: 20))
        XCTAssertTrue(waitUntil(timeout: 10) { restoredCard.value as? String == "online" })
    }

    func testTreeFileRowDragToFolderMovesSourceFile() throws {
        launch(importSyntheticNegative: true, demoScanner: false, dropTargetFolder: true)

        openLibraryFiles()

        let fileRow = app.buttons.matching(identifier: "negaflow.library.file-row").firstMatch
        XCTAssertTrue(fileRow.waitForExistence(timeout: 20))
        let dropFolder = app.buttons.matching(identifier: "negaflow.library.folder-row")
            .matching(NSPredicate(format: "label == %@", "DropTarget")).firstMatch
        XCTAssertTrue(dropFolder.waitForExistence(timeout: 20))

        fileRow.click(forDuration: 0.5, thenDragTo: dropFolder)

        try assertSyntheticNegativeMovedToDropTarget()
    }

    func testGridFrameCardDragToFolderMovesSourceFile() throws {
        launch(importSyntheticNegative: true, demoScanner: false, dropTargetFolder: true)

        openLibraryFiles()

        let card = app.descendants(matching: .any)
            .matching(identifier: "negaflow.frame-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        let dropFolder = app.buttons.matching(identifier: "negaflow.library.folder-row")
            .matching(NSPredicate(format: "label == %@", "DropTarget")).firstMatch
        XCTAssertTrue(dropFolder.waitForExistence(timeout: 20))

        card.click(forDuration: 0.5, thenDragTo: dropFolder)

        try assertSyntheticNegativeMovedToDropTarget()
    }

    private func assertSyntheticNegativeMovedToDropTarget() throws {
        let moved = fixtureRoot.appendingPathComponent("DropTarget/synthetic-negative.tiff")
        let original = fixtureRoot.appendingPathComponent("Fixtures/synthetic-negative.tiff")
        XCTAssertTrue(
            waitUntil(timeout: 30) {
                FileManager.default.fileExists(atPath: moved.path)
                    && !FileManager.default.fileExists(atPath: original.path)
            },
            "source file was not moved to DropTarget"
        )
    }

    private func openLibraryFiles() {
        let library = app.buttons["negaflow.workspace.library"]
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        library.click()
        XCTAssertTrue(waitUntil(timeout: 5) { library.isSelected })

        let files = app.buttons["negaflow.library.controls.files"]
        XCTAssertTrue(files.waitForExistence(timeout: 10))
        files.click()
    }

    private func launch(
        importSyntheticNegative: Bool,
        demoScanner: Bool,
        corruptCatalog: Bool = false,
        dropTargetFolder: Bool = false,
        autoDevelopImports: Bool = false
    ) {
        if fixtureRoot == nil {
            fixtureRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("negaflow-ui-test-\(UUID().uuidString)", isDirectory: true)
        }
        app = XCUIApplication()
        app.launchEnvironment["NEGAFLOW_UI_TEST_MODE"] = "1"
        app.launchEnvironment["NEGAFLOW_UI_TEST_ROOT"] = fixtureRoot.path
        app.launchEnvironment["NEGAFLOW_UI_TEST_IMPORT_SYNTHETIC"] = importSyntheticNegative ? "1" : "0"
        app.launchEnvironment["NEGAFLOW_UI_TEST_DEMO"] = demoScanner ? "1" : "0"
        app.launchEnvironment["NEGAFLOW_UI_TEST_CORRUPT_CATALOG"] = corruptCatalog ? "1" : "0"
        app.launchEnvironment["NEGAFLOW_UI_TEST_DROP_FOLDER"] = dropTargetFolder ? "1" : "0"
        app.launchEnvironment["NEGAFLOW_UI_TEST_AUTO_DEVELOP"] = autoDevelopImports ? "1" : "0"
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["negaflow.main"].waitForExistence(timeout: 15))
    }

    private func terminateForRelaunch() {
        app.terminate()
        app = nil
    }

    private func waitForCatalogPersistence() throws {
        let catalog = fixtureRoot.appendingPathComponent("Library/catalog.sqlite")
        XCTAssertTrue(waitUntil(timeout: 20) {
            guard let size = try? catalog.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return false
            }
            return size > 0
        })
    }

    private func waitForDevelopedCanvas() throws {
        let canvas = app.descendants(matching: .any)["negaflow.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 30))
        let export = app.buttons["negaflow.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil(timeout: 90) { export.isEnabled })
    }

    private func exportAndWaitForArtifact() throws {
        let exportButton = app.buttons["negaflow.export"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil(timeout: 15) { exportButton.isEnabled })
        exportButton.click()

        let exportRoot = fixtureRoot.appendingPathComponent("Exports", isDirectory: true)
        XCTAssertTrue(waitUntil(timeout: 90) {
            Self.containsExportArtifact(in: exportRoot)
        })
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return condition()
    }

    private static func containsExportArtifact(in root: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return false }
        let extensions = Set(["jpg", "jpeg", "png", "tif", "tiff"])
        for case let url as URL in enumerator where extensions.contains(url.pathExtension.lowercased()) {
            return true
        }
        return false
    }
}
