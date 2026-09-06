import XCTest
@testable import Chromabase
@testable import negaflowApp

final class InputGammaPreviewMeasurementsTests: XCTestCase {
    func testMeasurementsAreBoundedAndCannotCrossInputOrScale() throws {
        let owner = NSObject()
        let source = ObjectIdentifier(owner)
        var cache = InputGammaPreviewMeasurements()
        func key(_ gamma: Double, scale: Double = 1, rawRevision: Int = 1) throws -> InputGammaPreviewMeasurements.Key {
            var params = DevelopParameters()
            params.inputGamma = try .power(gamma)
            params.baseScale = try FilmBaseScale(scale)
            return .init(source: source, sourceRevision: 1, rawRevision: rawRevision,
                params: params, filmType: .colorNegative, preset: nil, dimension: 1536)
        }
        let stored = InputGammaPreviewMeasurements.Value(base: FilmBase(rgb: SIMD3(repeating: 0.7), source: .auto),
            measurements: DevelopSceneMeasurements())
        for index in 1...40 { cache.store(stored, for: try key(Double(index) / 10)) }
        XCTAssertEqual(cache.count, 40)
        XCTAssertNotNil(cache.value(for: try key(1.8)))
        XCTAssertNil(cache.value(for: try key(1.8, scale: 0.75)))
        XCTAssertNil(cache.value(for: try key(1.8, rawRevision: 2)))
        cache.store(stored, for: try key(1.8, scale: 0.75))
        XCTAssertEqual(cache.count, 40)
        XCTAssertNil(cache.value(for: try key(0.1)))
        cache.clear()
        XCTAssertEqual(cache.count, 0)
    }
}
