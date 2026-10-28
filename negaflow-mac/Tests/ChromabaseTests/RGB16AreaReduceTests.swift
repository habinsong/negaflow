import XCTest
@testable import Chromabase

final class RGB16AreaReduceTests: XCTestCase {
    private func reduce(
        _ pixels: [UInt16], width: Int, height: Int, channels: Int, to target: (Int, Int)
    ) -> [UInt16]? {
        pixels.withUnsafeBufferPointer {
            RGB16AreaReduce.reduce($0.baseAddress!, width: width, height: height, channels: channels,
                                   targetWidth: target.0, targetHeight: target.1)
        }
    }

    func testConstantImageStaysConstantAtFractionalRatios() throws {
        let width = 37, height = 23
        var pixels = [UInt16](repeating: 0, count: width * height * 3)
        for p in 0..<(width * height) { pixels[p * 3] = 1_000; pixels[p * 3 + 1] = 30_000; pixels[p * 3 + 2] = 65_535 }
        let out = try XCTUnwrap(reduce(pixels, width: width, height: height, channels: 3, to: (11, 7)))
        XCTAssertEqual(out.count, 11 * 7 * 4)
        for p in 0..<(11 * 7) {
            XCTAssertEqual(out[p * 4], 1_000)
            XCTAssertEqual(out[p * 4 + 1], 30_000)
            XCTAssertEqual(out[p * 4 + 2], 65_535)
            XCTAssertEqual(out[p * 4 + 3], 65_535)
        }
    }

    func testIntegerRatioIsExactBoxAverage() throws {
        // 4x2 → 2x1: 각 칸이 2x2 평균이다.
        let values: [[UInt16]] = [[0, 100, 400, 500], [200, 300, 600, 700]]
        var pixels = [UInt16]()
        for row in values { for v in row { pixels += [v, v * 2, v / 2] } }
        let out = try XCTUnwrap(reduce(pixels, width: 4, height: 2, channels: 3, to: (2, 1)))
        XCTAssertEqual(out[0], 150)           // (0+100+200+300)/4
        XCTAssertEqual(out[1], 300)
        XCTAssertEqual(out[4], 550)           // (400+500+600+700)/4
    }

    func testFractionalRatioWeightsEdgePixelsByCoverage() throws {
        // 3 열 → 2 열: 첫 칸은 열 0 과 열 1 의 절반, 둘째 칸은 열 1 의 절반과 열 2.
        let pixels: [UInt16] = [0, 0, 0, 300, 300, 300, 600, 600, 600]
        let out = try XCTUnwrap(reduce(pixels, width: 3, height: 1, channels: 3, to: (2, 1)))
        XCTAssertEqual(Int(out[0]), 100)      // (0*1 + 300*0.5) / 1.5
        XCTAssertEqual(Int(out[4]), 500)      // (300*0.5 + 600*1) / 1.5
    }

    func testFourChannelInputIgnoresAlpha() throws {
        let pixels: [UInt16] = [10, 20, 30, 0, 30, 40, 50, 0]
        let out = try XCTUnwrap(reduce(pixels, width: 2, height: 1, channels: 4, to: (1, 1)))
        XCTAssertEqual(Array(out), [20, 30, 40, 65_535])
    }

    func testMeanIsPreservedOnARamp() throws {
        let width = 211, height = 5
        var pixels = [UInt16](repeating: 0, count: width * height * 3)
        for y in 0..<height { for x in 0..<width {
            let v = UInt16(x * 300)
            for c in 0..<3 { pixels[(y * width + x) * 3 + c] = v }
        } }
        let out = try XCTUnwrap(reduce(pixels, width: width, height: height, channels: 3, to: (50, 2)))
        let sourceMean = Double(pixels.enumerated().filter { $0.offset % 3 == 0 }.map { Double($0.element) }.reduce(0, +))
            / Double(width * height)
        let reducedMean = stride(from: 0, to: out.count, by: 4).map { Double(out[$0]) }.reduce(0, +) / Double(50 * 2)
        XCTAssertEqual(reducedMean, sourceMean, accuracy: sourceMean * 0.01)
    }

    func testRejectsEnlargementAndBadChannelCounts() {
        let pixels = [UInt16](repeating: 1, count: 4 * 3)
        XCTAssertNil(reduce(pixels, width: 2, height: 2, channels: 3, to: (3, 2)))
        XCTAssertNil(reduce(pixels, width: 2, height: 2, channels: 2, to: (1, 1)))
        XCTAssertNil(reduce(pixels, width: 2, height: 2, channels: 3, to: (0, 1)))
    }
}
