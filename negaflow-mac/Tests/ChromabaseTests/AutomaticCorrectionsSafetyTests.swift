import CoreImage
import CoreGraphics
import XCTest
@testable import Chromabase

final class AutomaticCorrectionsSafetyTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private func flat(_ rgb: [UInt8]) -> CGImage {
        var bytes = [UInt8](); bytes.reserveCapacity(64 * 64 * 4)
        for _ in 0..<(64 * 64) { bytes += [rgb[0], rgb[1], rgb[2], 255] }
        return CGImage(width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 256,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    private func pixel(_ image: CIImage, x: Int = 128, y: Int = 64) -> SIMD3<Double> {
        var p = [Float](repeating: 0, count: 4)
        ChromabaseEngine.sharedLinearRenderContext.render(image, toBitmap: &p, rowBytes: 16,
            bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBAf, colorSpace: linear)
        return SIMD3(Double(p[0]), Double(p[1]), Double(p[2]))
    }
    func testEqualLuminanceColorsReceiveTheSameExposure() throws {
        let gray = AutoAdjust.autoTone(try XCTUnwrap(AutoAdjust.imageStats(flat([118,118,118]))))
        let red = AutoAdjust.autoTone(try XCTUnwrap(AutoAdjust.imageStats(flat([237,0,0]))))
        XCTAssertEqual(gray.exposure, red.exposure, accuracy: 0.03)
        XCTAssertEqual(gray.vibrance, 0)
        XCTAssertEqual(red.vibrance, 0)
    }
    func testLevelsPreserveNeutralAndChromaticRatios() {
        let image = SyntheticScan.makeImage(width: 256, height: 128) { x, _ in
            if (110..<145).contains(x) { return SIMD3(repeating: 0.2) }
            let t = Double(x) / 255
            return SIMD3(0.05 + 0.35 * t, 0.05 + 0.65 * t, 0.05 + 0.90 * t)
        }
        let output = AutoLevels.apply(to: image, sampleColorSpace: linear, outputWhite: 0.95, outputBlack: 0.003)
        let neutral = pixel(output)
        XCTAssertEqual(neutral.x, neutral.y, accuracy: 1e-5)
        XCTAssertEqual(neutral.y, neutral.z, accuracy: 1e-5)
        let before = pixel(image, x: 180), after = pixel(output, x: 180)
        XCTAssertEqual(before.x / before.z, after.x / after.z, accuracy: 1e-5)
        XCTAssertEqual(before.y / before.z, after.y / after.z, accuracy: 1e-5)
    }
    func testWeakWhiteBalanceEvidenceIsDampedAndClippedChannelsAreExcluded() throws {
        let warm = AutoAdjust.autoWhiteBalance(try XCTUnwrap(AutoAdjust.imageStats(flat([180,120,75]))))
        XCTAssertLessThan(abs(warm.warmth), 0.4)
        let clipped = try XCTUnwrap(AutoAdjust.imageStats(flat([255,120,100])))
        XCTAssertEqual(clipped.clippedFraction, 1, accuracy: 1e-5)
        let wb = AutoAdjust.autoWhiteBalance(clipped)
        XCTAssertEqual(wb.warmth, 0); XCTAssertEqual(wb.tint, 0)
        let tiny = flat([180,120,75]).cropping(to: CGRect(x: 0, y: 0, width: 4, height: 4))!
        let unsupported = AutoAdjust.autoWhiteBalance(try XCTUnwrap(AutoAdjust.imageStats(tiny)))
        XCTAssertEqual(unsupported.warmth, 0); XCTAssertEqual(unsupported.tint, 0)
    }
    func testAutoColorPreservesAnUnsupportedSingleSubjectColor() {
        let image = CIImage(color: CIColor(red: 0.4, green: 0.2, blue: 0.1, alpha: 1, colorSpace: linear)!)
            .cropped(to: CGRect(x: 0, y: 0, width: 256, height: 128))
        let output = pixel(NeutralBalance.apply(to: image, sampleColorSpace: linear))
        XCTAssertLessThan(abs(log(output.x / output.z) - log(4)), 0.12)
    }
    func testPortraitMeasurementHasABoundedSampleCount() throws {
        let image = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1, colorSpace: linear)!)
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 4096))
        let grid = try XCTUnwrap(SceneAnalysisSampler.sample(image, longEdge: 256))
        XCTAssertEqual(grid.width, 1); XCTAssertEqual(grid.height, 256)
        XCTAssertEqual(grid.pixels.count, 256)
        XCTAssertEqual(grid.pixels[127].x, 0.2, accuracy: 1e-5)
    }
    func testToneScorePenalizesChannelClipping() throws {
        let clipped = try XCTUnwrap(AutoAdjust.imageStats(flat([255,120,100])))
        let safe = try XCTUnwrap(AutoAdjust.imageStats(flat([245,120,100])))
        XCTAssertGreaterThan(AutoAdjust.toneScore(clipped, adjustMid: false), AutoAdjust.toneScore(safe, adjustMid: false))
    }
    func testSlopeFitNeedsIndependentBandSupport() {
        let bands = (0..<6).map { i in
            NeutralAxisEvidence.Band(logLuminance: -4 + Double(i) * 0.7,
                cast: SIMD3(i % 2 == 0 ? 0.15 : -0.15, 0, 0), count: 50)
        }
        let result = NeutralBalance.fit(NeutralAxisEvidence(bands: bands, selectedFraction: 1), strength: 1)
        XCTAssertEqual(result.slope, SIMD3(repeating: 1))
    }
}
