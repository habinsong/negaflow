import CoreImage
import XCTest
@testable import Chromabase

final class FixedNegativeResponseTests: XCTestCase {
    private let base = SIMD3<Double>(0.84, 0.55, 0.34)
    private let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    private func image(background: SIMD3<Double>, patch: SIMD3<Double>) -> CIImage {
        SyntheticScan.makeImage(width: 96, height: 64) { x, y in
            let d = (32..<64).contains(x) && (20..<44).contains(y) ? patch : background
            return SIMD3(self.base.x * pow(10, -d.x), self.base.y * pow(10, -d.y),
                         self.base.z * pow(10, -d.z))
        }
    }

    private func sample(_ image: CIImage, x: Int = 48) -> SIMD3<Double> {
        var pixel = [Float](repeating: 0, count: 4)
        ChromabaseEngine.sharedLinearRenderContext.render(image, toBitmap: &pixel, rowBytes: 16,
            bounds: CGRect(x: x, y: 32, width: 1, height: 1), format: .RGBAf, colorSpace: space)
        return SIMD3(Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }

    private func develop(_ image: CIImage, _ params: DevelopParameters = .init()) -> SIMD3<Double> {
        sample(ChromabaseEngine().developScanner(image: image,
            base: FilmBase(rgb: base, source: .manual), params: params))
    }

    // Independent idealized forward film: a smooth toe joins a straight D/logE line.
    private func forwardDensity(_ exposure: Double) -> Double {
        let join = 0.60 + 0.62 * log10(0.045 / 0.18)
        if exposure < 0.045 {
            return join * pow(exposure / 0.045, 0.62 / (join * log(10)))
        }
        return 0.60 + 0.62 * log10(exposure / 0.18)
    }

    func testSameDensityIsIndependentOfOtherFramePixelsAndPresetSampling() {
        let patch = SIMD3<Double>(0.48, 0.68, 0.70)
        let backgrounds = [SIMD3<Double>(repeating: 0.1), SIMD3(1.4, 0.2, 0.8),
                           SIMD3(0.3, 1.9, 0.4), SIMD3(repeating: 2.2)]
        for target in [DevelopTarget.main, .print] {
            for stock in [nil, "vision3-250d"] as [String?] {
                var params = DevelopParameters()
                params.developTarget = target
                params.baseEstimationMode = stock == nil ? .manual : .preset
                params.manualBaseRGB = base
                params.filmStockDminID = stock
                let reference = develop(image(background: backgrounds[0], patch: patch), params)
                for background in backgrounds.dropFirst() {
                    let actual = develop(image(background: background, patch: patch), params)
                    for c in 0..<3 { XCTAssertEqual(actual[c], reference[c], accuracy: 1e-5) }
                }
            }
        }
    }

    func testIndependentStraightLineFilmKeepsMiddleExposureAndColorRatios() {
        // Independent forward film model: D = 0.60 + 0.62 log10(E / 0.18).
        for rgb in [SIMD3<Double>(repeating: 0.09), SIMD3(repeating: 0.18),
                    SIMD3(repeating: 0.36), SIMD3(0.12, 0.24, 0.36)] {
            let d = SIMD3(0.60 + 0.62 * log10(rgb.x / 0.18),
                          0.60 + 0.62 * log10(rgb.y / 0.18),
                          0.60 + 0.62 * log10(rgb.z / 0.18))
            let actual = develop(image(background: .init(repeating: 0.5), patch: d))
            for c in 0..<3 { XCTAssertEqual(actual[c], rgb[c], accuracy: 1e-5) }
        }
    }

    func testWBRemovesKnownChannelGainAcrossShadowMidAndHighlight() throws {
        var params = DevelopParameters()
        params.warmth = 0.7
        params.tint = -0.25
        let gain = try XCTUnwrap(WhiteBalanceGains.gains(warmth: params.warmth, tint: params.tint))
        for y in [0.03, 0.09, 0.18, 0.36, 0.8] {
            let cast = SIMD3(forwardDensity(y / gain.x),
                             forwardDensity(y / gain.y),
                             forwardDensity(y / gain.z))
            let actual = develop(image(background: .init(repeating: 0.5), patch: cast), params)
            XCTAssertEqual(actual.x, actual.y, accuracy: 1e-5)
            XCTAssertEqual(actual.y, actual.z, accuracy: 1e-5)
        }
    }

    func testExposureIsAppliedBeforeOutputShoulder() {
        var params = DevelopParameters()
        params.exposure = 1
        let actual = develop(image(background: .init(repeating: 1.0), patch: .init(repeating: 0.60)), params)
        XCTAssertEqual(actual.x, 0.36, accuracy: 1e-5)
        let increased = develop(image(background: .init(repeating: 0.2),
            patch: .init(repeating: 0.60 + 0.62 * log10(2))))
        XCTAssertEqual(actual.x, increased.x, accuracy: 1e-5)
    }

    func testDenseNegativesKeepDistinctHighlightsBeyond18D() {
        var previous = 0.0
        for d in [1.7, 1.8, 1.9, 2.0, 2.2, 3.0] {
            let actual = develop(image(background: .init(repeating: 0.4), patch: .init(repeating: d)))
            XCTAssertTrue(actual.x.isFinite)
            XCTAssertGreaterThan(actual.x, previous)
            XCTAssertLessThan(actual.x, 1)
            previous = actual.x
        }
    }

    func testOutputBoundsEachChannelWithoutDarkeningTheOthers() {
        var previousBlue = 0.0
        for blue in [0.8, 2.0, 20.0, 20_000.0] {
            let input = SyntheticScan.makeImage(width: 96, height: 64) { _, _ in SIMD3(0.12, 0.24, blue) }
            let actual = sample(NegativeLinearResponse.output(input, exposure: 0, filmType: .colorNegative))
            XCTAssertEqual(actual.x, 0.12, accuracy: 1e-6)
            XCTAssertEqual(actual.y, 0.24, accuracy: 1e-6)
            XCTAssertGreaterThan(actual.z, previousBlue)
            XCTAssertLessThan(actual.z, 1)
            previousBlue = actual.z
        }
        // Opposite-signed channels near zero luminance must not create a division pole.
        let signed = SyntheticScan.makeImage(width: 96, height: 64) { _, _ in SIMD3(0.03, -0.008918, 0) }
        let actual = sample(NegativeLinearResponse.output(signed, exposure: 0, filmType: .colorNegative))
        for c in 0..<3 { XCTAssertTrue(actual[c].isFinite); XCTAssertGreaterThanOrEqual(actual[c], 0) }
        XCTAssertLessThan(actual.x, 0.031)
    }

    func testAutoLevelsReachesOutputTargetsAfterCurve() {
        for filmType in [FilmType.colorNegative, .bwNegative] {
            for exposureScale in [1.0, 0.02] {
                let source = SyntheticScan.makeImage(width: 96, height: 64) { x, _ in
                    let exposure = [0.05, 0.18, 1.10][min(x / 32, 2)] * exposureScale
                    let d = self.forwardDensity(exposure)
                    return self.base * pow(10, -d)
                }
                var params = DevelopParameters()
                params.filmType = filmType
                params.autoLevels = true
                let output = ChromabaseEngine().developScanner(image: source,
                    base: FilmBase(rgb: base, source: .manual), params: params)
                let black = sample(output, x: 16), white = sample(output, x: 80)
                for channel in 0..<3 {
                    XCTAssertEqual(black[channel], 0.003, accuracy: 1e-5)
                    XCTAssertEqual(white[channel], 0.95, accuracy: 1e-5)
                }
            }
        }
    }

    func testFilmToePreservesDeepShadowSteps() {
        var previous = 0.0
        for exposure in [0.0, 0.001, 0.002, 0.004, 0.008, 0.016, 0.0225, 0.03, 0.045] {
            let actual = develop(image(background: .init(repeating: 0.6),
                patch: .init(repeating: forwardDensity(exposure))))
            XCTAssertTrue(actual.x.isFinite)
            XCTAssertGreaterThan(actual.x, previous)
            if exposure == 0 { XCTAssertEqual(actual.x, 0.001, accuracy: 1e-6) }
            previous = actual.x
        }
        let low = develop(image(background: .init(repeating: 0.6), patch: .init(repeating: forwardDensity(0.01125))))
        let high = develop(image(background: .init(repeating: 0.6), patch: .init(repeating: forwardDensity(0.0225))))
        XCTAssertEqual(log2(high.x / low.x), 1, accuracy: 0.1)
    }

    func testOutputInverseRoundTripsTargets() {
        for filmType in [FilmType.colorNegative, .bwNegative] {
            let black = filmType == .bwNegative ? 0.0005 : 0.001
            for target in [black, 0.003, 0.004, 0.03, 0.045, 0.18, 0.70, 0.95, 0.99] {
                let scene = NegativeLinearResponse.inputLuminance(forOutput: target, filmType: filmType)
                XCTAssertEqual(NegativeLinearResponse.outputLuminance(scene, filmType: filmType), target, accuracy: 1e-12)
            }
        }
    }

    func testEmptyScannerProfileUsesSameResponseAsNoProfile() {
        let source = image(background: .init(repeating: 0.8), patch: .init(0.48, 0.68, 0.70))
        var params = DevelopParameters()
        let expected = develop(source, params)
        params.scannerProfileID = ""
        let actual = develop(source, params)
        for channel in 0..<3 { XCTAssertEqual(actual[channel], expected[channel], accuracy: 1e-6) }
    }

    func testManualGammaReferenceStaysFixedForNonAdaptiveTargets() throws {
        for target in [DevelopTarget.main, .print, .emulsion] {
            var params = DevelopParameters()
            params.developTarget = target
            params.scannerProfileID = "profile-reference"
            params.inputGamma = try .power(1.8)
            var measurements = DevelopSceneMeasurements()
            // A fixed reference needs no second image decode; this source is Swift text.
            try InputGammaRenderReference.prepare(source: URL(fileURLWithPath: #filePath),
                params: params, measurements: &measurements)
            let range = try XCTUnwrap(measurements.inputGammaReferenceRange)
            XCTAssertEqual(range, SIMD3(repeating: 1.55))
        }
    }

    func testInvalidExposureDoesNotPoisonImage() {
        let source = image(background: .init(repeating: 0.8), patch: .init(repeating: 0.60))
        let expected = develop(source)
        for invalid in [Double.nan, .infinity, -.infinity, 2000, -2000] {
            var params = DevelopParameters()
            params.exposure = invalid
            let actual = develop(source, params)
            for channel in 0..<3 { XCTAssertEqual(actual[channel], expected[channel], accuracy: 1e-6) }
        }
    }

    /// Reconstructs the original default for comparison with the corrected default.
    /// The retained v4 primitive and measured statistics supply the reference; its
    /// original 1.8D cap and automatic vibrance are restored only in this benchmark.
    private func originalDefault(_ input: CIImage) -> CIImage {
        var stats = NegativeInversion.sampleStats(input, base: FilmBase(rgb: base, source: .manual))!
        for c in 0..<3 { stats.dmaxNorm[c] = min(stats.dmaxNorm[c], 1.8) }
        let old = NegativeInversion.applyDensityEncoding(to: input, stats: stats,
            response: NegativeInversion.response(for: .colorNegative))
        return NegativeInversion.applyMutedSceneVibrance(to: old, monochrome: false)
    }

    func testOriginalAndRevisedResponseComparison() throws {
        let patch = SIMD3<Double>(0.48, 0.68, 0.70)
        let backgrounds = [SIMD3<Double>(repeating: 0.1), SIMD3(1.4, 0.2, 0.8),
                           SIMD3(0.3, 1.9, 0.4), SIMD3(repeating: 2.2)]
        var swatches: [[String: Any]] = []
        var oldL: [Double] = [], newL: [Double] = [], oldB: [Double] = [], newB: [Double] = []
        for background in backgrounds {
            let input = image(background: background, patch: patch)
            let old = sample(originalDefault(input)), current = develop(input)
            let before = ColorTargetColorimetry.linearSRGBToLabD50(old)
            let after = ColorTargetColorimetry.linearSRGBToLabD50(current)
            oldL.append(before.l); newL.append(after.l); oldB.append(before.b); newB.append(after.b)
            swatches.append(["background_density": [background.x, background.y, background.z],
                "before_linear_rgb": [old.x, old.y, old.z], "after_linear_rgb": [current.x, current.y, current.z],
                "before_lab_d50": [before.l, before.a, before.b], "after_lab_d50": [after.l, after.a, after.b]])
        }
        func spread(_ values: [Double]) -> Double { values.max()! - values.min()! }
        XCTAssertGreaterThan(spread(oldL), 1)
        XCTAssertLessThan(spread(newL), 0.001)
        XCTAssertLessThan(spread(newB), 0.001)

        let response = NegativeInversion.response(for: .colorNegative)
        func oldCurve(_ e: Double) -> Double {
            let d = forwardDensity(e)
            return response.linearOutput(normalizedDensity: d / 1.55)
        }
        func firstPassCurve(_ e: Double) -> Double {
            let linear = 0.18 * pow(10, (forwardDensity(e) - 0.60) / 0.62)
            return firstPassOutput(linear)
        }
        func firstPassOutput(_ y: Double) -> Double {
            if y < 0.045 {
                let base = 0.18 * pow(10, -0.60 / 0.62)
                let a = log(base / 0.001) / pow(log(0.045 / base), 2)
                return y * exp(-a * pow(log(0.045 / y), 2))
            }
            return y > 0.70 ? 0.70 + 0.30 * (y - 0.70) / (y - 0.70 + 0.30) : y
        }
        func currentCurve(_ e: Double) -> Double {
            NegativeLinearResponse.outputLuminance(e, filmType: .colorNegative)
        }
        func logContrast(_ e: Double, _ curve: (Double) -> Double) -> Double {
            let h = 0.0001
            return log(curve(e * exp(h)) / curve(e * exp(-h))) / (2 * h)
        }
        let tones = [-3, -2, -1, 0, 1, 2, 3].map { ev -> [String: Any] in
            let e = 0.18 * pow(2, Double(ev))
            return ["ev": ev, "scene_linear": e, "before": oldCurve(e), "after": currentCurve(e),
                "first_pass": firstPassCurve(e), "first_pass_log_contrast": logContrast(e, firstPassCurve),
                "before_log_contrast": logContrast(e, oldCurve), "after_log_contrast": logContrast(e, currentCurve)]
        }
        var wbParams = DevelopParameters()
        wbParams.warmth = 0.7; wbParams.tint = -0.25
        let gain = try XCTUnwrap(WhiteBalanceGains.gains(warmth: wbParams.warmth, tint: wbParams.tint))
        func castInput(_ y: Double) -> CIImage {
            image(background: .init(repeating: 1.2),
                patch: SIMD3(forwardDensity(y / gain.x), forwardDensity(y / gain.y), forwardDensity(y / gain.z)))
        }
        let oldMid = sample(originalDefault(castInput(0.18)))
        let neutralMid = pow(oldMid.x * oldMid.y * oldMid.z, 1.0 / 3)
        let oldGain = SIMD3(repeating: neutralMid) / oldMid
        var beforeC: [Double] = [], firstPassC: [Double] = [], afterC: [Double] = [], wb: [[String: Any]] = []
        var parityCases: [[String: Any]] = []
        for y in [0.03, 0.09, 0.18, 0.36, 0.8] {
            let input = castInput(y)
            let before = sample(originalDefault(input).applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: oldGain.x, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: oldGain.y, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: oldGain.z, w: 0)]))
            let after = develop(input, wbParams)
            let density = SIMD3(forwardDensity(y / gain.x), forwardDensity(y / gain.y), forwardDensity(y / gain.z))
            var firstPass = SIMD3(0.18 * pow(10, (density.x - 0.60) / 0.62),
                0.18 * pow(10, (density.y - 0.60) / 0.62), 0.18 * pow(10, (density.z - 0.60) / 0.62)) * gain
            let luminance = 0.2126 * firstPass.x + 0.7152 * firstPass.y + 0.0722 * firstPass.z
            firstPass *= firstPassOutput(luminance) / luminance
            let transmission = SIMD3(base.x * pow(10, -density.x), base.y * pow(10, -density.y), base.z * pow(10, -density.z))
            parityCases.append(["input_transmission": [transmission.x, transmission.y, transmission.z],
                "warmth": wbParams.warmth, "tint": wbParams.tint,
                "mac_output": [after.x, after.y, after.z]])
            let middle = ColorTargetColorimetry.linearSRGBToLabD50(firstPass)
            firstPassC.append(hypot(middle.a, middle.b))
            let a = ColorTargetColorimetry.linearSRGBToLabD50(before)
            let b = ColorTargetColorimetry.linearSRGBToLabD50(after)
            beforeC.append(hypot(a.a, a.b)); afterC.append(hypot(b.a, b.b))
            wb.append(["scene_linear": y, "before_chroma": beforeC.last!, "first_pass_chroma": firstPassC.last!, "after_chroma": afterC.last!])
        }
        XCTAssertLessThan(afterC.max()!, 0.001)
        let report: [String: Any] = ["renderer": "fixed-density-linear-v6",
            "base_transmission": [base.x, base.y, base.z], "patch_density": [patch.x, patch.y, patch.z],
            "wb_settings": ["warmth": 0.7, "tint": -0.25],
            "parity_cases": parityCases,
            "tone_input_model": "idealized C1 film toe below 0.045, straight D/logE above; not measured film data",
            "scope": "synthetic; fixed base/settings; not the Reddit 18-frame roll",
            "swatches": swatches, "before_L_spread": spread(oldL), "after_L_spread": spread(newL),
            "before_b_spread": spread(oldB), "after_b_spread": spread(newB), "tone_wedge": tones,
            "wb_neutral_wedge": wb, "before_max_chroma": beforeC.max()!, "first_pass_max_chroma": firstPassC.max()!, "after_max_chroma": afterC.max()!,
            "previous_auto_levels_white": firstPassOutput(0.95), "after_auto_levels_white": 0.95,
            "previous_auto_levels_black": firstPassOutput(0.003), "after_auto_levels_black": 0.003]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if let output = ProcessInfo.processInfo.environment["NEGAFLOW_RESPONSE_COMPARISON"] {
            try json.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
        print("[response-review] L* spread \(spread(oldL)) -> \(spread(newL)); b* spread \(spread(oldB)) -> \(spread(newB))")
    }

