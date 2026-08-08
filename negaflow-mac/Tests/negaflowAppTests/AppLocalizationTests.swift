import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class AppLocalizationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "negaflow.localization.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testLanguagePreferencePersistsAndChangesApplicationText() {
        let store = PresentationPreferencesStore(defaults: defaults)
        store.appLanguage = .korean

        let reloaded = PresentationPreferencesStore(defaults: defaults)
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            presentationPreferencesStore: reloaded
        )

        XCTAssertEqual(reloaded.appLanguage, .korean)
        XCTAssertEqual(model.text(.commandImportImages), "이미지 가져오기")

        model.appLanguage = .english

        XCTAssertEqual(model.text(.commandImportImages), "Import Photos")
        XCTAssertEqual(model.text(.settingsLanguageTab), "Language")
    }

    func testHistoricalPrintLayoutNamesAreLocalized() {
        XCTAssertEqual(AppLocalization.text(.printCyanotype, language: .korean), "시아노타입")
        XCTAssertEqual(AppLocalization.text(.printGlassPlate, language: .korean), "유리건판")
        XCTAssertEqual(AppLocalization.text(.printGelatin, language: .korean), "젤라틴")
        XCTAssertEqual(AppLocalization.text(.printGelatin, language: .english), "Gelatin Silver")
    }

    func testAboutAnniversaryMessageMatchesLocalizedReadmes() {
        let expected: [AppLanguage: String] = [
            .english: "Celebrating this summer, the bicentennial of Niépce's first-ever photograph.",
            .korean: "니엡스가 찍은 최초의 사진으로부터 200주년인 올해 여름을 기념하며.",
            .japanese: "ニエプスが人類最初の一枚を写してから二百年。その夏に寄せて。",
            .simplifiedChinese: "谨以此夏，纪念尼埃普斯拍下人类第一张照片二百周年。",
            .french: "Célébrons cet été le bicentenaire de la toute première photographie de Niépce.",
            .german: "Diesem Sommer gewidmet — zweihundert Jahre seit Niépces erster Fotografie.",
        ]

        for (language, message) in expected {
            XCTAssertEqual(
                AppLocalization.text(.aboutAnniversaryMessage, language: language),
                message
            )
        }
    }

    func testMenuCatalogUsesProfessionalPhotoWorkflowSections() {
        let menus = AppMenuCatalog(language: .english).menus

        XCTAssertEqual(
            menus.map(\.title),
            ["File", "Edit", "View", "Window", "Help", "Library", "Photo", "Develop", "Scanner", "Export"]
        )
        XCTAssertTrue(menus.first { $0.title == "File" }?.commands.map(\.title).contains("Import Photos") == true)
        XCTAssertTrue(menus.first { $0.title == "Edit" }?.commands.map(\.title).contains("Copy Develop Settings") == true)
        XCTAssertTrue(menus.first { $0.title == "View" }?.commands.map(\.title).contains("Enter Full Screen") == true)
        XCTAssertTrue(menus.first { $0.title == "Window" }?.commands.map(\.title).contains("Settings") == true)
        XCTAssertTrue(menus.first { $0.title == "Help" }?.commands.map(\.title).contains("Keyboard Shortcuts") == true)
    }

    func testSupportedLanguagesCoverRequestedSettingsLanguages() {
        XCTAssertEqual(
            AppLanguage.allCases.map(\.rawValue),
            ["system", "en", "ko", "ja", "zh-Hans", "fr", "de"]
        )
    }

    func testEverySupportedLanguageHasAllCurrentKeys() {
        for language in AppLanguage.allCases where language != .system {
            for key in AppLocalizedText.allCases {
                XCTAssertTrue(
                    AppLocalization.hasTranslation(key, language: language),
                    "\(language.rawValue) is missing \(key)"
                )
            }
        }
    }

    func testEverySupportedLanguageHasAllPhraseKeys() {
        for language in AppLanguage.allCases where language != .system {
            for key in AppLocalizedPhrase.allCases {
                XCTAssertTrue(
                    AppLocalization.hasTranslation(key, language: language),
                    "\(language.rawValue) is missing phrase \(key)"
                )
            }
        }
    }

    func testPhraseTranslationsChangeWithLanguageSelection() {
        XCTAssertEqual(AppLocalization.text(.userPreset, language: .english), "User Preset")
        XCTAssertEqual(AppLocalization.text(.userPreset, language: .korean), "사용자 프리셋")
        XCTAssertEqual(AppLocalization.text(.userPreset, language: .japanese), "ユーザープリセット")
        XCTAssertEqual(AppLocalization.text(.userPreset, language: .simplifiedChinese), "用户预设")
        XCTAssertEqual(AppLocalization.text(.userPreset, language: .french), "Paramètre prédéfini utilisateur")
        XCTAssertEqual(AppLocalization.text(.userPreset, language: .german), "Benutzervorgabe")
    }

    func testGrainMendBrandIsFixedAndModeLabelsAreLocalized() {
        let expectedModes: [AppLanguage: [String]] = [
            .english: ["Auto", "Guided", "Brush"],
            .korean: ["자동", "가이드", "브러시"],
            .japanese: ["自動", "ガイド", "ブラシ"],
            .simplifiedChinese: ["自动", "引导", "画笔"],
            .french: ["Auto", "Guidé", "Pinceau"],
            .german: ["Auto", "Geführt", "Pinsel"],
        ]

        for (language, modes) in expectedModes {
            XCTAssertEqual(
                AppLocalization.text(.inspectorTabDefect, language: language),
                "GrainMend"
            )
            XCTAssertEqual(
                [
                    AppLocalization.text(.autoDefect, language: language),
                    AppLocalization.text(.guidedDefect, language: language),
                    AppLocalization.text(.brushDefect, language: language),
                ],
                modes
            )
            XCTAssertTrue(
                AppLocalization.format(.grainMendIREditTitleFormat, language: language, 1)
                    .hasPrefix("GrainMend · IR ·")
            )
        }
    }

    func testCanvasBackgroundMenuUsesCompleteLocalizedLabels() {
        let expected: [AppLanguage: (title: String, colors: [String])] = [
            .english: ("Background Color", ["Black", "Gray", "White"]),
            .korean: ("배경색", ["검정", "회색", "흰색"]),
            .japanese: ("背景色", ["ブラック", "グレー", "ホワイト"]),
            .simplifiedChinese: ("背景颜色", ["黑色", "灰色", "白色"]),
            .french: ("Couleur d'arrière-plan", ["Noir", "Gris", "Blanc"]),
            .german: ("Hintergrundfarbe", ["Schwarz", "Grau", "Weiß"]),
        ]

        for (language, labels) in expected {
            XCTAssertEqual(
                AppLocalization.text(.canvasBackgroundMenu, language: language),
                labels.title
            )
            XCTAssertEqual(
                CanvasBackground.allCases.map { $0.label(language: language) },
                labels.colors
            )
        }
    }

    func testLibraryViewModeCapsuleUsesCompactLocalizedLabels() {
        // 캡슐 순서 = LibraryViewMode 선언 순서. 폴더별이 먼저이고 전체가 맨 뒤다.
        let expected: [AppLanguage: [String]] = [
            .english: ["Folders", "Film Type", "Offline", "All"],
            .korean: ["폴더별", "필름 종류", "오프라인", "전체"],
            .japanese: ["フォルダー", "フィルムタイプ", "オフライン", "すべて"],
            .simplifiedChinese: ["文件夹", "胶片类型", "离线", "全部"],
            .french: ["Dossiers", "Type de film", "Hors ligne", "Toutes"],
            .german: ["Ordner", "Filmtyp", "Offline", "Alle"],
        ]

        for (language, labels) in expected {
            XCTAssertEqual(
                LibraryViewMode.allCases.map { $0.capsuleDisplayName(language: language) },
                labels
            )
        }

        XCTAssertEqual(
            FilmType.allCases.map { $0.displayName(language: .korean) },
            ["컬러 네거티브", "슬라이드", "흑백 네거티브", "흑백 포지티브"]
        )
    }

    func testImportSidebarUsesSingleWordLabels() {
        XCTAssertEqual(AppLocalization.text(.importImageShort, language: .english), "Image")
        XCTAssertEqual(AppLocalization.text(.importFolderShort, language: .english), "Folder")
        XCTAssertEqual(AppLocalization.text(.scannerLabel, language: .english), "Scanner")
        XCTAssertEqual(AppLocalization.text(.importImageShort, language: .korean), "이미지")
        XCTAssertEqual(AppLocalization.text(.importFolderShort, language: .korean), "폴더")
        XCTAssertEqual(AppLocalization.text(.scannerLabel, language: .korean), "스캐너")
    }

    func testScanFolderAndDevelopProcessLabelsAreLocalized() {
        XCTAssertEqual(AppLocalization.text(.scanFolderName, language: .english), "Folder Name")
        XCTAssertEqual(AppLocalization.text(.scanFolderName, language: .korean), "폴더명")
        XCTAssertEqual(AppLocalization.text(.chooseScanFolder, language: .japanese), "スキャンフォルダを選択")
        XCTAssertEqual(AppLocalization.text(.process, language: .simplifiedChinese), "冲洗工艺")
        XCTAssertEqual(AppLocalization.text(.target, language: .korean), "타깃")
    }

    func testFilmTypesExposeDevelopmentProcessNames() {
        XCTAssertEqual(FilmType.colorNegative.developmentProcessName, "C-41/ECN-2")
        XCTAssertEqual(FilmType.colorPositive.developmentProcessName, "E-6")
        XCTAssertEqual(FilmType.bwNegative.developmentProcessName, "D-76")
        XCTAssertEqual(FilmType.bwPositive.developmentProcessName, "B&W Reversal")
    }

    func testScannerProfileValidationStatusesAreLocalized() {
        XCTAssertEqual(
            ScannerProfileValidationStatus.draft.displayName(language: .korean),
            "초안"
        )
        XCTAssertEqual(
            ScannerProfileValidationStatus.realOnly.displayName(language: .english),
            "Real Scans"
        )
        XCTAssertEqual(
            ScannerProfileValidationStatus.pairedSmoke.displayName(language: .japanese),
            "ペア試験"
        )
        XCTAssertEqual(
            ScannerProfileValidationStatus.pairedValidated.displayName(language: .german),
            "Paarweise validiert"
        )
    }

    func testLibrarySearchAndFilterPhrasesUseExactEnglishAndKoreanCopy() {
        XCTAssertEqual(AppLocalization.text(.librarySearchPlaceholder, language: .english), "Search Photos")
        XCTAssertEqual(AppLocalization.text(.libraryClearSearch, language: .english), "Clear Search")
        XCTAssertEqual(AppLocalization.format(.libraryResultCountFormat, language: .english, 12, 40), "12 of 40 photos")
        XCTAssertEqual(AppLocalization.text(.filterCurrentRoll, language: .english), "Current Roll")
        XCTAssertEqual(AppLocalization.format(.filterMinimumRatingFormat, language: .english, 3), "3 Stars & Up")
        XCTAssertEqual(AppLocalization.text(.filterInfrared, language: .english), "Infrared")
        XCTAssertEqual(AppLocalization.text(.filterDefectRecipe, language: .english), "Repair Recipe")
        XCTAssertEqual(AppLocalization.text(.filterUnvalidatedProfile, language: .english), "Unvalidated Profile")
        XCTAssertEqual(AppLocalization.text(.filterMetadataUnknown, language: .english), "Metadata Status Unknown")
        XCTAssertEqual(AppLocalization.text(.libraryFilters, language: .english), "Filters")
        XCTAssertEqual(AppLocalization.text(.clearFilters, language: .english), "Clear Filters")
        XCTAssertEqual(AppLocalization.text(.exportFileSettings, language: .english), "File")
        XCTAssertEqual(AppLocalization.text(.exportQualitySettings, language: .english), "Quality")
        XCTAssertEqual(AppLocalization.text(.exportSourceSettings, language: .english), "Source")
        XCTAssertEqual(AppLocalization.text(.noMatchingPhotos, language: .english), "No Matching Photos")

        XCTAssertEqual(AppLocalization.text(.librarySearchPlaceholder, language: .korean), "사진 검색")
        XCTAssertEqual(AppLocalization.text(.libraryClearSearch, language: .korean), "검색 지우기")
        XCTAssertEqual(AppLocalization.format(.libraryResultCountFormat, language: .korean, 12, 40), "사진 12장 / 전체 40장")
        XCTAssertEqual(AppLocalization.text(.filterCurrentRoll, language: .korean), "현재 롤")
        XCTAssertEqual(AppLocalization.format(.filterMinimumRatingFormat, language: .korean, 3), "별점 3 이상")
        XCTAssertEqual(AppLocalization.text(.filterInfrared, language: .korean), "적외선")
        XCTAssertEqual(AppLocalization.text(.filterDefectRecipe, language: .korean), "보정 레시피")
        XCTAssertEqual(AppLocalization.text(.filterUnvalidatedProfile, language: .korean), "미검증 프로파일")
        XCTAssertEqual(AppLocalization.text(.filterMetadataUnknown, language: .korean), "메타데이터 상태 미확인")
        XCTAssertEqual(AppLocalization.text(.libraryFilters, language: .korean), "필터")
        XCTAssertEqual(AppLocalization.text(.clearFilters, language: .korean), "필터 지우기")
        XCTAssertEqual(AppLocalization.text(.exportFileSettings, language: .korean), "파일")
        XCTAssertEqual(AppLocalization.text(.exportQualitySettings, language: .korean), "품질")
        XCTAssertEqual(AppLocalization.text(.exportSourceSettings, language: .korean), "소스")
        XCTAssertEqual(AppLocalization.text(.noMatchingPhotos, language: .korean), "일치하는 사진 없음")
    }

    func testStringCatalogPluralCountsAcrossSupportedLanguages() {
        let expected: [AppLanguage: [String]] = [
            .english: ["0 frames", "1 frame", "2 frames", "20 frames"],
            .korean: ["0장", "1장", "2장", "20장"],
            .japanese: ["0コマ", "1コマ", "2コマ", "20コマ"],
            .simplifiedChinese: ["0 张", "1 张", "2 张", "20 张"],
            .french: ["0 image", "1 image", "2 images", "20 images"],
            .german: ["0 Bilder", "1 Bild", "2 Bilder", "20 Bilder"]
        ]
        for (language, localizedCounts) in expected {
            XCTAssertEqual(
                [0, 1, 2, 20].map {
                    AppLocalization.format(.frameCountFormat, language: language, $0)
                },
                localizedCounts,
                language.rawValue
            )
        }

        XCTAssertEqual(
            AppLocalization.format(.defectsCountFormat, language: .english, 1),
            "1 defect"
        )
        XCTAssertEqual(
            AppLocalization.format(.defectsCountFormat, language: .english, 2),
            "2 defects"
        )
    }

    func testLibraryMetadataUnknownFilterNeverClaimsMetadataIsAbsent() {
        let absentClaims = [
            "No Metadata", "메타데이터 없음", "メタデータなし", "无元数据",
            "Aucune métadonnée", "Keine Metadaten"
        ]

        for language in AppLanguage.allCases where language != .system {
            let value = AppLocalization.text(.filterMetadataUnknown, language: language)
            XCTAssertFalse(absentClaims.contains(value), "\(language.rawValue) must describe unknown metadata state")
        }
    }

    func testKoreanProductTerminologyUsesPhotoEditingLabels() {
        XCTAssertEqual(AppLocalization.text(.commandScanFrame, language: .korean), "사진 스캔")
        XCTAssertEqual(AppLocalization.text(.raw, language: .korean), "원본")
        XCTAssertEqual(AppLocalization.text(.geometry, language: .korean), "편집")
        XCTAssertEqual(AppLocalization.text(.multiExposure, language: .korean), "다중 노출")
        XCTAssertEqual(AppLocalization.text(.bitDepth, language: .korean), "심도")
        XCTAssertEqual(AppLocalization.format(.frameDisplayFormat, language: .korean, 7), "사진 7")
        XCTAssertEqual(AppLocalization.text(.history, language: .korean), "기록")
        XCTAssertEqual(AppLocalization.text(.snapshot, language: .korean), "스냅샷")
        XCTAssertEqual(AppLocalization.text(.virtualCopy, language: .korean), "가상 사본")
        XCTAssertEqual(AppLocalization.text(.colorScannerInput, language: .korean), "스캐너 에뮬레이션")
        XCTAssertEqual(
            AppLocalization.text(.colorScannerInputReason, language: .korean),
            "선택된 스캐너 에뮬레이션 룩이 없습니다."
        )
    }

    func testDevelopTargetLabelsUseCompactProductNames() {
        XCTAssertEqual(AppLocalization.text(.developTargetMain, language: .english), "MAIN")
        XCTAssertEqual(AppLocalization.text(.developTargetPrint, language: .korean), "PRINT")
        XCTAssertEqual(DevelopTarget.main.displayName, "MAIN")
        XCTAssertEqual(DevelopTarget.print.displayName, "PRINT")
        XCTAssertEqual(DevelopTarget.noritsu.displayName, "HS")
        XCTAssertEqual(DevelopTarget.sp3000.displayName, "SP")
        XCTAssertEqual(DevelopTarget.f135.displayName, "F135")
        XCTAssertEqual(DevelopTarget.hr.displayName, "HR")
    }

    func testAdjustmentTerminologyMatchesNativePhotoSoftware() {
        XCTAssertEqual(AppLocalization.text(.whites, language: .korean), "흰색 계열")
        XCTAssertEqual(AppLocalization.text(.blacks, language: .korean), "검정 계열")
        XCTAssertEqual(AppLocalization.text(.toneHighlights, language: .korean), "밝은 영역")
        XCTAssertEqual(AppLocalization.text(.shadows, language: .korean), "어두운 영역")
        XCTAssertEqual(AppLocalization.text(.toneCurve, language: .korean), "톤 곡선")
        XCTAssertEqual(AppLocalization.text(.clarity, language: .korean), "부분 대비")
        XCTAssertEqual(AppLocalization.text(.vibrance, language: .korean), "생동감")

        XCTAssertEqual(AppLocalization.text(.whites, language: .japanese), "白レベル")
        XCTAssertEqual(AppLocalization.text(.blacks, language: .japanese), "黒レベル")
        XCTAssertEqual(AppLocalization.text(.vibrance, language: .japanese), "自然な彩度")
        XCTAssertEqual(AppLocalization.text(.exposure, language: .japanese), "露光量")
        XCTAssertEqual(AppLocalization.text(.grain, language: .japanese), "粒子")
        XCTAssertEqual(AppLocalization.text(.exportingStatus, language: .japanese), "書き出し中")

        XCTAssertEqual(AppLocalization.text(.whites, language: .simplifiedChinese), "白色色阶")
        XCTAssertEqual(AppLocalization.text(.blacks, language: .simplifiedChinese), "黑色色阶")
        XCTAssertEqual(AppLocalization.text(.vibrance, language: .simplifiedChinese), "鲜艳度")
        XCTAssertEqual(AppLocalization.text(.noiseReductionStrength, language: .simplifiedChinese), "降噪强度")
        XCTAssertEqual(AppLocalization.text(.exportingStatus, language: .simplifiedChinese), "正在导出")

        XCTAssertEqual(AppLocalization.text(.highlights, language: .german), "Lichter")
        XCTAssertEqual(AppLocalization.text(.vibrance, language: .german), "Dynamik")
        XCTAssertEqual(AppLocalization.text(.redPrimary, language: .german), "Primärfarbe Rot")
        XCTAssertEqual(AppLocalization.text(.apply, language: .german), "Anwenden")
        XCTAssertEqual(AppLocalization.text(.noiseReduction, language: .german), "Rauschreduzierung")

        XCTAssertEqual(AppLocalization.text(.highlights, language: .french), "Hautes lumières")
        XCTAssertEqual(AppLocalization.text(.apply, language: .french), "Appliquer")
        XCTAssertEqual(AppLocalization.text(.grain, language: .french), "Grain")
        XCTAssertEqual(AppLocalization.text(.balance, language: .french), "Balance")
    }

    func testPasteScopeDisplayNameIsLocalized() {
        var scope = DevelopSettingsPasteScope()
        XCTAssertEqual(scope.displayName(language: .english), "All Settings")
        XCTAssertEqual(scope.displayName(language: .korean), "모든 설정")
        XCTAssertEqual(scope.displayName(language: .japanese), "すべての設定")

        scope.detail = false
        XCTAssertEqual(scope.displayName(language: .korean), "베이스/기본 톤/색상/편집")
        XCTAssertEqual(scope.displayName(language: .simplifiedChinese), "片基/基本色调/颜色/几何")
        XCTAssertEqual(scope.displayName(language: .german), "Filmbasis/Grundeinstellungen/Farbe/Geometrie")

        scope.base = false
        scope.tone = false
        scope.color = false
        scope.geometry = false
        XCTAssertEqual(scope.displayName(language: .korean), "없음")
    }

    func testNoMachineTranslationArtifactsRemain() {
        let banned = [
            "白人", "黒人", "黑人", "星期六", "穀物", "谷物", "天然橡胶", "主楼",
            "汽车", "作付面積", "作物面积", "Grundschule", "Céréales", "Samedi",
            "Postuler", "Bewerben", "Anbaufläche", "Lochkamera", "Hauptwohnungsmeister"
        ]
        for language in AppLanguage.allCases where language != .system {
            for key in AppLocalizedPhrase.allCases {
                let value = AppLocalization.text(key, language: language)
                for term in banned {
                    XCTAssertFalse(
                        value.contains(term),
                        "\(language.rawValue) phrase \(key) contains mistranslation \(term)"
                    )
                }
            }
            for key in AppLocalizedText.allCases {
                let value = AppLocalization.text(key, language: language)
                for term in banned {
                    XCTAssertFalse(
                        value.contains(term),
                        "\(language.rawValue) text \(key) contains mistranslation \(term)"
                    )
                }
            }
        }
    }

    func testLegalNoticeTranslationsChangeWithLanguageSelection() {
        XCTAssertEqual(AppLocalization.text(.settingsLegalTab, language: .english), "Legal")
        XCTAssertEqual(AppLocalization.text(.settingsLegalTab, language: .korean), "법적 고지")
        XCTAssertEqual(AppLocalization.text(.settingsLegalTab, language: .french), "Mentions")

        XCTAssertTrue(AppLocalization.text(.legalAffiliationBody, language: .english).contains("not affiliated"))
        XCTAssertTrue(AppLocalization.text(.legalAffiliationBody, language: .korean).contains("제휴"))
        XCTAssertTrue(AppLocalization.text(.legalAffiliationBody, language: .german).contains("nicht"))
    }
}
