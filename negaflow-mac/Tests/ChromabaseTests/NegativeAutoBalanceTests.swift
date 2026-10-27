import CoreImage
import XCTest
@testable import Chromabase

final class NegativeAutoBalanceTests: XCTestCase {
    private let base = SIMD3<Double>(0.8, 0.5, 0.3)
    private func image(_ background: SIMD3<Double>) -> CIImage {
        SyntheticScan.makeImage(width: 128, height: 96) { x, y in
            let d = (40..<88).contains(x) && (30..<66).contains(y)
                ? SIMD3<Double>(0.48, 0.68, 0.70) : background
            return self.base * SIMD3(pow(10, -d.x), pow(10, -d.y), pow(10, -d.z))
        }
    }
    private func pixels(_ image: CIImage) -> [Float] {
        var data = [Float](repeating: 0, count: 128 * 96 * 4)
        ChromabaseEngine.sharedLinearRenderContext.render(image, toBitmap: &data, rowBytes: 128 * 16,
            bounds: CGRect(x: 0, y: 0, width: 128, height: 96), format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
        return data
    }
    /// 화면은 이 규칙으로 자동 밸런스 스위치를 보인다: MAIN 계열(MAIN·PRINT)과 커스텀만이고,
    /// 스캐너 타깃과 EXPIRED 는 자기 반전 도메인이 있어 스위치가 없다.
    func testSwitchExistsOnlyForMainFamilyAndCustomTargets() {
        for target in DevelopTarget.allCases {
            let expected = target == .main || target == .print || target.isCustom
            XCTAssertEqual(target.supportsAutoBalance, expected, "\(target.rawValue)")
        }
        XCTAssertFalse(DevelopTarget.rescue.supportsAutoBalance)
        XCTAssertFalse(DevelopTarget.noritsu.supportsAutoBalance)
        XCTAssertTrue(DevelopTarget.emulsion.supportsAutoBalance)
    }

    func testDefaultAndExplicitOffRoundTrip() throws {
        XCTAssertTrue(DevelopParameters().autoBalance)
        XCTAssertTrue(try JSONDecoder().decode(DevelopParameters.self, from: Data("{}".utf8)).autoBalance)
        var params = DevelopParameters()
        params.autoBalance = false
        let decoded = try JSONDecoder().decode(DevelopParameters.self, from: JSONEncoder().encode(params))
        XCTAssertFalse(decoded.autoBalance)
        XCTAssertFalse(decoded.mainFlatMasterParameters().autoBalance)
    }
    func testOnMatchesOriginalRangeCapCurveAndVibrance() throws {
        let fb = FilmBase(rgb: base, source: .manual)
        for background in [SIMD3<Double>(0.3, 0.5, 0.8), SIMD3(2.0, 1.6, 2.4)] {
            let input = image(background)
            // Original 412bb31 formula: p0.2 range bounded at 1.8D, v4 curve, then muted vibrance.
            var original = try XCTUnwrap(NegativeInversion.sampleStats(input, base: fb))
            for c in 0..<3 { original.dmaxNorm[c] = min(original.dmaxNorm[c], 1.8) }
            let expected = NegativeInversion.applyMutedSceneVibrance(to:
                NegativeInversion.applyDensityEncoding(to: input, stats: original,
                    response: NegativeInversion.response(for: .colorNegative)), monochrome: false)
            let actual = ChromabaseEngine().developScanner(image: input, base: fb, params: .init())
            let a = pixels(actual), b = pixels(expected)
            for i in a.indices { XCTAssertEqual(a[i], b[i], accuracy: 0.00001) }
        }
    }
    func testPresetAndCachedSliderRenderingMatchOriginal() throws {
        let input = image(SIMD3(0.8, 1.2, 1.5))
        let fb = FilmBase(rgb: base, source: .manual)
        let stock = try XCTUnwrap(FilmStockDminRegistry.find("vision3-250d"))
        var params = DevelopParameters()
        params.baseEstimationMode = .preset
        params.filmStockDminID = stock.id
        var state = DevelopSceneMeasurements()
        _ = ChromabaseEngine().developScanner(image: input, base: fb, params: params, measurements: &state)
        var expected = try XCTUnwrap(NegativeInversion.sampleStats(input, base: fb, densityLimit: 1.8))
        expected.dmaxNorm *= stock.relativeRangeFactor
        XCTAssertEqual(state.inversionStats?.dmaxNorm, expected.dmaxNorm)
        XCTAssertNotNil(state.mutedVibranceAmount)
        let before = state
        params.exposure = 0.25
        let reused = pixels(ChromabaseEngine().developScanner(image: input, base: fb, params: params, measurements: &state))
        let fresh = pixels(ChromabaseEngine().developScanner(image: input, base: fb, params: params))
        XCTAssertEqual(before, state)
        for i in reused.indices { XCTAssertEqual(reused[i], fresh[i], accuracy: 0.00001) }
    }
    func testOffUsesSameCurveWithoutSceneNormalizationOrVibrance() throws {
        let fb = FilmBase(rgb: base, source: .manual)
        var params = DevelopParameters()
        params.autoBalance = false
        for input in [image(SIMD3(0.2, 0.4, 0.6)), image(SIMD3(1.5, 0.3, 2.2))] {
            var state = DevelopSceneMeasurements()
            let actual = pixels(ChromabaseEngine().developScanner(image: input, base: fb, params: params, measurements: &state))
            let expected = pixels(NegativeInversion.apply(to: input, base: fb))
            XCTAssertNil(state.mutedVibranceAmount)
            XCTAssertEqual(state.inversionStats?.dmaxNorm, SIMD3(repeating: 1.55))
            for i in actual.indices { XCTAssertEqual(actual[i], expected[i], accuracy: 0.00001) }
        }
    }
    func testOtherTargetsIgnoreSwitch() {
        let input = image(SIMD3(0.8, 0.6, 1.0))
        for target in [DevelopTarget.noritsu, .sp3000, .f135, .hr, .rescue] {
            var params = DevelopParameters()
            params.developTarget = target
            let on = pixels(ChromabaseEngine().developScanner(image: input, base: FilmBase(rgb: base, source: .manual), params: params))
            params.autoBalance = false
            let off = pixels(ChromabaseEngine().developScanner(image: input, base: FilmBase(rgb: base, source: .manual), params: params))
            XCTAssertEqual(on, off)
        }
    }
}
