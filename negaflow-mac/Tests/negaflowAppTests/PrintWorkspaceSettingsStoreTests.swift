import Chromabase
import XCTest
@testable import negaflowApp

@MainActor
final class PrintWorkspaceSettingsStoreTests: XCTestCase {
    func testContactSheetDefaultsUseBlackSixBySevenGridWithTwoMillimeterGaps() {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PrintWorkspaceSettingsStore(defaults: defaults)
        store.layoutMode = .contactSheet
        let package = store.packageSettings

        XCTAssertEqual(store.sheetColor, .black)
        XCTAssertEqual(store.effectivePackageSettings()?.contactSheetBackground, .black)
        XCTAssertEqual(package.contactSheetBackground, .black)
        XCTAssertEqual(package.contactColumns, 6)
        XCTAssertEqual(package.contactRows, 7)
        XCTAssertEqual(package.horizontalSpacingMM, 2)
        XCTAssertEqual(package.verticalSpacingMM, 2)
    }

    func testEveryLayoutUsesRequestedSheetAndSurfaceDefaults() {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrintWorkspaceSettingsStore(defaults: defaults)

        XCTAssertEqual(store.paperSurface, .matte)
        for mode in PrintWorkspaceLayoutMode.allCases {
            store.layoutMode = mode
            XCTAssertEqual(
                store.sheetColor,
                mode == .contactSheet ? .black : .white,
                "unexpected default for \(mode)"
            )
            XCTAssertEqual(
                store.compositionSettings(dpi: 300).sheetBackground,
                mode == .contactSheet ? .black : .white
            )
            if let package = store.effectivePackageSettings(sourceCount: 1) {
                XCTAssertEqual(
                    package.contactSheetBackground,
                    mode == .contactSheet ? .black : .white
                )
            }
        }
    }

