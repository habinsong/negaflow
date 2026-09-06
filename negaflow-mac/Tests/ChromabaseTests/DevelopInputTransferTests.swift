import XCTest
@testable import Chromabase

final class DevelopInputTransferTests: XCTestCase {
    func testGammaAndScaleCanBePastedIndependently() throws {
        var source = DevelopParameters(), destination = DevelopParameters()
        source.inputGamma = try .power(1.8); source.baseScale = try FilmBaseScale(0.75)
        source.exposure = 0.5
        destination.inputGamma = try .power(2.4); destination.baseScale = try FilmBaseScale(1.25)
        destination.baseEstimationMode = .manual
        destination.manualBaseRGB = SIMD3(0.7, 0.3, 0.2)
        let gamma = DevelopSettingsPasteScope(base: false, tone: false, color: false, detail: false,
            geometry: false, inputGamma: true, baseScale: false)
        var expected = destination
        expected.inputGamma = source.inputGamma
        XCTAssertEqual(gamma.applying(source: source, to: destination), expected)
        var scale = gamma
        scale.inputGamma = false; scale.baseScale = true
        expected = destination; expected.baseScale = source.baseScale
        XCTAssertEqual(scale.applying(source: source, to: destination), expected)
        XCTAssertFalse(gamma.isEmpty); XCTAssertFalse(scale.isEmpty)
    }

    func testBaseScopeDoesNotOverrideExplicitlyExcludedGammaOrScale() throws {
        var source = DevelopParameters(), destination = DevelopParameters()
        source.inputGamma = try .power(1.8); source.baseScale = try FilmBaseScale(0.75)
        source.baseEstimationMode = .preset; source.filmStockDminID = "vision3-250d"
        destination.inputGamma = try .power(2.4); destination.baseScale = try FilmBaseScale(1.25)
        var scope = DevelopSettingsPasteScope.all
        scope.inputGamma = false; scope.baseScale = false
        let result = scope.applying(source: source, to: destination)
        XCTAssertFalse(scope.isFullDevelopScope)
        XCTAssertEqual(result.inputGamma, destination.inputGamma)
        XCTAssertEqual(result.baseScale, destination.baseScale)
        XCTAssertEqual(result.filmStockDminID, source.filmStockDminID)
    }

    func testScopeCodecKeepsNewFlagsAndMapsLegacyBaseSelection() throws {
        let scope = DevelopSettingsPasteScope(base: false, tone: false, color: false, detail: false,
            geometry: false, inputGamma: true, baseScale: false)
        XCTAssertEqual(try JSONDecoder().decode(DevelopSettingsPasteScope.self,
            from: JSONEncoder().encode(scope)), scope)
        for base in [true, false] {
            let data = Data("{\"base\":\(base),\"tone\":false,\"color\":false,\"detail\":false,\"geometry\":false}".utf8)
            let legacy = try JSONDecoder().decode(DevelopSettingsPasteScope.self, from: data)
            XCTAssertEqual(legacy.inputGamma, base)
            XCTAssertEqual(legacy.baseScale, base)
            XCTAssertEqual(legacy.isEmpty, !base)
        }
    }

    func testUserPresetCodecKeepsAutomaticAndManualInputWithScale() throws {
        for gamma in [InputGammaInterpretation.automatic, try .power(1.8), try .power(2.19921875)] {
            var params = DevelopParameters()
            params.inputGamma = gamma; params.baseScale = try FilmBaseScale(0.75)
            let preset = DevelopUserPreset(name: "입력 설정", params: params, presetID: nil)
            let restored = try JSONDecoder().decode(DevelopUserPreset.self, from: JSONEncoder().encode(preset))
            XCTAssertEqual(restored.params.inputGamma, gamma)
            XCTAssertEqual(restored.params.baseScale, params.baseScale)
        }
    }
}