    /// Opt-in real demo roll check. Reuses each frame's measured legacy settings on
    /// one identical density patch; this checks consistency, not color accuracy.
    func testBundledRollFrameConsistency() throws {
        guard let output = ProcessInfo.processInfo.environment["NEGAFLOW_RESPONSE_ROLL_DIR"] else {
            throw XCTSkip("Set NEGAFLOW_RESPONSE_ROLL_DIR to compare the bundled 18-frame roll")
        }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ScannerKit/Resources/Roll_Perforation.tiff")
        let source = try XCTUnwrap(ImageLoader.loadScannerTIFF(fixture))
        let frames = try FlatbedFrameDetector.detect(url: fixture)
        XCTAssertEqual(frames.count, 18)
        let filmBase = try XCTUnwrap(FilmBaseEstimator.estimate(from: source))
        let grid = try XCTUnwrap(FilmBaseSampleGrid(image: source))
        let component = try XCTUnwrap(FilmBaseEstimator.connectedBaseComponent(from: grid, neutralBase: false))
        let excluded = FilmBaseEstimator.nonFilmExclusion(for: grid, neutralBase: false)
        let legacyRebate = try XCTUnwrap(FilmBaseRebate.rebateBase(image: source, grid: grid,
            neutralBase: false, gateOpen: true, nonFilmExclusion: { excluded }))
        XCTAssertTrue(FilmBaseEstimator.looksLikeLight(legacyRebate.rgb, comparedWith: component.rgb))
        for c in 0..<3 { XCTAssertEqual(filmBase.rgb[c], component.rgb[c], accuracy: 1e-5) }
        let patchDensity = SIMD3<Double>(0.48, 0.68, 0.70)
        let patchRGB = SIMD3(filmBase.rgb.x * pow(10, -patchDensity.x),
            filmBase.rgb.y * pow(10, -patchDensity.y), filmBase.rgb.z * pow(10, -patchDensity.z))
        let marker = CIImage(color: CIColor(red: patchRGB.x, green: patchRGB.y, blue: patchRGB.z,
            alpha: 1, colorSpace: space)!).cropped(to: CGRect(x: 32, y: 20, width: 32, height: 24))
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let engine = ChromabaseEngine()
        var rows: [[String: Any]] = []
        var beforeL: [Double] = [], beforeB: [Double] = [], afterL: [Double] = [], afterB: [Double] = []
        var cappedBlueFrames = 0
        for frame in frames {
            // Detector coordinates have a top-left origin; Core Image uses bottom-left.
            let n = frame.normalizedRect
            let rect = CGRect(x: n.minX * source.extent.width,
                y: (1 - n.maxY) * source.extent.height,
                width: n.width * source.extent.width, height: n.height * source.extent.height).integral
            let crop = source.cropped(to: rect)
                .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            var stats = try XCTUnwrap(NegativeInversion.sampleStats(crop, base: filmBase))
            let uncapped = stats.dmaxNorm
            if uncapped.z > 1.8 { cappedBlueFrames += 1 }
            for c in 0..<3 { stats.dmaxNorm[c] = min(stats.dmaxNorm[c], 1.8) }
            let legacy = NegativeInversion.applyDensityEncoding(to: crop, stats: stats,
                response: NegativeInversion.response(for: .colorNegative))
            var vibrance: Double?
            let before = NegativeInversion.applyMutedSceneVibrance(to: legacy,
                monochrome: false, amount: &vibrance)
            let legacyPatch = NegativeInversion.applyDensityEncoding(to: marker, stats: stats,
                response: NegativeInversion.response(for: .colorNegative))
            let beforePatch = sample(NegativeInversion.applyMutedSceneVibrance(to: legacyPatch,
                monochrome: false, amount: &vibrance))
            let after = engine.developScanner(image: crop, base: filmBase, params: .init())
            let afterPatch = sample(engine.developScanner(image: marker.composited(over: crop),
                base: filmBase, params: .init()))
            let oldLab = ColorTargetColorimetry.linearSRGBToLabD50(beforePatch)
            let newLab = ColorTargetColorimetry.linearSRGBToLabD50(afterPatch)
            beforeL.append(oldLab.l); beforeB.append(oldLab.b)
            afterL.append(newLab.l); afterB.append(newLab.b)
            let id = "S\(frame.row + 1)F\(frame.column + 1)"
            rows.append(["frame": id, "normalized_rect": [n.minX, n.minY, n.width, n.height],
                "before_density_range": [stats.dmaxNorm.x, stats.dmaxNorm.y, stats.dmaxNorm.z],
                "uncapped_density_range": [uncapped.x, uncapped.y, uncapped.z],
                "before_vibrance": vibrance ?? 0,
                "before_patch_rgb": [beforePatch.x, beforePatch.y, beforePatch.z],
                "after_patch_rgb": [afterPatch.x, afterPatch.y, afterPatch.z],
                "before_patch_lab": [oldLab.l, oldLab.a, oldLab.b],
                "after_patch_lab": [newLab.l, newLab.a, newLab.b]])
            let scale = min(1, 420 / crop.extent.width)
            for (label, image) in [("before", before), ("after", after)] {
                try ChromabaseEngine.sharedLinearRenderContext.writePNGRepresentation(
                    of: DisplayGamutMap.apply(to: image)
                        .transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
                    to: directory.appendingPathComponent("\(id)-\(label).png"), format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            }
        }
        func spread(_ x: [Double]) -> Double { x.max()! - x.min()! }
        XCTAssertGreaterThan(spread(beforeL), 1)
        XCTAssertLessThan(spread(afterL), 0.001)
        XCTAssertLessThan(spread(afterB), 0.001)
        let report: [String: Any] = ["source": fixture.lastPathComponent, "frames": rows,
            "method": "one estimated roll base held fixed; legacy settings measured per frame before inserting identical patch; current defaults; no color accuracy reference",
            "base_transmission": [filmBase.rgb.x, filmBase.rgb.y, filmBase.rgb.z],
            "rejected_legacy_rebate": [legacyRebate.rgb.x, legacyRebate.rgb.y, legacyRebate.rgb.z],
            "patch_density": [patchDensity.x, patchDensity.y, patchDensity.z],
            "before_L_spread": spread(beforeL), "after_L_spread": spread(afterL),
            "before_b_spread": spread(beforeB), "after_b_spread": spread(afterB),
            "original_blue_18D_cap_frame_count": cappedBlueFrames]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("roll-comparison.json"), options: .atomic)
        print("[response-roll] 18 frames; L* spread \(spread(beforeL)) -> \(spread(afterL)); b* spread \(spread(beforeB)) -> \(spread(afterB)); B cap \(cappedBlueFrames)/18")
    }

}