    func testSheetColorPersistsIndependentlyForEachLayout() {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrintWorkspaceSettingsStore(defaults: defaults)

        store.layoutMode = .singleImage
        store.sheetColor = .gray
        store.layoutMode = .contactSheet
        store.sheetColor = .white
        store.layoutMode = .cyanotype
        store.sheetColor = .black

        let restored = PrintWorkspaceSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.layoutMode, .cyanotype)
        XCTAssertEqual(restored.sheetColor, .black)
        restored.layoutMode = .singleImage
        XCTAssertEqual(restored.sheetColor, .gray)
        restored.layoutMode = .contactSheet
        XCTAssertEqual(restored.sheetColor, .white)
        restored.layoutMode = .picturePackage
        XCTAssertEqual(restored.sheetColor, .white)
    }

    func testRulerAndSurfaceDefaultsAndPersistence() {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrintWorkspaceSettingsStore(defaults: defaults)

        XCTAssertFalse(store.showsRulers)
        XCTAssertEqual(store.rulerUnit, .inches)
        XCTAssertEqual(store.paperSurface, .matte)

        store.showsRulers = true
        store.rulerUnit = .centimeters
        store.paperSurface = .silk

        let restored = PrintWorkspaceSettingsStore(defaults: defaults)
        XCTAssertTrue(restored.showsRulers)
        XCTAssertEqual(restored.rulerUnit, .centimeters)
        XCTAssertEqual(restored.paperSurface, .silk)
    }

    func testLegacyCPrintSurfaceMigratesToCommonSurface() {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(PrintPaperSurface.glossy.rawValue, forKey: "print.cPrint.paperSurface")

        XCTAssertEqual(
            PrintWorkspaceSettingsStore(defaults: defaults).paperSurface,
            .glossy
        )
    }

    /// "사진 한 장씩 반복"이 켜져 있으면 콘택트 시트는 선택한 나머지를 버리고 첫 장만 채운다.
    /// 다음 실행까지 살아남으면 다중 선택이 사라진 것처럼 보이므로 언제나 꺼진 채로 시작한다.
    func testRepeatOnePhotoPerPageAlwaysStartsOff() {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrintWorkspaceSettingsStore(defaults: defaults)
        store.layoutMode = .contactSheet
        var package = store.packageSettings
        package.repeatOnePhotoPerPage = true
        store.packageSettings = package
        XCTAssertTrue(store.packageSettings.repeatOnePhotoPerPage)

        let reloaded = PrintWorkspaceSettingsStore(defaults: defaults)

        XCTAssertFalse(reloaded.packageSettings.repeatOnePhotoPerPage)
        // 나머지 레이아웃 설정은 그대로 복원돼야 한다.
        XCTAssertEqual(reloaded.layoutMode, .contactSheet)
        XCTAssertEqual(reloaded.packageSettings.contactRows, package.contactRows)
        XCTAssertEqual(reloaded.packageSettings.contactColumns, package.contactColumns)
    }

    func testContactSheetGeometryClampsImpossibleGapsWithoutChangingCounts() throws {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrintWorkspaceSettingsStore(defaults: defaults)
        store.layoutMode = .contactSheet
        store.paperSize = .fourBySix
        store.orientation = .portrait
        store.marginMM = 50
        store.packageSettings = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 12,
            contactColumns: 12,
            horizontalSpacingMM: 25,
            verticalSpacingMM: 25
        )

        XCTAssertEqual(store.packageSettings.contactRows, 12)
        XCTAssertEqual(store.packageSettings.contactColumns, 12)
        XCTAssertLessThan(store.packageSettings.horizontalSpacingMM, 25)
        XCTAssertLessThan(store.packageSettings.verticalSpacingMM, 25)
        XCTAssertNotNil(PrintPackageLayout.make(
            sourceSizes: [CGSize(width: 3, height: 2)],
            composition: store.compositionSettings(dpi: 300),
            package: try XCTUnwrap(store.effectivePackageSettings(sourceCount: 1))
        ))
    }

    func testLegacyPackageWithoutAppearanceKeysRestoresSafeDefaults() throws {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let encoded = try JSONEncoder().encode(PrintPackageSettings())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "contactSheetBackground")
        object.removeValue(forKey: "captionAlignment")
        object.removeValue(forKey: "captionFontName")
        object.removeValue(forKey: "customCaptions")
        defaults.set(
            try JSONSerialization.data(withJSONObject: object),
            forKey: "print.packageSettings"
        )

        let package = PrintWorkspaceSettingsStore(defaults: defaults).packageSettings

        XCTAssertEqual(package.contactSheetBackground, .black)
        XCTAssertEqual(package.captionAlignment, .leading)
        XCTAssertEqual(package.captionFontName, "Helvetica")
        XCTAssertEqual(package.customCaptions.count, 1)
    }

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
            captionFontName: "Courier",
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

    func testCaptionFontNameMustBeNonempty() {
        XCTAssertFalse(PrintPackageSettings(captionFontName: "").isValid)
        XCTAssertFalse(PrintPackageSettings(captionFontName: "   ").isValid)
        XCTAssertTrue(PrintPackageSettings(captionFontName: "Courier").isValid)
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

    func testHistoricalProcessLayoutsUseIndependentPagesAndMatchingCompositionStyle() {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrintWorkspaceSettingsStore(defaults: defaults)
        let expectations: [(PrintWorkspaceLayoutMode, PrintPresentationStyle)] = [
            (.cyanotype, .cyanotype),
            (.glassPlate, .glassPlate),
            (.gelatin, .gelatinSilver),
        ]

        for (layoutMode, presentationStyle) in expectations {
            store.layoutMode = layoutMode

            XCTAssertTrue(layoutMode.usesIndividualPages)
            XCTAssertTrue(layoutMode.usesVerticalPageStack(sourceCount: 39))
            XCTAssertFalse(layoutMode.usesVerticalPageStack(sourceCount: 1))
            XCTAssertNil(store.effectivePackageSettings(sourceCount: 39))
            XCTAssertEqual(
                store.compositionSettings(dpi: 300).presentationStyle,
                presentationStyle
            )
        }
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

    func testDefaultCustomPackagePlacesEverySelectedSourceOnOneEditablePage() throws {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrintWorkspaceSettingsStore(defaults: defaults)
        store.layoutMode = .customPackage

        store.prepareDefaultCustomPackage(sourceCount: 5)

        let package = try XCTUnwrap(store.effectivePackageSettings(sourceCount: 5))
        XCTAssertEqual(package.customItems.map(\.sourceIndex), Array(0..<5))
        XCTAssertEqual(Set(package.customItems.map(\.pageIndex)), [0])
        XCTAssertTrue(package.customItems.allSatisfy {
            $0.normalizedRect.minX >= 0
                && $0.normalizedRect.minY >= 0
                && $0.normalizedRect.maxX <= 1
                && $0.normalizedRect.maxY <= 1
        })
        XCTAssertEqual(
            PrintPackageLayout.expectedPageCount(sourceCount: 5, package: package),
            1
        )
    }

    func testPreparingDefaultCustomPackagePreservesUserLayout() {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrintWorkspaceSettingsStore(defaults: defaults)
        store.layoutMode = .customPackage
        let userItem = PrintCustomPackageItem(
            sourceIndex: 0,
            normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
        )
        store.packageSettings = PrintPackageSettings(
            mode: .customPackage,
            customItems: [userItem]
        )

        store.prepareDefaultCustomPackage(sourceCount: 5)

        XCTAssertEqual(store.packageSettings.customItems, [userItem])
    }

    func testCPrintDestinationAndProofSettingsPersist() throws {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let store = PrintWorkspaceSettingsStore(defaults: defaults)

        store.outputProcess = .cPrint
        store.cPrintLabName = "Example Lab"
        store.cPrintPaperName = "Example Paper"
        store.paperSurface = .lustre
        store.cPrintProofICCProfileData = profile.iccProfileData
        store.cPrintProofICCProfileName = profile.profileName
        store.cPrintPreviewEnabled = true
        store.cPrintPaperSimulationEnabled = true

        let restored = PrintWorkspaceSettingsStore(defaults: defaults)
        // 출력 방식은 기억하지 않는다 — C-Print 는 랩에 넘길 때만 켜는 특수 경로라 언제나
        // 일반 출력으로 시작한다. 랩/용지/프로파일 같은 부수 설정은 그대로 남는다.
        XCTAssertEqual(restored.outputProcess, .standard)
        XCTAssertEqual(restored.cPrintLabName, "Example Lab")
        XCTAssertEqual(restored.cPrintPaperName, "Example Paper")
        XCTAssertEqual(restored.paperSurface, .lustre)
        XCTAssertEqual(restored.cPrintProofICCProfileData, profile.iccProfileData)
        XCTAssertEqual(restored.cPrintProofICCProfileName, profile.profileName)
        XCTAssertTrue(restored.cPrintPreviewEnabled)
        XCTAssertTrue(restored.cPrintPaperSimulationEnabled)
    }

    func testInvalidCPrintICCDisablesRestoredPreview() {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-an-icc".utf8), forKey: "print.cPrint.proofICCProfileData")
        defaults.set("Invalid", forKey: "print.cPrint.proofICCProfileName")
        defaults.set(true, forKey: "print.cPrint.previewEnabled")

        let restored = PrintWorkspaceSettingsStore(defaults: defaults)

        XCTAssertNil(restored.cPrintProofICCProfileData)
        XCTAssertNil(restored.cPrintProofICCProfileName)
        XCTAssertFalse(restored.cPrintPreviewEnabled)
    }

    func testGenericRGBProofProfileRestoresWithoutPrinterTransformValidation() throws {
        let suiteName = "PrintWorkspaceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let data = try XCTUnwrap(SoftProof.profile(for: .displayP3)?.iccData)
        defaults.set(data, forKey: "print.cPrint.proofICCProfileData")
        defaults.set("Display P3", forKey: "print.cPrint.proofICCProfileName")
        defaults.set(true, forKey: "print.cPrint.previewEnabled")

        let restored = PrintWorkspaceSettingsStore(defaults: defaults)

        XCTAssertEqual(restored.cPrintProofICCProfileData, data)
        XCTAssertEqual(restored.cPrintProofICCProfileName, "Display P3")
        XCTAssertTrue(restored.cPrintPreviewEnabled)
    }
}
