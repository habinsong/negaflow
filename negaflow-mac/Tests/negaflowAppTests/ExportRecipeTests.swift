import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class ExportRecipeTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-recipe-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try await super.tearDown()
    }

    func testConfigurationHashIsDeterministicAndExcludesPresetIdentity() throws {
        let settings = makeSettings()
        let first = ExportRecipe(name: "Archive", settings: settings)
        let renamed = ExportRecipe(
            id: first.id,
            name: "Renamed",
            createdAt: first.createdAt,
            settings: settings
        )
        var changed = settings
        changed.options.jpegQuality = 0.4

        XCTAssertEqual(
            try first.settings.configurationSHA256(),
            try renamed.settings.configurationSHA256()
        )
        XCTAssertNotEqual(
            try settings.configurationSHA256(),
            try changed.configurationSHA256()
        )
        XCTAssertEqual(try settings.configurationSHA256().utf8.count, 64)
    }

    func testPrintConfigurationHashChangesWithOutputProfileHash() throws {
        let model = makeModel()
        let settings = makeSettings()
        let composition = PrintCompositionSettings()
        let first = try XCTUnwrap(
            model.printExportRecipeIdentity(
                settings: composition,
                format: settings.format,
                options: settings.options,
                writeSidecar: settings.writeSidecar,
                writeMainFlatMaster: settings.writeMainFlatMaster,
                writeOriginalRaw: settings.writeOriginalRaw,
                namingTemplate: settings.filenameTemplate,
                outputProfileSHA256: String(repeating: "a", count: 64)
            )
        )
        let second = try XCTUnwrap(
            model.printExportRecipeIdentity(
                settings: composition,
                format: settings.format,
                options: settings.options,
                writeSidecar: settings.writeSidecar,
                writeMainFlatMaster: settings.writeMainFlatMaster,
                writeOriginalRaw: settings.writeOriginalRaw,
                namingTemplate: settings.filenameTemplate,
                outputProfileSHA256: String(repeating: "b", count: 64)
            )
        )

        XCTAssertNotEqual(first.configurationSHA256, second.configurationSHA256)
    }

    func testMixedMainAndPrintBatchBindsProfileOnlyToPrintRecipeIdentity() throws {
        let model = makeModel()
        let mainFrame = try makeFrame()
        let printURL = temporaryDirectory.appendingPathComponent("print-source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: printURL)
        let printFrame = ScanFrame(
            scanIndex: 2,
            rawScanURL: printURL,
            filmType: .colorPositive
        )
        printFrame.updateParams { $0.developTarget = .print }
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let mainIdentity = try XCTUnwrap(model.currentExportRecipeIdentity())
        let printIdentity = try XCTUnwrap(model.currentExportRecipeIdentity(
            outputProfileSHA256: profile.profileSHA256
        ))

        let plans = model.makeExportBatchPlans(
            frames: [mainFrame, printFrame],
            root: temporaryDirectory.appendingPathComponent("mixed-exports"),
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: model.exportOptions,
            printerOutputProfile: profile,
            recipeIdentity: mainIdentity,
            printRecipeIdentity: printIdentity
        )

        XCTAssertEqual(plans[0].recipeIdentity?.configurationSHA256, mainIdentity.configurationSHA256)
        XCTAssertEqual(plans[1].recipeIdentity?.configurationSHA256, printIdentity.configurationSHA256)
        XCTAssertNotEqual(
            plans[0].recipeIdentity?.configurationSHA256,
            plans[1].recipeIdentity?.configurationSHA256
        )
    }

    func testPrintPackageRecipeHashUsesEffectiveMinimalMetadataPolicy() throws {
        let model = makeModel()
        var requestedOptions = ExportOptions(dpi: 240)
        requestedOptions.metadataPolicy = .all
        let effectiveOptions = model.printPackageExportOptions(requestedOptions, dpi: 300)
        let composition = PrintCompositionSettings(dpi: 300)
        let package = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 2,
            contactColumns: 2
        )
        let requestedIdentity = try XCTUnwrap(model.printExportRecipeIdentity(
            settings: composition,
            package: package,
            format: .jpeg,
            options: requestedOptions,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            namingTemplate: ExportNamingTemplate.defaultPattern
        ))
        let effectiveIdentity = try XCTUnwrap(model.printExportRecipeIdentity(
            settings: composition,
            package: package,
            format: .jpeg,
            options: effectiveOptions,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            namingTemplate: ExportNamingTemplate.defaultPattern
        ))

        XCTAssertEqual(effectiveOptions.metadataPolicy, .minimal)
        XCTAssertEqual(effectiveOptions.dpi, 300)
        XCTAssertNotEqual(
            requestedIdentity.configurationSHA256,
            effectiveIdentity.configurationSHA256
        )
    }

    func testStorePersistsRenameDeleteAndRejectsDuplicateNames() throws {
        let url = temporaryDirectory.appendingPathComponent("recipes.json")
        let store = ExportRecipeStore(url: url)
        let recipe = try XCTUnwrap(store.add(name: "Archive", settings: makeSettings()))
        XCTAssertNil(store.add(name: "archive", settings: makeSettings()))
        XCTAssertTrue(store.rename(id: recipe.id, to: "Master"))

        let reloaded = ExportRecipeStore(url: url)
        XCTAssertEqual(reloaded.recipes.map(\.name), ["Master"])
        XCTAssertEqual(reloaded.recipes[0].settings, makeSettings())
        reloaded.delete(id: recipe.id)
        XCTAssertTrue(ExportRecipeStore(url: url).recipes.isEmpty)
    }

    func testUnsupportedStoreVersionIsPreservedAndBlocksMutation() throws {
        let url = temporaryDirectory.appendingPathComponent("recipes.json")
        let bytes = Data(#"{"version":999,"recipes":[]}"#.utf8)
        try bytes.write(to: url)

        let store = ExportRecipeStore(url: url)

        XCTAssertFalse(store.canModify)
        XCTAssertNil(store.add(name: "Must Not Overwrite", settings: makeSettings()))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testApplyingRecipeRestoresEveryCapturedSettingAndTracksDrift() throws {
        let model = makeModel()
        configure(model, with: makeSettings())
        let recipeID = try XCTUnwrap(model.saveCurrentExportRecipe(name: "Current"))
        let originalIdentity = try XCTUnwrap(model.currentExportRecipeIdentity())
        XCTAssertEqual(originalIdentity.presetID, recipeID)

        model.exportDPI = 72
        let driftedIdentity = try XCTUnwrap(model.currentExportRecipeIdentity())
        XCTAssertNil(driftedIdentity.presetID)
        XCTAssertNotEqual(driftedIdentity.configurationSHA256, originalIdentity.configurationSHA256)

        let recipe = try XCTUnwrap(model.exportRecipes.first)
        model.applyExportRecipe(recipe)
        XCTAssertEqual(model.currentExportRecipeSettings, recipe.settings)
        XCTAssertEqual(model.currentExportRecipeIdentity()?.presetID, recipeID)
    }

    func testExportPersistsRecipeIdentityInCatalogAndSidecars() async throws {
        let model = makeModel()
        configure(model, with: makeSettings())
        await model.restoreLibraryOnLaunch()
        let frame = try makeFrame()
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame]))
        frame.hasDevelopedOnce = true
        model.selectedFrameIDs = [frame.id]
        model.updateInteractionScope([frame.id])
        let recipeID = try XCTUnwrap(model.saveCurrentExportRecipe(name: "Archive"))
        let identity = try XCTUnwrap(model.currentExportRecipeIdentity())
        let outputURL = temporaryDirectory.appendingPathComponent("archive.jpg")

        let result = await model.runExportFrameTransaction(
            frame,
            to: outputURL,
            format: model.exportFormat,
            writeSidecar: true,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: model.exportOptions,
            recipeIdentity: identity,
            reportsGlobalStatus: false
        )
        guard case .completed = result else {
            return XCTFail("export failed")
        }

        let event = try XCTUnwrap(
            frame.libraryWorkflowTrackingState?.exportTracking.successfulEvents.last
        )
        XCTAssertEqual(event.exportRecipePresetID, recipeID)
        XCTAssertEqual(event.exportRecipeSHA256, identity.configurationSHA256)
        let sidecarURL = outputURL.deletingPathExtension().appendingPathExtension("negaflow.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(Sidecar.self, from: Data(contentsOf: sidecarURL))
        XCTAssertEqual(sidecar.exportRecipe?.presetID, recipeID.uuidString)
        XCTAssertEqual(sidecar.exportRecipe?.configurationSHA256, identity.configurationSHA256)
        XCTAssertEqual(sidecar.renderManifest?.exportRecipeSHA256, identity.configurationSHA256)
        XCTAssertEqual(sidecar.exportEncoding, Sidecar.ExportEncodingInfo(model.exportOptions))
        XCTAssertEqual(sidecar.exportMetadataPolicy, .removeLocation)
        let xmpURL = outputURL.deletingPathExtension().appendingPathExtension("xmp")
        XCTAssertTrue(
            try String(contentsOf: xmpURL, encoding: .utf8)
                .contains("negaflow:ExportMetadataPolicy=\"removeLocation\"")
        )
    }

    private func makeModel() -> AppModel {
        let defaults = UserDefaults(suiteName: "ExportRecipeTests-\(UUID().uuidString)")!
        return AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            exportRecipeStore: ExportRecipeStore(
                url: temporaryDirectory.appendingPathComponent("recipes.json")
            ),
            libraryCatalogURL: temporaryDirectory.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: temporaryDirectory.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: temporaryDirectory.appendingPathComponent("backups")
        )
    }

    private func makeSettings() -> ExportRecipeSettings {
        ExportRecipeSettings(
            format: .jpeg,
            options: ExportOptions(
                colorSpace: .displayP3,
                dpi: 300,
                longEdge: 2048,
                jpegQuality: 0.82,
                tiffCompression: .lzw,
                tiffBitDepth: .eight,
                metadataPolicy: .removeLocation,
                outputSharpening: 0.55,
                outputSharpeningMedium: .mattePaper
            ),
            writeSidecar: true,
            writeMainFlatMaster: true,
            writeOriginalRaw: false,
            filenameTemplate: "{date}-{roll}-{frame}-{name}-{preset}-{sequence}"
        )
    }

    private func configure(_ model: AppModel, with settings: ExportRecipeSettings) {
        model.exportFormat = settings.format
        model.exportColorSpace = settings.options.colorSpace
        model.exportDPI = settings.options.dpi
        model.exportLongEdge = settings.options.longEdge ?? 0
        model.exportJPEGQuality = settings.options.jpegQuality
        model.exportTIFFCompression = settings.options.tiffCompression
        model.exportTIFFBitDepth = settings.options.tiffBitDepth
        model.exportPreserveAlpha = settings.options.preserveAlpha
        model.exportMetadataPolicy = settings.options.metadataPolicy
        model.exportOutputSharpening = settings.options.outputSharpening
        model.exportOutputSharpeningMedium = settings.options.outputSharpeningMedium
        model.exportWriteSidecar = settings.writeSidecar
        model.exportWriteMainFlatMaster = settings.writeMainFlatMaster
        model.exportWriteOriginalRaw = settings.writeOriginalRaw
        model.exportNamingTemplate = settings.filenameTemplate
    }

    private func makeFrame() throws -> ScanFrame {
        let sourceURL = temporaryDirectory.appendingPathComponent("source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: sourceURL)
        let frame = ScanFrame(scanIndex: 1, rawScanURL: sourceURL, filmType: .colorPositive)
        _ = LibraryFrameRecord(frame: frame)
        return frame
    }
}
