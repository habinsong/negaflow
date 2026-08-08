import XCTest
@testable import Chromabase

final class ColorTargetColorimetryTests: XCTestCase {
    func testLinearSRGBPrimariesConvertThroughBradfordToLabD50() {
        let samples: [(SIMD3<Double>, ColorTargetLab)] = [
            (SIMD3(1.0, 1.0, 1.0), ColorTargetLab(l: 100.0, a: 0.0, b: 0.0)),
            (SIMD3(0.0, 0.0, 0.0), ColorTargetLab(l: 0.0, a: 0.0, b: 0.0)),
            (SIMD3(1.0, 0.0, 0.0), ColorTargetLab(l: 54.2917, a: 80.8125, b: 69.8851)),
            (SIMD3(0.0, 1.0, 0.0), ColorTargetLab(l: 87.8181, a: -79.2873, b: 80.9903)),
            (SIMD3(0.0, 0.0, 1.0), ColorTargetLab(l: 29.5676, a: 68.2986, b: -112.0294)),
        ]

        for (rgb, expected) in samples {
            let actual = ColorTargetColorimetry.linearSRGBToLabD50(rgb)
            XCTAssertEqual(actual.l, expected.l, accuracy: 0.002, "RGB: \(rgb)")
            XCTAssertEqual(actual.a, expected.a, accuracy: 0.002, "RGB: \(rgb)")
            XCTAssertEqual(actual.b, expected.b, accuracy: 0.002, "RGB: \(rgb)")
        }
    }

    func testLinearSRGBConversionDoesNotClampExtendedValues() {
        let overRange = ColorTargetColorimetry.linearSRGBToLabD50(SIMD3(repeating: 2.0))
        let belowRange = ColorTargetColorimetry.linearSRGBToLabD50(SIMD3(repeating: -0.1))

        XCTAssertGreaterThan(overRange.l, 100.0)
        XCTAssertLessThan(belowRange.l, 0.0)
        XCTAssertTrue([overRange.l, overRange.a, overRange.b].allSatisfy(\.isFinite))
        XCTAssertTrue([belowRange.l, belowRange.a, belowRange.b].allSatisfy(\.isFinite))
    }

    func testLinearSRGBMidGrayIsNotDecodedAsGammaEncodedSRGB() {
        let actual = ColorTargetColorimetry.linearSRGBToLabD50(SIMD3(repeating: 0.5))

        XCTAssertEqual(actual.l, 76.0693, accuracy: 0.0001)
        XCTAssertEqual(actual.a, 0.0, accuracy: 0.0001)
        XCTAssertEqual(actual.b, 0.0, accuracy: 0.0001)
    }

    func testDeltaE2000MatchesSharmaReferencePairs() {
        let pairs: [(ColorTargetLab, ColorTargetLab, Double)] = [
            (lab(50.0000, 2.6772, -79.7751), lab(50.0000, 0.0000, -82.7485), 2.0425),
            (lab(50.0000, 3.1571, -77.2803), lab(50.0000, 0.0000, -82.7485), 2.8615),
            (lab(50.0000, 2.8361, -74.0200), lab(50.0000, 0.0000, -82.7485), 3.4412),
            (lab(50.0000, -1.3802, -84.2814), lab(50.0000, 0.0000, -82.7485), 1.0000),
            (lab(50.0000, 0.0000, 0.0000), lab(50.0000, -1.0000, 2.0000), 2.3669),
            (lab(50.0000, 2.4900, -0.0010), lab(50.0000, -2.4900, 0.0011), 7.2195),
            (lab(50.0000, -0.0010, 2.4900), lab(50.0000, 0.0009, -2.4900), 4.8045),
            (lab(50.0000, -0.0010, 2.4900), lab(50.0000, 0.0011, -2.4900), 4.7461),
            (lab(60.2574, -34.0099, 36.2677), lab(60.4626, -34.1751, 39.4387), 1.2644),
        ]

        for (first, second, expected) in pairs {
            XCTAssertEqual(
                ColorTargetColorimetry.deltaE2000(first, second),
                expected,
                accuracy: 0.000_1,
                "first=\(first), second=\(second)"
            )
        }
    }

    func testDeltaE2000IsSymmetricAndZeroForIdentity() {
        let first = lab(42.0, -18.5, 37.25)
        let second = lab(71.5, 22.0, -4.75)

        XCTAssertEqual(ColorTargetColorimetry.deltaE2000(first, first), 0.0, accuracy: 1e-12)
        XCTAssertEqual(
            ColorTargetColorimetry.deltaE2000(first, second),
            ColorTargetColorimetry.deltaE2000(second, first),
            accuracy: 1e-12
        )
    }

    private func lab(_ l: Double, _ a: Double, _ b: Double) -> ColorTargetLab {
        ColorTargetLab(l: l, a: a, b: b)
    }
}
