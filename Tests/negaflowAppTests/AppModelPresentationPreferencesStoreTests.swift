import Combine
import XCTest
@testable import negaflowApp

@MainActor
final class AppModelPresentationPreferencesStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "negaflow.presentation-preferences.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testStorePersistsAppearanceAndCanvasBackgroundValues() {
        let store = PresentationPreferencesStore(defaults: defaults)

        store.appearanceMode = AppAppearanceMode.dark
        store.canvasBackground = CanvasBackground.white
        store.developerMode = true
        store.clippingOverlayEnabled = true
        store.developsImportsAutomatically = true

        let reloaded = PresentationPreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.appearanceMode, AppAppearanceMode.dark)
        XCTAssertEqual(reloaded.canvasBackground, CanvasBackground.white)
        XCTAssertTrue(reloaded.developerMode)
        XCTAssertTrue(reloaded.clippingOverlayEnabled)
        XCTAssertTrue(reloaded.developsImportsAutomatically)
    }

    func testStoreFallsBackForMissingOrInvalidDefaults() {
        defaults.set("not-an-appearance-mode", forKey: "appearanceMode")
        defaults.set("not-a-canvas-background", forKey: "canvasBackground")

        let store = PresentationPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.appearanceMode, AppAppearanceMode.system)
        XCTAssertEqual(store.canvasBackground, CanvasBackground.black)
        XCTAssertFalse(store.clippingOverlayEnabled)
        XCTAssertFalse(store.developsImportsAutomatically)
    }

    func testCanvasHUDContrastFollowsCanvasBackgroundInsteadOfAppAppearance() {
        XCTAssertEqual(CanvasBackground.black.hudColorScheme, .dark)
        XCTAssertEqual(CanvasBackground.gray.hudColorScheme, .light)
        XCTAssertEqual(CanvasBackground.white.hudColorScheme, .light)
    }

    func testAppModelFacadePublishesPresentationPreferenceChanges() {
        let store = PresentationPreferencesStore(defaults: defaults)
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            presentationPreferencesStore: store
        )
        var changeCount = 0
        let cancellable = model.objectWillChange.sink { changeCount += 1 }

        model.appearanceMode = AppAppearanceMode.light
        model.canvasBackground = CanvasBackground.gray
        model.clippingOverlayEnabled = true

        XCTAssertEqual(model.appearanceMode, AppAppearanceMode.light)
        XCTAssertEqual(model.canvasBackground, CanvasBackground.gray)
        XCTAssertEqual(store.appearanceMode, AppAppearanceMode.light)
        XCTAssertEqual(store.canvasBackground, CanvasBackground.gray)
        XCTAssertTrue(model.clippingOverlayEnabled)
        XCTAssertTrue(store.clippingOverlayEnabled)
        XCTAssertGreaterThanOrEqual(changeCount, 1)
        withExtendedLifetime(cancellable) {}
    }

    func testClippingToggleRequestsOnlySelectedDevelopedFrame() async throws {
        let store = PresentationPreferencesStore(defaults: defaults)
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            presentationPreferencesStore: store
        )
        let selected = makeFrame(index: 1)
        let other = makeFrame(index: 2)
        model.frames = [selected, other]
        model.selectedFrameID = selected.id
        selected.hasDevelopedOnce = true
        other.hasDevelopedOnce = true

        model.clippingOverlayEnabled = true

        let deadline = Date().addingTimeInterval(1)
        while selected.developRevision == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(selected.developRevision, 1)
        XCTAssertEqual(other.developRevision, 0)
    }

    func testExportSettingsTabMountsColorManagementWithoutRemovingExistingTabs() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("Sources/negaflowApp/Settings/AppSettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("ColorManagementSettingsSection()"))
        for tabKey in [
            ".settingsGeneralTab", ".settingsInterfaceTab", ".settingsWorkflowTab",
            ".settingsScanTab", ".settingsDiskTab", ".settingsExportTab",
            ".settingsShortcutsTab", ".settingsLegalTab",
        ] {
            XCTAssertTrue(source.contains(tabKey), "설정 탭 누락: \(tabKey)")
        }
    }

    private func makeFrame(index: Int) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("negaflow-clipping-refresh-\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
    }
}
