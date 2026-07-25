import Chromabase
import XCTest
@testable import negaflowApp

@MainActor
final class PrintWorkspaceSettingsStoreTests: XCTestCase {
    func testSettingsPersistAndProduceValidComposition() {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrintWorkspaceSettingsStore(defaults: defaults)
        store.paperSize = .eightByTen
        store.orientation = .landscape
        store.marginMM = 12
        store.perforationStyle = .thirtyFiveMillimeter
        store.layoutMode = .customPackage
        store.packageSettings = PrintPackageSettings(
            mode: .customPackage,
            contentMode: .fill,
            customItems: [
                PrintCustomPackageItem(
                    sourceIndex: 0,
                    normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
                ),
            ],
            captionMode: .fileName,
            showsCropMarks: true
        )

        let restored = PrintWorkspaceSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.paperSize, .eightByTen)
        XCTAssertEqual(restored.orientation, .landscape)
        XCTAssertEqual(restored.marginMM, 12)
        XCTAssertEqual(restored.perforationStyle, .thirtyFiveMillimeter)
        XCTAssertEqual(restored.layoutMode, .customPackage)
        XCTAssertEqual(restored.packageSettings, store.packageSettings)
        XCTAssertEqual(restored.effectivePackageSettings()?.mode, .customPackage)
        XCTAssertEqual(restored.compositionSettings(dpi: 0).dpi, 300)
        XCTAssertTrue(restored.compositionSettings(dpi: 300).isValid)
    }

    func testMarginIsClampedToRendererContract() {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrintWorkspaceSettingsStore(defaults: defaults)

        store.marginMM = 75

        XCTAssertEqual(store.marginMM, 50)
        XCTAssertEqual(PrintWorkspaceSettingsStore(defaults: defaults).marginMM, 50)
    }

    func testSingleImageModeDoesNotProducePackageSettings() {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrintWorkspaceSettingsStore(defaults: defaults)

        store.layoutMode = .singleImage

        XCTAssertNil(store.effectivePackageSettings())
    }

    func testCorruptPersistedPackageFallsBackWithoutRewritingOtherSettings() {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(PrintWorkspaceLayoutMode.contactSheet.rawValue, forKey: "print.layoutMode")
        defaults.set(Data("not-json".utf8), forKey: "print.packageSettings")

        let store = PrintWorkspaceSettingsStore(defaults: defaults)

        XCTAssertEqual(store.layoutMode, .contactSheet)
        XCTAssertEqual(store.packageSettings, PrintPackageSettings())
        XCTAssertEqual(store.effectivePackageSettings()?.mode, .contactSheet)
    }

    func testEffectiveCustomPackageClampsSourcesWithoutChangingStoredAssignment() throws {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrintWorkspaceSettingsStore(defaults: defaults)
        store.layoutMode = .customPackage
        store.packageSettings = PrintPackageSettings(
            mode: .customPackage,
            customItems: [
                PrintCustomPackageItem(
                    sourceIndex: 2,
                    normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
                ),
            ]
        )

        let oneSource = try XCTUnwrap(store.effectivePackageSettings(sourceCount: 1))
        XCTAssertEqual(oneSource.customItems[0].sourceIndex, 0)
        XCTAssertEqual(store.packageSettings.customItems[0].sourceIndex, 2)

        let restoredSources = try XCTUnwrap(store.effectivePackageSettings(sourceCount: 3))
        XCTAssertEqual(restoredSources.customItems[0].sourceIndex, 2)
        XCTAssertEqual(store.packageSettings.customItems[0].sourceIndex, 2)
    }
}
