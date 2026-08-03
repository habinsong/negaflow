import Combine
import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class AppModelExportSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "negaflow.export-settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testStorePersistsExportAndQuickExportValues() {
        let store = ExportSettingsStore(defaults: defaults)

        store.exportFormat = .png
        store.exportColorSpace = .displayP3
        store.exportDPI = 300
        store.exportLongEdge = 4096
        store.exportWriteMainFlatMaster = true
        store.exportWriteOriginalRaw = true
        store.exportJPEGQuality = 0.78
        store.exportTIFFCompression = .lzw
        store.exportTIFFBitDepth = .eight
        store.exportPreserveAlpha = true
        store.exportMetadataPolicy = .removeLocation
        store.exportOutputSharpening = 0.64
        store.exportOutputSharpeningMedium = .mattePaper
        store.exportNamingTemplate = "{date}-{roll}-{frame}-{sequence}"
        store.exportSequenceStart = 42
        store.quickExportFormat = .png
        store.quickExportDPI = 300
        store.quickExportLongEdge = 4096
        let profileData = SoftProof.profile(for: .displayP3)?.iccData
        store.softProofICCProfileData = profileData
        store.softProofICCProfileName = "Display P3 Test"
        store.destinationGamutWarningEnabled = true

        let reloaded = ExportSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.exportFormat, .png)
        XCTAssertEqual(reloaded.exportColorSpace, .displayP3)
        XCTAssertEqual(reloaded.exportDPI, 300)
        XCTAssertEqual(reloaded.exportLongEdge, 4096)
        XCTAssertTrue(reloaded.exportWriteMainFlatMaster)
        XCTAssertTrue(reloaded.exportWriteOriginalRaw)
        XCTAssertEqual(reloaded.exportJPEGQuality, 0.78)
        XCTAssertEqual(reloaded.exportTIFFCompression, .lzw)
        XCTAssertEqual(reloaded.exportTIFFBitDepth, .eight)
        XCTAssertTrue(reloaded.exportPreserveAlpha)
        XCTAssertEqual(reloaded.exportMetadataPolicy, .removeLocation)
        XCTAssertEqual(reloaded.exportOutputSharpening, 0.64)
        XCTAssertEqual(reloaded.exportOutputSharpeningMedium, .mattePaper)
        XCTAssertEqual(reloaded.exportNamingTemplate, "{date}-{roll}-{frame}-{sequence}")
        XCTAssertEqual(reloaded.exportSequenceStart, 42)
        XCTAssertEqual(reloaded.quickExportFormat, .png)
        XCTAssertEqual(reloaded.quickExportDPI, 300)
        XCTAssertEqual(reloaded.quickExportLongEdge, 4096)
        XCTAssertEqual(reloaded.softProofICCProfileData, profileData)
        XCTAssertEqual(reloaded.softProofICCProfileName, "Display P3 Test")
        XCTAssertTrue(reloaded.destinationGamutWarningEnabled)
    }

    func testStoreFallsBackForMissingOrInvalidDefaults() {
        defaults.set("not-a-format", forKey: "export.format")
        defaults.set("not-a-space", forKey: "export.colorSpace")
        defaults.set("not-a-quick-format", forKey: "export.quick.format")
        defaults.set("not-a-policy", forKey: "export.metadataPolicy")
        defaults.set(Double.nan, forKey: "export.outputSharpening")
        defaults.set("not-a-medium", forKey: "export.outputSharpeningMedium")
        defaults.set(-4, forKey: "export.sequenceStart")

        let store = ExportSettingsStore(defaults: defaults)

        XCTAssertEqual(store.exportFormat, .jpeg)
        XCTAssertEqual(store.exportColorSpace, .sRGB)
        XCTAssertEqual(store.exportDPI, 0)
        XCTAssertEqual(store.exportLongEdge, 0)
        XCTAssertFalse(store.exportWriteMainFlatMaster)
        XCTAssertFalse(store.exportWriteOriginalRaw)
        XCTAssertEqual(store.exportJPEGQuality, 1.0)
        XCTAssertEqual(store.exportTIFFCompression, .none)
        XCTAssertEqual(store.exportTIFFBitDepth, .sixteen)
        XCTAssertFalse(store.exportPreserveAlpha)
        XCTAssertEqual(store.exportMetadataPolicy, .minimal)
        XCTAssertEqual(store.exportOutputSharpening, 0)
        XCTAssertEqual(store.exportOutputSharpeningMedium, .screen)
        XCTAssertEqual(store.exportNamingTemplate, ExportNamingTemplate.defaultPattern)
        XCTAssertEqual(store.exportSequenceStart, 1)
        XCTAssertEqual(store.quickExportFormat, .jpeg)
        XCTAssertEqual(store.quickExportDPI, ExportSettingsStore.defaultQuickExportDPI)
        XCTAssertEqual(store.quickExportLongEdge, ExportSettingsStore.defaultQuickExportLongEdge)
    }

    /// 새 기본값은 키가 없을 때만 적용한다 — 사용자가 이미 고른 값(원본 크기/원본 DPI 포함)을
    /// 업데이트가 조용히 덮어쓰면 안 된다.
    func testStoredQuickExportSizeAndDPISurviveNewDefaults() {
        defaults.set(0, forKey: "export.quick.dpi")
        defaults.set(0, forKey: "export.quick.longEdge")

        let store = ExportSettingsStore(defaults: defaults)

        XCTAssertEqual(store.quickExportDPI, 0)
        XCTAssertEqual(store.quickExportLongEdge, 0)

        let model = AppModel(exportSettingsStore: store)
        XCTAssertNil(model.quickExportOptions.longEdge)
        XCTAssertEqual(model.quickExportOptions.dpi, 0)
    }

    func testNegativeStoredQuickExportSizeIsClampedToFullSize() {
        defaults.set(-2048, forKey: "export.quick.longEdge")

        let store = ExportSettingsStore(defaults: defaults)

        XCTAssertEqual(store.quickExportLongEdge, 0)
    }

    func testQuickExportOptionsCarryEncodingSettings() {
        let model = AppModel(exportSettingsStore: ExportSettingsStore(defaults: defaults))

        // 기본값: 두 경로 모두 JPEG 최고 품질, PNG 는 보관용 16bit / 공유용 8bit.
        XCTAssertEqual(model.quickExportJPEGQuality, 1.0)
        XCTAssertEqual(model.quickExportOptions.jpegQuality, 1.0)
        XCTAssertEqual(model.exportOptions.pngBitDepth, .sixteen)
        XCTAssertEqual(model.quickExportOptions.pngBitDepth, .eight)

        // 빠른 내보내기는 자기 설정을 따른다 — 일반 내보내기 값이 새지 않는다.
        model.quickExportJPEGQuality = 0.7
        model.quickExportPNGBitDepth = .sixteen
        model.exportJPEGQuality = 0.4
        model.exportPNGBitDepth = .eight

        XCTAssertEqual(model.quickExportOptions.jpegQuality, 0.7)
        XCTAssertEqual(model.quickExportOptions.pngBitDepth, .sixteen)
        XCTAssertEqual(model.exportOptions.jpegQuality, 0.4)
        XCTAssertEqual(model.exportOptions.pngBitDepth, .eight)
    }

    func testAppModelFacadePublishesAndBuildsExportOptions() {
        let model = AppModel(exportSettingsStore: ExportSettingsStore(defaults: defaults))
        var changeCount = 0
        let cancellable = model.objectWillChange.sink { changeCount += 1 }

        model.exportColorSpace = .displayP3
        model.exportDPI = 240
        model.exportLongEdge = 2048
        model.exportJPEGQuality = 0.8
        model.exportTIFFCompression = .deflate
        model.exportTIFFBitDepth = .eight
        model.exportMetadataPolicy = .copyrightOnly
        model.exportOutputSharpening = 0.72
        model.exportOutputSharpeningMedium = .glossyPaper
        model.exportWriteOriginalRaw = true
        model.quickExportDPI = 72
        let profileData = try! XCTUnwrap(SoftProof.profile(for: .displayP3)?.iccData)
        XCTAssertTrue(model.setSoftProofICCProfile(data: profileData, name: "Display P3 Test"))

        XCTAssertEqual(model.exportOptions.colorSpace, .displayP3)
        XCTAssertEqual(model.exportOptions.dpi, 240)
        XCTAssertEqual(model.exportOptions.longEdge, 2048)
        XCTAssertEqual(model.exportOptions.jpegQuality, 0.8)
        XCTAssertEqual(model.exportOptions.tiffCompression, .deflate)
        XCTAssertEqual(model.exportOptions.tiffBitDepth, .eight)
        XCTAssertEqual(model.exportOptions.metadataPolicy, .copyrightOnly)
        XCTAssertEqual(model.exportOptions.outputSharpening, 0.72)
        XCTAssertEqual(model.exportOptions.outputSharpeningMedium, .glossyPaper)
        XCTAssertEqual(model.softProofSettings.colorSpace, .displayP3)
        XCTAssertEqual(model.softProofSettings.iccProfileData, profileData)
        XCTAssertEqual(model.softProofICCProfileName, "Display P3 Test")
        model.softProofEnabled = true
        model.destinationGamutWarningEnabled = true
        XCTAssertTrue(model.destinationGamutWarningEnabled)
        XCTAssertTrue(model.destinationGamutWarningAvailable)
        XCTAssertTrue(model.exportWriteOriginalRaw)
        XCTAssertEqual(model.quickExportOptions.colorSpace, .sRGB)
        XCTAssertEqual(model.quickExportOptions.dpi, 72)
        XCTAssertEqual(
            model.quickExportOptions.longEdge,
            ExportSettingsStore.defaultQuickExportLongEdge
        )
        XCTAssertEqual(model.quickExportOptions.metadataPolicy, .minimal)
        XCTAssertEqual(model.quickExportOptions.outputSharpening, 0)
        XCTAssertGreaterThanOrEqual(changeCount, 1)
        withExtendedLifetime(cancellable) {}
    }

    func testInvalidStoredICCProfileIsIgnored() {
        defaults.set(Data([0x00, 0x01]), forKey: "softProof.iccProfileData")
        defaults.set("Broken", forKey: "softProof.iccProfileName")

        let store = ExportSettingsStore(defaults: defaults)

        XCTAssertNil(store.softProofICCProfileData)
        XCTAssertNil(store.softProofICCProfileName)
    }

    func testPrinterOutputProfilePersistsAndRejectsNonPrinterICC() throws {
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let model = AppModel(exportSettingsStore: ExportSettingsStore(defaults: defaults))

        XCTAssertTrue(model.setPrinterOutputICCProfile(
            data: profile.iccProfileData,
            name: profile.profileName
        ))

        let reloaded = AppModel(exportSettingsStore: ExportSettingsStore(defaults: defaults))
        XCTAssertEqual(reloaded.printerOutputICCProfileData, profile.iccProfileData)
        XCTAssertEqual(reloaded.printerOutputICCProfileName, profile.profileName)
        XCTAssertEqual(reloaded.selectedPrinterOutputProfile?.profileSHA256, profile.profileSHA256)

        let displayProfile = try XCTUnwrap(SoftProof.profile(for: .displayP3)?.iccData)
        XCTAssertFalse(reloaded.setPrinterOutputICCProfile(
            data: displayProfile,
            name: "Display P3"
        ))
        XCTAssertEqual(reloaded.printerOutputICCProfileData, profile.iccProfileData)
        XCTAssertEqual(reloaded.printerOutputICCProfileName, profile.profileName)
        XCTAssertEqual(reloaded.selectedPrinterOutputProfile?.profileSHA256, profile.profileSHA256)
    }

    func testClearedMigratedPrinterProfileDoesNotReturnOnReload() throws {
        let profile = try ICCOutputProfileTestFixture.snapshot()
        defaults.set(profile.iccProfileData, forKey: "softProof.iccProfileData")
        defaults.set(profile.profileName, forKey: "softProof.iccProfileName")

        let migrated = AppModel(exportSettingsStore: ExportSettingsStore(defaults: defaults))
        XCTAssertEqual(migrated.selectedPrinterOutputProfile?.profileSHA256, profile.profileSHA256)

        migrated.clearPrinterOutputICCProfile()
        let reloaded = AppModel(exportSettingsStore: ExportSettingsStore(defaults: defaults))

        XCTAssertNil(reloaded.printerOutputICCProfileData)
        XCTAssertNil(reloaded.printerOutputICCProfileName)
        XCTAssertNil(reloaded.selectedPrinterOutputProfile)
        XCTAssertEqual(reloaded.softProofICCProfileData, profile.iccProfileData)
    }

    func testRawExportOptionsDiscardResizeAndProcessedOutputSettings() {
        let model = AppModel(exportSettingsStore: ExportSettingsStore(defaults: defaults))
        model.exportLongEdge = 4096
        model.exportTIFFCompression = .lzw
        model.exportTIFFBitDepth = .eight
        model.exportPreserveAlpha = true
        model.exportOutputSharpening = 0.8

        model.exportFormat = .rawScanTIFF

        XCTAssertNil(model.exportOptions.longEdge)
        XCTAssertEqual(model.exportOptions.tiffCompression, .none)
        XCTAssertEqual(model.exportOptions.tiffBitDepth, .sixteen)
        XCTAssertFalse(model.exportOptions.preserveAlpha)
        XCTAssertEqual(model.exportOptions.outputSharpening, 0)
        XCTAssertNoThrow(try model.exportOptions.validate(for: .rawScanTIFF))
    }

    func testStoredRawAndUnsupportedQuickFormatsRestoreToSafeInvariants() {
        defaults.set(ExportFormat.rawScanTIFF.rawValue, forKey: "export.format")
        defaults.set(4096, forKey: "export.longEdge")
        defaults.set(ExportTIFFCompression.lzw.rawValue, forKey: "export.tiffCompression")
        defaults.set(ExportTIFFBitDepth.eight.rawValue, forKey: "export.tiffBitDepth")
        defaults.set(true, forKey: "export.preserveAlpha")
        defaults.set(0.9, forKey: "export.outputSharpening")
        defaults.set(ExportFormat.rawScanTIFF.rawValue, forKey: "export.quick.format")

        let store = ExportSettingsStore(defaults: defaults)

        XCTAssertEqual(store.exportFormat, .rawScanTIFF)
        XCTAssertEqual(store.exportLongEdge, 0)
        XCTAssertEqual(store.exportTIFFCompression, .none)
        XCTAssertEqual(store.exportTIFFBitDepth, .sixteen)
        XCTAssertFalse(store.exportPreserveAlpha)
        XCTAssertEqual(store.exportOutputSharpening, 0)
        XCTAssertEqual(store.quickExportFormat, .jpeg)
    }

    func testQuickExportFolderUsesConfiguredPathAndDisplayName() {
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            diskStorageStore: DiskStorageStore(defaults: defaults)
        )

        model.quickExportFolderPath = "/tmp/negaflow-export-folder"

        XCTAssertEqual(model.quickExportFolderURL.path, "/tmp/negaflow-export-folder")
        XCTAssertEqual(model.quickExportFolderDisplay, "negaflow-export-folder")
    }
}
