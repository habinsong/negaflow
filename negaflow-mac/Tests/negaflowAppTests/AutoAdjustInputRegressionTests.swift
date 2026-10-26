import XCTest
import CoreImage
import ScannerKit
@testable import Chromabase
@testable import negaflowApp

@MainActor
final class AutoAdjustInputRegressionTests: XCTestCase {
    func testChangingCameraRawIntentDropsPixelCachesButPreservesSource() throws {
        let source = URL(fileURLWithPath: "/tmp/camera-native-cache.dng")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: source, filmType: .colorNegative)
        let identity = try DefectRecipeIdentity(fingerprintVersion: DefectRecipeFingerprint.currentVersion,
            revision: 1, recipeSHA256: String(repeating: "a", count: 64),
            sourceIdentity: DefectSourceIdentity(byteCount: 100, sha256: String(repeating: "b", count: 64)))
        frame.defectRecipeIdentity = identity
        frame.cleanedRawDiskIdentity = identity
        frame.cleanedRawDiskURL = URL(fileURLWithPath: "/tmp/old-working-raw.tiff")
        XCTAssertNil(frame.identityMatchedCleanedRawDiskURL, "Old working-RGB cache cannot serve camera-native inversion")
        frame.cleanedRawDiskURL = CleanedRawCacheFile.makeBuildURL(frameID: frame.id)
        XCTAssertNotNil(frame.identityMatchedCleanedRawDiskURL)
        frame.thumbnailRecipeID = "old-render"
        frame.params.isDigitalSource = true
        XCTAssertNil(frame.cleanedRawDiskURL)
        XCTAssertNil(frame.thumbnailRecipeID)
        XCTAssertEqual(frame.defectRecipeIdentity, identity)
        XCTAssertEqual(frame.rawScanURL, source)
    }

    func testAutomaticResultAndResetUndoPreserveInputSettings() async throws {
        let (model, frame, root) = try fixture()
        defer { model.frames = []; try? FileManager.default.removeItem(at: root) }
        frame.params.inputGamma = try .power(1.8)
        frame.params.baseScale = try FilmBaseScale(0.75)
        let original = frame.params
        await model.autoTone(frame).value
        let adjusted = frame.params
        XCTAssertNotEqual(original, adjusted)
        model.performUndo(); XCTAssertEqual(frame.params, original)
        model.performRedo(); XCTAssertEqual(frame.params, adjusted)
        model.resetAutoTone(frame)
        XCTAssertEqual(frame.params.exposure, 0)
        XCTAssertEqual(frame.params.inputGamma, original.inputGamma)
        XCTAssertEqual(frame.params.baseScale, original.baseScale)
        model.performUndo(); XCTAssertEqual(frame.params, adjusted)
        let pending = model.autoWhiteBalance(frame)
        model.resetAutoWhiteBalance(frame)
        let reset = frame.params
        await pending.value
        XCTAssertEqual(frame.params, reset)
    }

    func testGammaScaleAndToggleMatrixMatchesFreshSceneMeasurements() throws {
        let (model, frame, root) = try fixture()
        defer { model.frames = []; try? FileManager.default.removeItem(at: root) }
        for gamma in [InputGammaInterpretation.automatic, try .power(1.8), try .power(2.4)] {
            for scale in [0.75, 1.25] {
                for levels in [false, true] {
                    for color in [false, true] {
                        frame.updateParams {
                            $0.inputGamma = gamma; $0.baseScale = try! FilmBaseScale(scale)
                            $0.autoLevels = levels; $0.autoNeutralBalance = color
                        }
                        let key = FilmBaseCacheKey(filmType: frame.filmType, mode: .auto, manualBaseRGB: nil, filmStockDminID: nil)
                        let snapshot = model.makeSnapshot(for: frame, baseKey: key, needsRawPreview: false,
                            needsNeutralPreview: false, needsDebugPreviews: false, needsThumbnail: false, proxyMaxDimension: 128)
                        let result = try DevelopFrameRenderer.render(snapshot)
                        var fresh = snapshot
                        fresh.cachedSceneMeasurements = DevelopSceneMeasurements()
                        XCTAssertEqual(pixels(result.developed), pixels(try DevelopFrameRenderer.render(fresh).developed),
                            "gamma=\(String(describing: gamma.value)) scale=\(scale) levels=\(levels) color=\(color)")
                        XCTAssertEqual(result.sceneMeasurements.autoLevelsPoints != nil, levels)
                        XCTAssertEqual(result.sceneMeasurements.neutralBalanceCorrection != nil, color)
                        model.applyBaseCache(result, to: frame, baseKey: key)
                        model.applySceneMeasurementCache(result, to: frame, baseKey: key, proxyMaxDimension: 128,
                            renderedParams: snapshot.params)
                        let reused = model.makeSnapshot(for: frame, baseKey: key, needsRawPreview: false,
                            needsNeutralPreview: false, needsDebugPreviews: false, needsThumbnail: false, proxyMaxDimension: 128)
                        XCTAssertEqual(pixels(result.developed), pixels(try DevelopFrameRenderer.render(reused).developed))
                    }
                }
            }
        }
    }

    func testTargetSwitchAndComparisonPreviewKeepSelectedMeasurements() throws {
        let (model, frame, root) = try fixture()
        defer { model.frames = []; try? FileManager.default.removeItem(at: root) }
        let key = FilmBaseCacheKey(filmType: frame.filmType, mode: .auto,
                                  manualBaseRGB: nil, filmStockDminID: nil)
        let cases: [(DevelopTarget, String?)] = [
            (.main, nil), (.sp3000, nil),
            (.main, "noritsu__color-nega__kodak-ultramax-400"),
            (.emulsion, nil), (.rescue, nil), (.main, nil),
        ]
        for (target, profile) in cases {
            frame.updateParams {
                $0.developTarget = target
                $0.scannerProfileID = profile
                $0.autoLevels = true
            }
            let snapshot = model.makeSnapshot(for: frame, baseKey: key, needsRawPreview: false,
                needsNeutralPreview: true, needsMainPreview: true, needsDebugPreviews: false,
                needsThumbnail: false, proxyMaxDimension: 128)
            let result = try DevelopFrameRenderer.render(snapshot)
            var fresh = model.makeSnapshot(for: frame, baseKey: key, needsRawPreview: false,
                needsNeutralPreview: false, needsDebugPreviews: false,
                needsThumbnail: false, proxyMaxDimension: 128)
            fresh.cachedSceneMeasurements = DevelopSceneMeasurements()
            let reference = try DevelopFrameRenderer.render(fresh)
            XCTAssertEqual(pixels(result.developed), pixels(reference.developed), target.rawValue)
            XCTAssertEqual(result.sceneMeasurements, reference.sceneMeasurements, target.rawValue)
            model.applyBaseCache(result, to: frame, baseKey: key)
            model.applySceneMeasurementCache(result, to: frame, baseKey: key, proxyMaxDimension: 128,
                                            renderedParams: snapshot.params)
            let reused = model.makeSnapshot(for: frame, baseKey: key, needsRawPreview: false,
                needsNeutralPreview: false, needsDebugPreviews: false,
                needsThumbnail: false, proxyMaxDimension: 128)
            XCTAssertEqual(pixels(try DevelopFrameRenderer.render(reused).developed),
                           pixels(reference.developed), target.rawValue)
        }
    }

    func testAutomaticToneAndWhiteBalanceUseCurrentInputAndRemainIdempotent() async throws {
        let (model, frame, root) = try fixture()
        defer { model.frames = []; try? FileManager.default.removeItem(at: root) }
        for gamma in [1.8, 2.4] {
            for scale in [0.75, 1.25] {
                frame.params.inputGamma = try .power(gamma)
                frame.params.baseScale = try FilmBaseScale(scale)
                frame.params.autoLevels = true; frame.params.autoNeutralBalance = true
                // 자동 보정 입력은 화면이 메모리에 올린 raw 프록시에서 줄인다 — 기대값과 모델이 같은
                // 입력을 보도록 현상을 먼저 끝낸다(뒤에서 끝나는 현상과 경쟁하지 않게).
                await model.developFrame(frame)
                // 자동 톤은 폐루프다: 중립본에서 계산 → 그 값으로 다시 그려 재고 한 번 바로잡는다.
                let image = try DevelopFrameRenderer.render(model.neutralSnapshot(frame, clearTone: true)).developed
                let first = AutoAdjust.autoTone(try XCTUnwrap(AutoAdjust.imageStats(image)), filmType: frame.filmType)
                let verify = try DevelopFrameRenderer.render(model.autoAdjustSnapshot(
                    frame, params: AppModel.applying(first, to: frame.params))).developed
                let expected = AutoAdjust.refineTone(first, measured: try XCTUnwrap(AutoAdjust.imageStats(verify)),
                                                     filmType: frame.filmType)
                await model.autoTone(frame).value
                XCTAssertEqual(frame.params.exposure, expected.exposure)
                XCTAssertEqual(frame.params.whites, expected.whites)
                XCTAssertEqual(frame.params.density, expected.density)
                let once = frame.params
                await model.autoTone(frame).value
                XCTAssertEqual(frame.params, once)
                let wbImage = try DevelopFrameRenderer.render(model.neutralSnapshot(frame, clearWB: true)).developed
                let wb = AutoAdjust.autoWhiteBalance(try XCTUnwrap(AutoAdjust.imageStats(wbImage)))
                await model.autoWhiteBalance(frame).value
                XCTAssertEqual(frame.params.warmth, wb.warmth)
                XCTAssertEqual(frame.params.tint, wb.tint)
                let balanced = frame.params
                await model.autoWhiteBalance(frame).value
                XCTAssertEqual(frame.params, balanced)
                XCTAssertEqual(frame.params.inputGamma.value, gamma)
                XCTAssertEqual(frame.params.baseScale.value, scale)
                XCTAssertTrue(frame.params.autoLevels && frame.params.autoNeutralBalance)
            }
        }
    }

    func testAllInputEditsAndNewRequestsInvalidateOldAutomaticWork() throws {
        let (_, frame, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for edit: (ScanFrame) -> Void in [
            { $0.params.inputGamma = try! .power(1.8); $0.params.inputGamma = .automatic },
            { $0.params.baseScale = try! FilmBaseScale(1.25); $0.params.baseScale = .identity },
            { $0.params.autoLevels = true; $0.params.autoLevels = false },
            { $0.params.autoNeutralBalance = true; $0.params.autoNeutralBalance = false },
            { $0.imageTransform = ImageTransform(rotation: .deg90); $0.imageTransform = .identity },
            { _ = AutoAdjustRequest($0) }
        ] {
            let request = AutoAdjustRequest(frame)
            XCTAssertTrue(request.isCurrent(frame))
            edit(frame)
            XCTAssertFalse(request.isCurrent(frame))
        }
    }

    /// 둘을 연달아 누르면 둘 다 반영되고, 하나씩 끝까지 기다려 누른 것과 같은 값이다.
    func testPressingToneThenWhiteBalanceAppliesBothLikeSequentialPresses() async throws {
        let (model, frame, root) = try fixture()
        defer { model.frames = []; try? FileManager.default.removeItem(at: root) }
        await model.developFrame(frame)
        let start = frame.params
        await model.autoTone(frame).value
        await model.autoWhiteBalance(frame).value
        let sequential = frame.params
        XCTAssertNotEqual(sequential, start)
        frame.params = start
        let tone = model.autoTone(frame)
        let balance = model.autoWhiteBalance(frame)
        await tone.value
        await balance.value
        XCTAssertEqual(frame.params, sequential)
    }

    private func fixture() throws -> (AppModel, ScanFrame, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("auto-input-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("source.tif")
        let gradient = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0, y: 0),
            "inputPoint1": CIVector(x: 128, y: 96), "inputColor0": CIColor(red: 0.04, green: 0.08, blue: 0.02),
            "inputColor1": CIColor(red: 0.85, green: 0.65, blue: 0.40)])!.outputImage!
            .cropped(to: CGRect(x: 0, y: 0, width: 128, height: 96))
        let cg = try XCTUnwrap(ChromabaseEngine.sharedLinearRenderContext.createCGImage(gradient, from: gradient.extent,
            format: .RGBA16, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)))
        XCTAssertTrue(ImageLoader.saveScannerTIFF(cg, to: url))
        let frame = ScanFrame(scanIndex: 1, rawScanURL: url, filmType: .colorNegative)
        let model = AppModel(); model.frames = [frame]
        return (model, frame, root)
    }

    private func pixels(_ cg: CGImage) -> Data {
        var data = Data(count: cg.width * cg.height * 4)
        data.withUnsafeMutableBytes {
            ChromabaseEngine.sharedLinearRenderContext.render(CIImage(cgImage: cg), toBitmap: $0.baseAddress!,
                rowBytes: cg.width * 4, bounds: CGRect(x: 0, y: 0, width: cg.width, height: cg.height),
                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        return data
    }

    func testScaleRoundTripBeforeAutomaticTaskStartsCannotPublishOldRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("auto-input-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.tif")
        try MockScannerBackend.writeSyntheticNegative(width: 256, height: 192, to: url)
        let model = AppModel()
        let frame = ScanFrame(scanIndex: 1, rawScanURL: url, filmType: .colorNegative)
        model.frames = [frame]
        defer { model.frames = [] }
        let before = frame.params
        let task = model.autoTone(frame)
        frame.params.baseScale = try FilmBaseScale(1.25)
        frame.params.baseScale = .identity
        await task.value
        XCTAssertEqual(frame.params, before)
    }

    func testNeutralAutoSnapshotRejectsStaleBaseAndKeepsInputSettings() throws {
        let model = AppModel()
        let frame = ScanFrame(scanIndex: 1, rawScanURL: URL(fileURLWithPath: "/tmp/auto-input.tif"), filmType: .colorNegative)
        frame.params.inputGamma = try .power(1.8)
        frame.params.baseScale = try FilmBaseScale(0.75)
        frame.params.autoLevels = true; frame.params.autoNeutralBalance = true
        frame.cachedBase = FilmBase(rgb: SIMD3(0.1, 0.2, 0.3), source: .auto)
        frame.cachedBaseKey = FilmBaseCacheKey(filmType: .bwNegative, mode: .auto, manualBaseRGB: nil, filmStockDminID: nil)
        let tone = model.neutralSnapshot(frame, clearTone: true)
        let wb = model.neutralSnapshot(frame, clearWB: true)
        for snapshot in [tone, wb] {
            XCTAssertNil(snapshot.cachedBase)
            XCTAssertEqual(snapshot.params.inputGamma, frame.params.inputGamma)
            XCTAssertEqual(snapshot.params.baseScale, frame.params.baseScale)
            XCTAssertTrue(snapshot.params.autoLevels); XCTAssertTrue(snapshot.params.autoNeutralBalance)
        }
        frame.cachedBaseKey = tone.baseKey
        XCTAssertNil(model.neutralSnapshot(frame, clearWB: true).cachedBase,
            "matching display base must not change the fixed-size automatic measurement")
    }
}
