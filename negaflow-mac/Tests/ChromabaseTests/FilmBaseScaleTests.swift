import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class FilmBaseScaleTests: XCTestCase {
    func testBoundsAndNonfiniteValuesAreRejected() throws {
        for value in [0.49, 1.51, .infinity, -.infinity, .nan] {
            XCTAssertThrowsError(try FilmBaseScale(value))
        }
        XCTAssertEqual(try FilmBaseScale(0.5).value, 0.5)
        XCTAssertEqual(try FilmBaseScale(1.5).value, 1.5)
    }

    func testChannelClampingAndRepeatDoNotChangeReference() throws {
        let reference = SIMD3<Double>(0.77, 0.25, 0.16)
        let half = try FilmBaseScale(0.5)
        let more = try FilmBaseScale(1.5)
        XCTAssertEqual(half.applied(to: reference), SIMD3(0.385, 0.125, 0.08))
        XCTAssertEqual(more.applied(to: reference), SIMD3(1, 0.375, 0.24))
        XCTAssertEqual(FilmBaseScale.identity.applied(to: reference), reference)
        XCTAssertEqual(half.applied(to: reference), SIMD3(0.385, 0.125, 0.08))
        XCTAssertEqual(more.applied(to: SIMD3(0, 0.8, 1)), SIMD3(0, 1, 1))
    }

    func testScaledAutoMatchesDirectBaseWithoutChangingInversion() throws {
        let image = makeNegative()
        let base = FilmBase(rgb: SIMD3(0.77, 0.25, 0.16), source: .auto)
        let engine = ChromabaseEngine()
        for value in [0.5, 0.75, 1, 1.25, 1.5] {
            var params = DevelopParameters()
            params.baseScale = try FilmBaseScale(value)
            let scaled = engine.developScanner(image: image, base: base, params: params)
            let directBase = FilmBase(rgb: params.baseScale.applied(to: base.rgb), source: .auto)
            params.baseScale = .identity
            let direct = engine.developScanner(image: image, base: directBase, params: params)
            XCTAssertEqual(pixels(scaled), pixels(direct), "scale=\(value)")
        }
    }

    func testManualAndPresetIgnoreStoredScale() throws {
        let image = makeNegative()
        let base = FilmBase(rgb: SIMD3(0.77, 0.25, 0.16), source: .auto)
        let engine = ChromabaseEngine()
        for mode in [DevelopParameters.BaseMode.manual, .preset] {
            var params = DevelopParameters()
            params.baseEstimationMode = mode
            params.manualBaseRGB = base.rgb
            params.filmStockDminID = mode == .preset ? "vision3-250d" : nil
            let expected = pixels(engine.developScanner(image: image, base: base, params: params))
            for scale in [0.5, 1.5] {
                params.baseScale = try FilmBaseScale(scale)
                XCTAssertEqual(pixels(engine.developScanner(image: image, base: base, params: params)), expected)
            }
        }
    }

    func testDefaultKeysAreOmittedAndNondefaultsRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let defaults = try encoder.encode(DevelopParameters())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: defaults) as? [String: Any])
        XCTAssertNil(object["baseScale"])
        XCTAssertNil(object["inputGamma"])
        var params = DevelopParameters()
        params.baseScale = try FilmBaseScale(0.75)
        params.inputGamma = try .power(1.8)
        params.manualBaseRGB = SIMD3(0.7, 0.2, 0.1)
        params.scannerProfileID = "test-scanner"
        params.lightSourceProfileID = "test-light"
        params.isDigitalSource = false
        params.exposure = 0.35
        let encoded = try encoder.encode(params)
        XCTAssertEqual(try JSONDecoder().decode(DevelopParameters.self, from: encoded), params)
        XCTAssertEqual(try encoder.encode(JSONDecoder().decode(DevelopParameters.self, from: defaults)), defaults)
    }

    func testInvalidPresentFieldsDoNotBecomeDefaults() {
        for json in ["{\"baseScale\":null}", "{\"baseScale\":0}", "{\"baseScale\":2}",
                     "{\"inputGamma\":null}", "{\"inputGamma\":0}", "{\"inputGamma\":4.01}",
                     "{\"inputGamma\":\"1.8\"}", "{\"inputGamma\":\"linear\"}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(DevelopParameters.self, from: Data(json.utf8)), json)
        }
    }

    func testGammaAndScalePasteScopesAreIndependent() throws {
        var source = DevelopParameters()
        source.baseScale = try FilmBaseScale(0.5)
        source.inputGamma = try .power(1)
        var target = DevelopParameters()
        target.inputGamma = try .power(2.2)
        let pasted = DevelopSettingsPasteScope.all.applying(source: source, to: target)
        XCTAssertEqual(pasted.baseScale, source.baseScale)
        XCTAssertEqual(pasted.inputGamma, source.inputGamma)
        let toneOnly = DevelopSettingsPasteScope(base: false, tone: true, color: false, detail: false, geometry: false)
        XCTAssertEqual(toneOnly.applying(source: source, to: target).baseScale, .identity)
    }

    private func makeNegative() -> CIImage {
        var samples = [Float]()
        for i in 0..<512 {
            let t = Float(i + 16) / 528
            samples.append(contentsOf: [0.65 * t, 0.20 * t, 0.14 * t, 1])
        }
        let data = samples.withUnsafeBytes { Data($0) }
        return CIImage(bitmapData: data, bytesPerRow: 32 * 16, size: CGSize(width: 32, height: 16),
                       format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
    }

    private func pixels(_ image: CIImage) -> [Float] {
        var samples = [Float](repeating: 0, count: 32 * 16 * 4)
        ChromabaseEngine.sharedLinearRenderContext.render(
            image, toBitmap: &samples, rowBytes: 32 * 16,
            bounds: CGRect(x: 0, y: 0, width: 32, height: 16), format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)
        )
        return samples
    }
}
