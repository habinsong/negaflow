import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import Chromabase

/// 흰색/검정 계열 슬라이더 범위를 ±2 로 넓힌 계약.
///
/// 넓히면서 지켜야 하는 것: ±1 구간의 결과가 이전과 같을 것, 확장 구간이 실제로 더 밀 것,
/// 자동 톤/자동 화이트밸런스가 내는 값이 여전히 범위 안에 있을 것.
final class BasicToneExtendedRangeTests: XCTestCase {

    func testRangeIsPlusMinusTwo() {
        XCTAssertEqual(DevelopToneRange.whites.lowerBound, -2, accuracy: 1e-9)
        XCTAssertEqual(DevelopToneRange.whites.upperBound, 2, accuracy: 1e-9)
        XCTAssertEqual(DevelopToneRange.blacks.lowerBound, -2, accuracy: 1e-9)
        XCTAssertEqual(DevelopToneRange.blacks.upperBound, 2, accuracy: 1e-9)
    }

    /// 자동 톤은 스스로 whites -1...1, blacks -1...0.15 로 제한한다 — 넓힌 범위 안이어야 한다.
    func testAutoToneStaysInsideTheWidenedRange() {
        for luminance in stride(from: 0.05, through: 0.95, by: 0.15) {
            let stats = Self.stats(luminance: luminance)
            let delta = AutoAdjust.autoTone(stats)
            XCTAssertTrue(DevelopToneRange.whites.contains(delta.whites),
                          "whites \(delta.whites) 가 범위 밖")
            XCTAssertTrue(DevelopToneRange.blacks.contains(delta.blacks),
                          "blacks \(delta.blacks) 가 범위 밖")
        }
    }

    /// 확장 구간이 실제로 더 밀어야 한다(±1 에서 포화되면 슬라이더만 길어진 셈).
    func testWhitesAndBlacksKeepPushingBeyondOne() throws {
        let ramp = Self.rampImage()
        let atOne = try Self.meanLuma(ramp, whites: 1, blacks: 0)
        let atTwo = try Self.meanLuma(ramp, whites: 2, blacks: 0)
        XCTAssertGreaterThan(atTwo, atOne + 1e-4, "whites 가 +1 에서 포화됐다")

        let blackAtOne = try Self.meanLuma(ramp, whites: 0, blacks: -1)
        let blackAtTwo = try Self.meanLuma(ramp, whites: 0, blacks: -2)
        XCTAssertLessThan(blackAtTwo, blackAtOne - 1e-4, "blacks 가 −1 에서 포화됐다")
    }

    /// ±1 구간은 이전 동작 그대로여야 한다 — 계수·마스크를 바꾸지 않았다는 증거.
    func testInRangeValuesAreUnchangedByTheClamp() throws {
        let ramp = Self.rampImage()
        // clamp(±2) 는 범위 안 값에 항등이므로, 0.5 와 −0.5 는 대칭적으로 밝기를 올리고 내린다.
        let neutral = try Self.meanLuma(ramp, whites: 0, blacks: 0)
        let up = try Self.meanLuma(ramp, whites: 0.5, blacks: 0)
        let down = try Self.meanLuma(ramp, whites: -0.5, blacks: 0)
        XCTAssertGreaterThan(up, neutral)
        XCTAssertLessThan(down, neutral)
    }

    // MARK: 픽스처

    /// 0..1 수평 그라디언트(float linear) — 백점/흑점 대역을 모두 포함한다.
    private static func rampImage() -> CIImage {
        let width = 256, height = 8
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = Float(x) / Float(width - 1)
                let i = (y * width + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = 1
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: width * 16,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
    }

    private static func meanLuma(_ image: CIImage, whites: Double, blacks: Double) throws -> Double {
        var params = DevelopParameters()
        params.whites = whites
        params.blacks = blacks
        let output = ToneMapper.applyToneCurves(to: image, params: params)
        let extent = output.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        let space = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let context = CIContext(options: [.workingColorSpace: space])
        var buffer = [Float](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            context.render(output, toBitmap: raw.baseAddress!, rowBytes: width * 16,
                           bounds: extent, format: .RGBAf, colorSpace: space)
        }
        var sum = 0.0
        for index in stride(from: 0, to: buffer.count, by: 4) {
            sum += Double(0.2126 * buffer[index] + 0.7152 * buffer[index + 1]
                + 0.0722 * buffer[index + 2])
        }
        return sum / Double(width * height)
    }

    /// 평균 휘도 주변에 좁게 뭉친 히스토그램 — 자동 톤이 끝점을 크게 밀고 싶어 하는 입력이다.
    private static func stats(luminance: Double) -> AutoAdjust.ImageStats {
        var histogram = [Double](repeating: 0, count: 256)
        let center = Int((luminance * 255).rounded())
        for bin in max(0, center - 12)...min(255, center + 12) { histogram[bin] = 1 }
        let total = histogram.reduce(0, +)
        histogram = histogram.map { $0 / total }
        return AutoAdjust.ImageStats(
            avgR: luminance,
            avgG: luminance,
            avgB: luminance,
            lumaHist: histogram,
            avgSaturation: 0.2
        )
    }
}
