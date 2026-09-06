import XCTest
import simd
@testable import Chromabase

final class InputGammaEstimatorTests: XCTestCase {
    func testRecoversKnownPowerAcrossIndependentColorEdges() throws {
        for gamma in [0.22, 0.5, 1, 1.8, 2.2, 3.5] {
            let estimate = try XCTUnwrap(InputGammaEstimator.estimate(edges(gamma: gamma)))
            XCTAssertEqual(estimate.gamma, gamma, accuracy: 0.015)
            XCTAssertGreaterThanOrEqual(estimate.evidence, 0.65)
        }
    }

    func testRejectsFlatGrayClippedAndSpatiallySparseSamples() {
        XCTAssertNil(InputGammaEstimator.estimate([]))
        for value in [0.0, 0.4, 1.0] {
            let flat = (0..<128).map { InputGammaEstimator.Edge(samples: Array(repeating: SIMD3(repeating: value), count: 9), tile: $0 % 16) }
            XCTAssertNil(InputGammaEstimator.estimate(flat))
        }
        XCTAssertNil(InputGammaEstimator.estimate(edges(gamma: 2.2).map { .init(samples: $0.samples, tile: 0) }))
    }

    func testRejectsDisagreementBetweenSpatialHoldouts() {
        let first = edges(gamma: 1), second = edges(gamma: 2.4)
        let mixed = zip(first, second).map { a, b in (a.tile / 4 + a.tile % 4).isMultiple(of: 2) ? a : b }
        XCTAssertNil(InputGammaEstimator.estimate(mixed))
    }

    private func edges(gamma: Double) -> [InputGammaEstimator.Edge] {
        (0..<256).map { index in
            let offset = Double(index % 17) * 0.008
            let a = SIMD3(pow(0.08 + offset, gamma), pow(0.4 + offset, gamma), pow(0.14 + offset, gamma))
            let b = SIMD3(pow(0.65 - offset, gamma), pow(0.2 + offset, gamma), pow(0.75 - offset, gamma))
            let samples = [0.0, 0, 0.15, 0.32, 0.5, 0.72, 0.9, 1, 1].map { weight in
                let linear = a + weight * (b - a)
                return SIMD3(pow(linear.x, 1 / gamma), pow(linear.y, 1 / gamma), pow(linear.z, 1 / gamma))
            }
            return InputGammaEstimator.Edge(samples: samples, tile: index % 16)
        }
    }
}
