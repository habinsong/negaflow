import CoreImage
import XCTest
@testable import Chromabase

/// 자동 색상(NeutralBalance)의 기울기(감마) 항은 증거가 덮는 휘도에만 쓴다. 범위 밖으로 외삽하면 깊은
/// 암부에서 채널별 감마 차이가 스톱 단위 캐스트가 된다(2026-11-08 사용자 카탈로그 실측).
final class NeutralBalanceCoverageTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    /// 밝은 절반에만 중립 증거(밝기에 따라 초록 캐스트가 커짐)가 있고, 아래 절반에는 증거보다 훨씬 어두운
    /// 회색이 있다. 회색은 증거 범위 아래 경계의 보정 배율만 받아야 한다.
    func testSlopeIsHeldAtTheEvidenceEdge() throws {
        let width = 256, height = 128
        let deepGray = 0.0006
        let image = SyntheticScan.makeImage(width: width, height: height) { x, y in
            if y < height / 2 {
                // 휘도 0.06 → 0.6 램프, 밝을수록 초록이 조금씩 더 뜬다(대역마다 다른 캐스트).
                let t = Double(x) / Double(width - 1)
                let luma = 0.06 * pow(10, t)
                let green = 1 + 0.10 * t
                return SIMD3(luma / green, luma * green, luma / green)
            }
            // 증거(채널 하한 0.004)에 잡히지 않는 깊은 회색.
            return SIMD3(repeating: deepGray)
        }
        let correction = NeutralBalance.measure(image, sampleColorSpace: linear, insetFraction: 0, strength: 1)
        // 이 증거로는 감마 항이 쓰인다 — 시험이 경계 처리를 실제로 건드린다.
        XCTAssertGreaterThan(Self.largestSlopeDeparture(correction.slope), 0.01)
        XCTAssertGreaterThan(log(deepGray), correction.support.lowerBound - 4)
        XCTAssertLessThan(log(deepGray), correction.support.lowerBound - 1, "회색이 증거 범위 밖에 있어야 한다")

        var cached: NeutralBalance.Correction? = correction
        let output = NeutralBalance.apply(to: image, sampleColorSpace: linear, strength: 1, correction: &cached)
        let pixel = try XCTUnwrap(render(output, x: width / 2, y: height - 4))

        let exponent = SIMD3<Double>(repeating: 1) / correction.slope
        let gain = SIMD3(exp(-correction.offset.x * exponent.x), exp(-correction.offset.y * exponent.y),
                         exp(-correction.offset.z * exponent.z))
        let low = correction.channelBounds.low
        var extrapolatedSpread = 0.0, heldSpread = 0.0
        var expected = SIMD3<Double>(repeating: 0)
        var extrapolated = SIMD3<Double>(repeating: 0)
        for c in 0..<3 {
            expected[c] = deepGray * gain[c] * pow(max(low[c], deepGray), exponent[c] - 1)
            extrapolated[c] = gain[c] * pow(deepGray, exponent[c])
            XCTAssertEqual(pixel[c], expected[c], accuracy: expected[c] * 2e-3, "채널 \(c)")
        }
        // 경계 배율을 쓰면 회색의 채널 비가 경계에서의 비를 넘지 않는다. 외삽했다면 훨씬 벌어진다.
        func spread(_ v: SIMD3<Double>) -> Double { log(max(v.x, max(v.y, v.z)) / min(v.x, min(v.y, v.z))) }
        extrapolatedSpread = spread(extrapolated)
        heldSpread = spread(pixel)
        XCTAssertLessThan(heldSpread, extrapolatedSpread - 0.05)
    }

    /// 증거 범위 안의 화소는 맞춘 중립축을 정확히 뒤집는다(c' = gain·c^exponent).
    func testInsideTheEvidenceThePowerLawIsExact() throws {
        let width = 256, height = 64
        let image = SyntheticScan.makeImage(width: width, height: height) { x, _ in
            let t = Double(x) / Double(width - 1)
            let luma = 0.06 * pow(10, t)
            let green = 1 + 0.10 * t
            return SIMD3(luma / green, luma * green, luma / green)
        }
        let correction = NeutralBalance.measure(image, sampleColorSpace: linear, insetFraction: 0, strength: 1)
        XCTAssertGreaterThan(Self.largestSlopeDeparture(correction.slope), 0.01)
        var cached: NeutralBalance.Correction? = correction
        let output = NeutralBalance.apply(to: image, sampleColorSpace: linear, strength: 1, correction: &cached)
        let x = width / 2
        let t = Double(x) / Double(width - 1)
        let luma = 0.06 * pow(10, t), green = 1 + 0.10 * t
        let input = SIMD3(luma / green, luma * green, luma / green)
        XCTAssertTrue((0..<3).allSatisfy {
            log(input[$0]) > correction.support.lowerBound - 1 && log(input[$0]) < correction.support.upperBound + 1
        })
        let pixel = try XCTUnwrap(render(output, x: x, y: height / 2))
        for c in 0..<3 {
            let exponent = 1 / correction.slope[c]
            let expected = exp(-correction.offset[c] * exponent) * pow(input[c], exponent)
            XCTAssertEqual(pixel[c], expected, accuracy: expected * 2e-3, "채널 \(c)")
        }
    }

    private func render(_ image: CIImage, x: Int, y: Int) -> SIMD3<Double>? {
        var px = [Float](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: linear])
        // CIImage 의 y 는 아래에서 위로 — makeImage 의 행 y 를 뒤집어 읽는다.
        let flippedY = Int(image.extent.height) - 1 - y
        context.render(image, toBitmap: &px, rowBytes: 16,
                       bounds: CGRect(x: x, y: flippedY, width: 1, height: 1), format: .RGBAf, colorSpace: linear)
        return SIMD3(Double(px[0]), Double(px[1]), Double(px[2]))
    }

    /// 세 채널 기울기 가운데 1 에서 가장 먼 거리.
    private static func largestSlopeDeparture(_ slope: SIMD3<Double>) -> Double {
        var largest = 0.0
        for channel in 0..<3 { largest = max(largest, abs(slope[channel] - 1)) }
        return largest
    }
}
