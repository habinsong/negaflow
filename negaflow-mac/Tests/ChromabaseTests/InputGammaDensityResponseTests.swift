import XCTest
import CoreImage
@testable import Chromabase

final class InputGammaDensityResponseTests: XCTestCase {
    func testManualGammaChangesDensityContinuouslyInsteadOfRenormalizingItAway() throws {
        var previous: Float = -1
        for value in [0.22, 0.32, 0.33, 0.34, 0.5, 1, 1.8, 2.2, 3, 4] {
            var params = DevelopParameters()
            params.filmType = .colorNegative
            params.inputGamma = try .power(value)
            params.baseEstimationMode = .manual
            params.manualBaseRGB = SIMD3(repeating: pow(0.85, value))
            let sample = pow(0.35, value)
            let color = try XCTUnwrap(CIColor(red: sample, green: sample, blue: sample,
                colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!))
            let input = CIImage(color: color)
                .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
            var measurements = DevelopSceneMeasurements()
            let output = ChromabaseEngine().developScanner(image: input, base: nil, params: params, measurements: &measurements)
            var pixel = [Float](repeating: 0, count: 4)
            ChromabaseEngine.sharedLinearRenderContext.render(output, toBitmap: &pixel, rowBytes: 16,
                bounds: CGRect(x: 32, y: 32, width: 1, height: 1), format: .RGBAf,
                colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
            XCTAssertGreaterThan(pixel[0], previous, "gamma \(value)")
            XCTAssertEqual(try XCTUnwrap(measurements.inversionStats).dmaxNorm.x, NegativeInversion.colorResponse.normalRange)
            let debug = ChromabaseEngine().developDebugFramesScanner(image: input, base: nil, params: params)
            let metrics = try XCTUnwrap(debug.first?.metrics)
            let debugRange = try XCTUnwrap(metrics.dmaxNorm)
            XCTAssertEqual(debugRange.x, NegativeInversion.colorResponse.normalRange)
            previous = pixel[0]
        }
    }
}
