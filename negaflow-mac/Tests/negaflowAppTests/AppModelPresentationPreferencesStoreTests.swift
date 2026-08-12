import AppKit
import Combine
import SwiftUI
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

    /// 캔버스 위 컨트롤(비교 토글·줌 캡슐)은 앱 외형이 아니라 캔버스 배경의 반대색으로 그린다.
    /// 흰 배경 + 다크 모드에서 흰 글자가 흰 바탕에 얹혀 컨트롤이 통째로 사라진 적이 있다.
    func testCanvasHUDColorsContrastWithEveryCanvasBackground() {
        for background in CanvasBackground.allCases {
            let canvas = luminance(background.color)
            let content = luminance(background.hudContentColor)
            let surface = luminance(background.hudSurfaceColor)
            XCTAssertGreaterThan(
                abs(content - canvas), 0.4,
                "\(background.rawValue): 글자/아이콘이 배경의 반대쪽 밝기여야 한다."
            )
            XCTAssertGreaterThan(
                abs(content - surface), 0.5,
                "\(background.rawValue): 글자/아이콘이 컨트롤 판과 충분히 대비돼야 한다."
            )
            XCTAssertGreaterThan(
                abs(surface - canvas), 0.1,
                "\(background.rawValue): 컨트롤 판이 배경과 구분돼야 한다."
            )
        }
    }

    private func luminance(_ color: Color) -> Double {
        let converted = NSColor(color).usingColorSpace(.sRGB)
        return Double(converted?.brightnessComponent ?? 0)
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
