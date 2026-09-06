import XCTest
import CoreImage
import ImageIO
@testable import Chromabase
@testable import negaflowApp

@MainActor
final class InputGammaWorkflowTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testReturningToCurrentValueCancelsPendingDifferentGamma() async throws {
        let frame = try makeFrame()
        let model = AppModel()
        model.frames = [frame]
        model.frameStore.selectedFrameID = frame.id
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let url = frame.rawScanURL
        let hold = Task.detached {
            try? InputGammaSourceInfoCache.read(url) {
                started.signal()
                _ = release.wait(timeout: .now() + 5)
                return .init(curve: .embeddedPower(1), manualError: nil)
            }
        }
        XCTAssertEqual(started.wait(timeout: .now() + 5), .success)
        let gamma = try InputGammaInterpretation.power(1.8)
        let pending = Task { await model.setInputGamma(gamma, for: frame) }
        for _ in 0..<100 {
            if frame.isApplyingInputGamma { break }
            await Task.yield()
        }
        XCTAssertTrue(frame.isApplyingInputGamma)
        let unchanged = await model.setInputGamma(.automatic, for: frame)
        release.signal()
        let oldApplied = await pending.value
        _ = await hold.value
        XCTAssertFalse(unchanged)
        XCTAssertFalse(oldApplied)
        XCTAssertEqual(frame.params.inputGamma, .automatic)
        XCTAssertFalse(frame.isApplyingInputGamma)
        model.frames = []
    }

    func testGammaInvalidatesInputButScaleReusesDecodedPixels() throws {
        let frame = try makeFrame()
        let raw = try XCTUnwrap(ImageLoader.loadScannerTIFFDecoded(frame.rawScanURL))
        let cg = try XCTUnwrap(ChromabaseEngine.sharedLinearRenderContext.createCGImage(raw.image, from: raw.image.extent))
        frame.cachedSettledPreviewRaw = DevelopFramePreviewRaw(image: cg, usesLinearSRGB: true)
        frame.cachedSettledPreviewRawRevision = frame.cleanRawRevision
        frame.cachedBase = FilmBase(rgb: SIMD3(0.77, 0.25, 0.16), source: .auto)
        frame.cachedNeutralBase = cg
        let revision = frame.cleanRawRevision
        frame.params.baseScale = try FilmBaseScale(0.5)
        XCTAssertNotNil(frame.cachedSettledPreviewRaw)
        XCTAssertNotNil(frame.cachedBase)
        XCTAssertNil(frame.cachedNeutralBase)
        XCTAssertEqual(frame.cleanRawRevision, revision)
        frame.params.inputGamma = try .power(1.8)
        XCTAssertNil(frame.cachedSettledPreviewRaw)
        XCTAssertNil(frame.cachedBase)
        XCTAssertGreaterThan(frame.cleanRawRevision, revision)
    }

    func testGammaReferenceUsesSnapshotFilmTypeInsteadOfDefaultParameterFilmType() throws {
        let frame = try makeFrame(gradient: true)
        frame.filmType = .bwNegative
        frame.params.inputGamma = try .power(1.8)
        XCTAssertEqual(frame.params.filmType, .colorNegative)
        let snapshot = AppModel().makeSnapshot(for: frame,
            baseKey: FilmBaseCacheKey(filmType: .bwNegative, mode: .auto, manualBaseRGB: nil, filmStockDminID: nil),
            needsRawPreview: false, needsNeutralPreview: false, needsDebugPreviews: false,
            needsThumbnail: false, proxyMaxDimension: 64)
        let result = try DevelopFrameRenderer.render(snapshot)
        let range = try XCTUnwrap(result.sceneMeasurements.inversionStats).dmaxNorm
        XCTAssertEqual(range.x, range.y, accuracy: 1e-12)
        XCTAssertEqual(range.y, range.z, accuracy: 1e-12)
    }

    func testPastePresetAndSnapshotRestoreInputAndBaseScale() throws {
        let source = try makeFrame()
        let target = try makeFrame()
        source.params.inputGamma = try .power(1.8)
        source.params.baseScale = try FilmBaseScale(0.5)
        target.params.inputGamma = try .power(2.4)
        target.applyDevelopSettingsSnapshot(source.developSettingsSnapshot, scope: .all)
        XCTAssertEqual(target.params.inputGamma.value, 1.8)
        XCTAssertEqual(target.params.baseScale.value, 0.5)
        let preset = source.makeUserDevelopPreset(name: "Gamma test")
        XCTAssertEqual(preset.params.inputGamma.value, 1.8)
        target.params.inputGamma = try .power(2.4)
        target.applyUserDevelopPreset(preset, presets: [])
        XCTAssertEqual(target.params.inputGamma.value, 1.8)
        target.applyDevelopSnapshot(source.makeDevelopSnapshot(name: "Full state"), presets: [])
        XCTAssertEqual(target.params.inputGamma.value, 1.8)
        XCTAssertEqual(target.params.mainFlatMasterParameters().inputGamma.value, 1.8)
    }

    func testGammaEditAndUndoRestoreWholeBaseState() async throws {
        let frame = try makeFrame()
        let model = AppModel(libraryDefectDirectoryURL: directory.appendingPathComponent("defects"))
        model.frames = [frame]
        model.frameStore.selectedFrameID = frame.id
        frame.params.baseEstimationMode = .manual
        frame.params.manualBaseRGB = SIMD3(0.7, 0.3, 0.2)
        frame.params.baseScale = try FilmBaseScale(0.75)
        let previous = frame.params
        let changed = await model.setInputGamma(try .power(1.8), for: frame)
        XCTAssertTrue(changed)
        XCTAssertEqual(frame.params.inputGamma.value, 1.8)
        XCTAssertEqual(frame.params.baseEstimationMode, .auto)
        XCTAssertNil(frame.params.manualBaseRGB)
        XCTAssertEqual(frame.params.baseScale.value, 0.75)
        model.performUndo()
        XCTAssertEqual(frame.params, previous)
        model.performRedo()
        XCTAssertEqual(frame.params.inputGamma.value, 1.8)
        XCTAssertEqual(frame.params.baseScale.value, 0.75)
        model.frames = []
    }

    func testGammaModesAndManualEditsPreserveScaleAcrossRange() async throws {
        let frame = try makeFrame()
        let model = AppModel(libraryDefectDirectoryURL: directory.appendingPathComponent("defects"))
        model.frames = [frame]
        model.frameStore.selectedFrameID = frame.id
        defer { model.frames = [] }
        for scale in [0.5, 0.75, 1.0, 1.25, 1.5] {
            frame.params.baseScale = try FilmBaseScale(scale)
            for gamma: InputGammaInterpretation in [try .power(0.3), try .power(4.0), .automatic] {
                let changed = await model.setInputGamma(gamma, for: frame)
                XCTAssertTrue(changed)
                XCTAssertEqual(frame.params.baseScale.value, scale)
                XCTAssertEqual(frame.params.inputGamma, gamma)
                XCTAssertEqual(frame.params.mainFlatMasterParameters().baseScale.value, scale)
                XCTAssertNil(frame.cachedBase)
                XCTAssertNil(frame.baseRGB)
            }
        }
    }

    func testUnsupportedSourceDoesNotCommitOrResetBase() async throws {
        let url = directory.appendingPathComponent("unsupported.png")
        try Data([0, 1, 2]).write(to: url)
        let frame = ScanFrame(scanIndex: 1, rawScanURL: url, filmType: .colorNegative)
        let model = AppModel()
        model.frames = [frame]
        model.frameStore.selectedFrameID = frame.id
        frame.params.baseScale = try FilmBaseScale(0.75)
        let original = frame.params
        let changed = await model.setInputGamma(try .power(2.2), for: frame)
        XCTAssertFalse(changed)
        XCTAssertEqual(frame.params, original)
        XCTAssertFalse(frame.isApplyingInputGamma)
    }

    func testPickerPreviewAndPrintDecodeTheSameGammaWithoutModifyingSource() throws {
        let frame = try makeFrame()
        let original = try Data(contentsOf: frame.rawScanURL)
        for power in [1.0, 1.8, 2.2, 2.4] {
            frame.params.inputGamma = try .power(power)
            let expected = try ImageLoader.loadScannerTIFFDecoded(frame.rawScanURL, inputGamma: frame.params.inputGamma).image
            let picked = try XCTUnwrap(AppModel.loadRawForBasePick(
                preloadedRaw: nil, cleanedRawURL: nil, cleanedRawFrameID: nil, cleanedRawIdentity: nil,
                requiresCleanedRaw: false, rawScanURL: frame.rawScanURL, sourceKind: frame.sourceKind,
                inputGamma: frame.params.inputGamma
            ))
            XCTAssertEqual(pixels(picked), pixels(expected))
            let plan = ExportFrameSnapshotBuilder.build(frame: frame,
                sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
                outputURL: directory.appendingPathComponent("export.tiff"), format: .tiff16,
                writeSidecar: true, writeMainFlatMaster: false, writeOriginalRaw: false,
                options: ExportOptions(), scannerModel: nil, backendUsed: nil)
            let rendered = try ExportDevelopedFrameRenderer.prepareForPrintComposite(plan.snapshot, proxyLongEdge: 32)
            XCTAssertEqual(pixels(rendered.rawInput), pixels(expected))
            XCTAssertEqual(rendered.selectedDecodeProvenance?.inputGamma, frame.params.inputGamma)
        }
        XCTAssertEqual(try Data(contentsOf: frame.rawScanURL), original)
    }

    private func makeFrame(gradient: Bool = false) throws -> ScanFrame {
        let url = directory.appendingPathComponent("\(UUID().uuidString).tiff")
        let source = gradient ? try XCTUnwrap(CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 32, y: 0),
            "inputColor0": CIColor(red: 0.12, green: 0.15, blue: 0.08),
            "inputColor1": CIColor(red: 0.7, green: 0.4, blue: 0.19)
        ])?.outputImage) : CIImage(color: CIColor(red: 0.7, green: 0.3, blue: 0.15))
        let image = source.cropped(to: CGRect(x: 0, y: 0, width: 32, height: 16))
        let cg = try XCTUnwrap(ChromabaseEngine.sharedLinearRenderContext.createCGImage(
            image, from: image.extent, format: .RGBA16, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)))
        XCTAssertTrue(ImageLoader.saveScannerTIFF(cg, to: url))
        return ScanFrame(scanIndex: 1, rawScanURL: url, filmType: .colorNegative)
    }

    private func pixels(_ image: CIImage) -> [Float] {
        var values = [Float](repeating: 0, count: 32 * 16 * 4)
        ChromabaseEngine.sharedLinearRenderContext.render(image, toBitmap: &values, rowBytes: 32 * 16,
            bounds: CGRect(x: 0, y: 0, width: 32, height: 16), format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
        return values
    }
}
