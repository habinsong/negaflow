import XCTest
@testable import negaflowApp

@MainActor
final class WorkflowShortcutSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "negaflow.workflow-shortcuts.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testShortcutStorePersistsCustomAssignmentsAndFallsBackToDefaults() {
        let store = WorkflowShortcutStore(defaults: defaults)

        XCTAssertEqual(store.shortcut(for: .pickPhoto), WorkflowShortcut(key: "p", modifiers: []))
        XCTAssertTrue(store.setShortcut(WorkflowShortcut(key: "g", modifiers: [.command, .shift]), for: .pickPhoto))

        let reloaded = WorkflowShortcutStore(defaults: defaults)

        XCTAssertEqual(reloaded.shortcut(for: .pickPhoto), WorkflowShortcut(key: "g", modifiers: [.command, .shift]))
        XCTAssertEqual(reloaded.shortcut(for: .rejectPhoto), WorkflowShortcut(key: "x", modifiers: []))
    }

    func testShortcutStoreMigratesLegacySemiAutoOverrideToGuided() throws {
        let legacyShortcut = WorkflowShortcut(key: "g", modifiers: [.command, .shift])
        let legacyPayload = ["semiAutoDefectTool": legacyShortcut]
        defaults.set(
            try JSONEncoder().encode(legacyPayload),
            forKey: "workflow.shortcuts.overrides"
        )

        let store = WorkflowShortcutStore(defaults: defaults)

        XCTAssertEqual(store.shortcut(for: .guidedDefectTool), legacyShortcut)
    }

    func testShortcutStoreRejectsInvalidAndDuplicateAssignments() {
        let store = WorkflowShortcutStore(defaults: defaults)

        XCTAssertFalse(store.setShortcut(WorkflowShortcut(key: "", modifiers: []), for: .pickPhoto))
        XCTAssertFalse(store.setShortcut(WorkflowShortcut(key: "ab", modifiers: []), for: .pickPhoto))
        XCTAssertFalse(store.setShortcut(store.shortcut(for: .rejectPhoto), for: .pickPhoto))
        XCTAssertEqual(store.shortcut(for: .pickPhoto), WorkflowShortcut(key: "p", modifiers: []))
    }

    func testShortcutRecorderCommitsMultiModifierShortcutOnKeyRelease() {
        let result = WorkflowShortcutRecorder.shortcutFromKeyRelease(
            key: "C",
            modifiers: [.shift, .control]
        )

        XCTAssertEqual(result, .commit(WorkflowShortcut(key: "c", modifiers: [.shift, .control])))
    }

    func testShortcutRecorderRejectsModifierOnlyAndCancelsEscape() {
        XCTAssertEqual(
            WorkflowShortcutRecorder.shortcutFromKeyRelease(key: "", modifiers: [.shift, .control]),
            .invalid
        )
        XCTAssertEqual(
            WorkflowShortcutRecorder.shortcutFromKeyRelease(key: "escape", modifiers: []),
            .cancel
        )
    }

    func testShortcutStoreIncludesAdditionalWorkflowCommands() {
        let store = WorkflowShortcutStore(defaults: defaults)

        XCTAssertEqual(store.shortcut(for: .deletePhoto), WorkflowShortcut(key: "delete", modifiers: []))
        XCTAssertEqual(store.shortcut(for: .copyDevelopSettings), WorkflowShortcut(key: "c", modifiers: [.command, .shift]))
        XCTAssertEqual(store.shortcut(for: .pasteDevelopSettings), WorkflowShortcut(key: "v", modifiers: [.command, .shift]))
        XCTAssertEqual(store.shortcut(for: .rotateLeft), WorkflowShortcut(key: "[", modifiers: [.command, .shift]))
        XCTAssertEqual(store.shortcut(for: .rotateRight), WorkflowShortcut(key: "]", modifiers: [.command, .shift]))
        XCTAssertEqual(store.shortcut(for: .flipHorizontal), WorkflowShortcut(key: "h", modifiers: [.command, .option]))
        XCTAssertEqual(store.shortcut(for: .flipVertical), WorkflowShortcut(key: "v", modifiers: [.command, .option]))
        XCTAssertEqual(store.shortcut(for: .toggleFullScreen), WorkflowShortcut(key: "f", modifiers: [.command, .control]))
        XCTAssertEqual(store.shortcut(for: .openHelp), WorkflowShortcut(key: "h", modifiers: [.command, .shift]))
    }

    func testShortcutSettingsExposeSevenLocalizedWorkflowGroups() {
        let model = AppModel(
            presentationPreferencesStore: PresentationPreferencesStore(defaults: defaults),
            workflowShortcutStore: WorkflowShortcutStore(defaults: defaults)
        )
        model.appLanguage = .korean

        XCTAssertEqual(
            WorkflowShortcutGroup.allCases.map { model.text($0.titleKey) },
            ["라이브러리", "사진", "현상", "보기", "스캐너", "내보내기", "도움말"]
        )
        for group in WorkflowShortcutGroup.allCases {
            XCTAssertTrue(
                WorkflowShortcutAction.allCases.contains { $0.group == group },
                "\(group)"
            )
        }
    }

    func testEveryDefaultShortcutIsValidAndUnique() {
        let shortcuts = WorkflowShortcutAction.allCases.map(\.defaultShortcut)

        XCTAssertTrue(shortcuts.allSatisfy(\.isValid))
        XCTAssertEqual(Set(shortcuts.map(\.signature)).count, shortcuts.count)
    }

    func testEveryShortcutTitleIsLocalizedAcrossSupportedLanguages() {
        let model = AppModel(
            presentationPreferencesStore: PresentationPreferencesStore(defaults: defaults),
            workflowShortcutStore: WorkflowShortcutStore(defaults: defaults)
        )

        for language in AppLanguage.allCases where language != .system {
            model.appLanguage = language
            for action in WorkflowShortcutAction.allCases {
                let title = action.title(in: model)
                XCTAssertFalse(title.isEmpty, "\(language.rawValue): \(action.rawValue)")
                XCTAssertFalse(title.contains("..."), "\(language.rawValue): \(action.rawValue)")
            }
        }
    }

    func testNewPhotoWorkflowDefaultsFollowEditingConventions() {
        XCTAssertEqual(
            WorkflowShortcutAction.importFolder.defaultShortcut,
            WorkflowShortcut(key: "i", modifiers: [.command, .shift])
        )
        XCTAssertEqual(
            WorkflowShortcutAction.createVirtualCopy.defaultShortcut,
            WorkflowShortcut(key: "'", modifiers: [.command])
        )
        XCTAssertEqual(
            WorkflowShortcutAction.libraryGrid.defaultShortcut,
            WorkflowShortcut(key: "g", modifiers: [])
        )
        XCTAssertEqual(
            WorkflowShortcutAction.cropTool.defaultShortcut,
            WorkflowShortcut(key: "r", modifiers: [])
        )
        XCTAssertEqual(
            WorkflowShortcutAction.guidedDefectTool.defaultShortcut,
            WorkflowShortcut(key: "q", modifiers: [])
        )
        XCTAssertEqual(
            WorkflowShortcutAction.brushDefectTool.defaultShortcut,
            WorkflowShortcut(key: "b", modifiers: [])
        )
        XCTAssertEqual(
            WorkflowShortcutAction.cloneStampTool.defaultShortcut,
            WorkflowShortcut(key: "s", modifiers: [])
        )
    }

    func testAppModelPerformsNewDevelopToggleProcessAndTargetActions() {
        let model = AppModel(workflowShortcutStore: WorkflowShortcutStore(defaults: defaults))
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-shortcut-develop.tif"),
            filmType: .colorNegative
        )
        model.frames = [frame]
        model.selectedFrameID = frame.id

        model.performWorkflowShortcutAction(.toggleAutoColor)
        model.performWorkflowShortcutAction(.toggleAutoLevels)
        model.performWorkflowShortcutAction(.toggleNoiseReduction)

        XCTAssertTrue(frame.params.autoNeutralBalance)
        XCTAssertTrue(frame.params.autoLevels)
        XCTAssertEqual(frame.params.noiseReduction, 0.7, accuracy: 1e-12)

        model.performWorkflowShortcutAction(.toggleNoiseReduction)
        XCTAssertEqual(frame.params.noiseReduction, 0, accuracy: 1e-12)

        model.performWorkflowShortcutAction(.processBWNegative)
        XCTAssertEqual(frame.filmType, .bwNegative)
        XCTAssertEqual(frame.params.filmType, .bwNegative)

        model.performWorkflowShortcutAction(.targetHR)
        XCTAssertEqual(model.developTarget, .hr)
        XCTAssertEqual(frame.params.developTarget, .hr)
        XCTAssertNil(frame.params.scannerProfileID)

        model.developController.cancelPendingDevelopRequest()
    }

    func testToolAndWorkspaceShortcutsPublishUsableRequests() {
        let model = AppModel(workflowShortcutStore: WorkflowShortcutStore(defaults: defaults))
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-shortcut-tools.tif"),
            filmType: .colorNegative
        )
        model.frames = [frame]
        model.selectedFrameID = frame.id
        let initialRequest = model.developToolShortcutRequest

        model.performWorkflowShortcutAction(.cloneStampTool)

        XCTAssertEqual(model.activeWorkspaceModule, .develop)
        XCTAssertEqual(model.pendingDevelopToolShortcutAction, .cloneStampTool)
        XCTAssertEqual(model.developToolShortcutRequest, initialRequest + 1)

        model.performWorkflowShortcutAction(.librarySurvey)
        XCTAssertEqual(model.activeWorkspaceModule, .library)
        XCTAssertEqual(model.libraryCullingMode, .survey)

        model.performWorkflowShortcutAction(.openPrintWorkspace)
        XCTAssertEqual(model.activeWorkspaceModule, .print)
    }

    func testAppModelPerformsPhotoWorkflowShortcutActions() {
        let store = WorkflowShortcutStore(defaults: defaults)
        let model = AppModel(workflowShortcutStore: store)
        let first = ScanFrame(scanIndex: 1, rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-1.tif"), filmType: .colorNegative)
        let second = ScanFrame(scanIndex: 2, rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-2.tif"), filmType: .colorNegative)
        model.frames = [first, second]
        model.selectedFrameID = first.id

        model.performWorkflowShortcutAction(.pickPhoto)
        XCTAssertEqual(first.pickState, .picked)

        model.performWorkflowShortcutAction(.rateFive)
        XCTAssertEqual(first.rating, 5)

        model.performWorkflowShortcutAction(.rateFive)
        XCTAssertEqual(first.rating, 0)

        model.performWorkflowShortcutAction(.rateThree)
        XCTAssertEqual(first.rating, 3)

        model.performWorkflowShortcutAction(.nextPhoto)
        XCTAssertEqual(model.selectedFrameID, second.id)

        model.performWorkflowShortcutAction(.previousPhoto)
        XCTAssertEqual(model.selectedFrameID, first.id)

        model.performWorkflowShortcutAction(.clearPick)
        XCTAssertEqual(first.pickState, .unflagged)

        model.performWorkflowShortcutAction(.rateZero)
        XCTAssertEqual(first.rating, 0)
    }

    func testPhotoNavigationUsesInteractionScopeOrderAndSkipsHiddenFrames() {
        let model = AppModel(workflowShortcutStore: WorkflowShortcutStore(defaults: defaults))
        let first = ScanFrame(scanIndex: 1, rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-scope-1.tif"), filmType: .colorNegative)
        let hidden = ScanFrame(scanIndex: 2, rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-scope-hidden.tif"), filmType: .colorNegative)
        let last = ScanFrame(scanIndex: 3, rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-scope-3.tif"), filmType: .colorNegative)
        model.frames = [first, hidden, last]
        model.updateInteractionScope([last.id, first.id])
        model.selectFrame(last, orderedFrameIDs: [last.id, first.id], modifiers: [])

        XCTAssertFalse(model.canPerformWorkflowShortcutAction(.previousPhoto))
        XCTAssertTrue(model.canPerformWorkflowShortcutAction(.nextPhoto))

        model.performWorkflowShortcutAction(.nextPhoto)

        XCTAssertEqual(model.selectedFrameID, first.id)
        XCTAssertFalse(model.canPerformWorkflowShortcutAction(.nextPhoto))
        XCTAssertTrue(model.canPerformWorkflowShortcutAction(.previousPhoto))
        XCTAssertFalse(model.selectedFrameIDs.contains(hidden.id))
    }

    func testHiddenActiveFrameDisablesMutatingAndExportShortcuts() {
        let model = AppModel(workflowShortcutStore: WorkflowShortcutStore(defaults: defaults))
        let visible = ScanFrame(scanIndex: 1, rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-visible.tif"), filmType: .colorNegative)
        let hidden = ScanFrame(scanIndex: 2, rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-hidden.tif"), filmType: .colorNegative)
        hidden.hasDevelopedOnce = true
        model.frames = [visible, hidden]
        model.updateInteractionScope([visible.id])
        model.selectedFrameID = hidden.id

        XCTAssertNil(model.actionableFrame)
        XCTAssertFalse(model.canPerformWorkflowShortcutAction(.rateFive))
        XCTAssertFalse(model.canPerformWorkflowShortcutAction(.deletePhoto))
        XCTAssertFalse(model.canPerformWorkflowShortcutAction(.rotateRight))
        XCTAssertFalse(model.canPerformWorkflowShortcutAction(.quickExport))

        model.performWorkflowShortcutAction(.rateFive)
        model.performWorkflowShortcutAction(.rotateRight)
        model.performWorkflowShortcutAction(.deletePhoto)

        XCTAssertEqual(hidden.rating, 0)
        XCTAssertEqual(hidden.imageTransform.rotation, .deg0)
        XCTAssertEqual(model.frames.map(\.id), [visible.id, hidden.id])
    }

    func testAppModelPerformsExpandedWorkflowShortcutActions() {
        let store = WorkflowShortcutStore(defaults: defaults)
        let model = AppModel(workflowShortcutStore: store)
        let first = ScanFrame(scanIndex: 1, rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-1.tif"), filmType: .colorNegative)
        let second = ScanFrame(scanIndex: 2, rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-2.tif"), filmType: .colorNegative)
        first.params.exposure = 0.35
        second.params.exposure = -0.2
        model.frames = [first, second]
        model.selectedFrameID = first.id

        model.performWorkflowShortcutAction(.loadScanner)
        XCTAssertTrue(model.showScannerControls)

        model.performWorkflowShortcutAction(.copyDevelopSettings)
        XCTAssertNotNil(model.copiedDevelopSettings)

        model.selectedFrameID = second.id
        model.performWorkflowShortcutAction(.pasteDevelopSettings)
        XCTAssertEqual(second.params.exposure, first.params.exposure)

        model.performWorkflowShortcutAction(.rotateRight)
        XCTAssertEqual(second.imageTransform.rotation, .deg90)

        model.performWorkflowShortcutAction(.rotateLeft)
        XCTAssertEqual(second.imageTransform.rotation, .deg0)

        model.performWorkflowShortcutAction(.flipHorizontal)
        XCTAssertTrue(second.imageTransform.flipHorizontal)

        model.performWorkflowShortcutAction(.flipVertical)
        XCTAssertTrue(second.imageTransform.flipVertical)

        model.performWorkflowShortcutAction(.deletePhoto)
        XCTAssertEqual(model.frames.map(\.id), [first.id])
    }

    func testPhotoWorkflowShortcutsRemainAvailableDuringScannerScan() {
        let model = AppModel(workflowShortcutStore: WorkflowShortcutStore(defaults: defaults))
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-scan-concurrency.tif"),
            filmType: .colorNegative
        )
        frame.params.exposure = 0.4
        model.frames = [frame]
        model.selectedFrameID = frame.id
        frame.hasDevelopedOnce = true
        model.isScanning = true

        for action in [
            WorkflowShortcutAction.autoTone,
            .autoWhiteBalance,
            .resetAdjustments,
            .copyDevelopSettings,
            .rotateLeft,
            .rotateRight,
            .flipHorizontal,
            .flipVertical,
            .quickExport,
            .exportPhoto,
        ] {
            XCTAssertTrue(model.canPerformWorkflowShortcutAction(action), "\(action)")
        }
        XCTAssertFalse(model.canPerformWorkflowShortcutAction(.detectScanners))

        model.performWorkflowShortcutAction(.copyDevelopSettings)
        XCTAssertNotNil(model.copiedDevelopSettings)
        XCTAssertTrue(model.canPerformWorkflowShortcutAction(.pasteDevelopSettings))

        model.performWorkflowShortcutAction(.rotateRight)
        XCTAssertEqual(frame.imageTransform.rotation, .deg90)
        model.performWorkflowShortcutAction(.resetAdjustments)
        XCTAssertEqual(frame.params.exposure, 0)
    }

    func testScannerSetupEntryPointsDoNotRequireConnectedHardware() {
        let model = AppModel(workflowShortcutStore: WorkflowShortcutStore(defaults: defaults))
        XCTAssertFalse(model.hasConnectedScanner)
        XCTAssertFalse(model.showScannerControls)

        model.performWorkflowShortcutAction(.loadScanner)
        XCTAssertTrue(model.showScannerControls)

        model.showScannerControls = false
        model.performWorkflowShortcutAction(.toggleScannerSimulator)
        XCTAssertTrue(model.demoMode)
        XCTAssertTrue(model.showScannerControls)
        XCTAssertTrue(model.hasScanner)

        model.performWorkflowShortcutAction(.toggleScannerSimulator)
        XCTAssertFalse(model.demoMode)
        XCTAssertTrue(model.showScannerControls)
    }

    func testScannerAppConflictsRecognizeExternalScannerApps() {
        XCTAssertEqual(
            AppModel.scannerAppConflicts(in: ["Finder", "SilverFast 9", "com.hamrick.vuescan"]),
            ["SilverFast", "VueScan"]
        )
        XCTAssertTrue(AppModel.scannerAppConflicts(in: ["Finder", "negaflowApp"]).isEmpty)
    }
}
