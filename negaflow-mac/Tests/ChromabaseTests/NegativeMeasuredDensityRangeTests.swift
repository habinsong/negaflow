import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

/// 실측 밀도역(`NegativeInversion.sampleStats`)의 계약.
///
/// 앞 판은 잰 범위가 좁으면 그것을 "측정 실패" 로 보고 명목 범위(1.55, 고대비 가정)로
/// 되돌렸다. 그런데 **좁은 것과 실패한 것은 다르다** — 오래되어 바랜 필름은 실제로 평평하다.
/// 측정이 맞는데 틀린 걸로 보고 버리고, 그 고대비 가정이 사진을 검게 눌렀다.
final class NegativeMeasuredDensityRangeTests: XCTestCase {
    private let extendedLinear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private let base = SIMD3<Double>(0.80, 0.60, 0.40)

    /// 오래되어 바랜 네거티브. 밀도 범위가 진짜로 좁고, 파랑이 가장 먼저 바랜다.
    private func fadedNegative() -> CIImage {
        makeFloatImage(width: 64, height: 16) { x, _ in
            let density = x < 8 ? 0.30 : 0.15
            return (
                self.base.x * pow(10, -density),
                self.base.y * pow(10, -density * 0.95),
                self.base.z * pow(10, -density * 0.40)
            )
        }
    }

    /// 건강한 스캔. 세 채널이 비슷하게 넓은 범위를 쓴다.
    private func healthyNegative() -> CIImage {
        makeFloatImage(width: 64, height: 16) { x, _ in
            let density = x < 8 ? 0.90 : 0.10
            return (
                self.base.x * pow(10, -density),
                self.base.y * pow(10, -density * 0.98),
                self.base.z * pow(10, -density * 0.95)
            )
        }
    }

    func testFadedNegativeKeepsItsMeasuredNarrowRange() throws {
        let stats = try XCTUnwrap(NegativeInversion.sampleStats(
            fadedNegative(), base: FilmBase(rgb: base, source: .manual)
        ))
        XCTAssertLessThan(stats.dmaxNorm.x, 0.42,
                          "진짜로 평평한 네거티브는 잰 범위를 그대로 유지해야 합니다")
        XCTAssertNotEqual(stats.dmaxNorm.x, stats.dmaxNorm.z,
                          "바랜 네거티브는 채널별 범위 차이를 유지해야 합니다")
        // 파랑이 가장 먼저 바래므로 파랑의 범위가 가장 좁아야 한다. 앞 판의 max(0.4) 바닥은
        // 그 차이를 통째로 삼켰다 — 실측 카메라 스캔에서 파랑이 정확히 0.40 으로 걸리고,
        // 그만큼 파랑이 과하게 늘어나 사진이 노랗게 나왔다.
        XCTAssertLessThan(stats.dmaxNorm.z, stats.dmaxNorm.y)
        XCTAssertGreaterThan(stats.dmaxNorm.z, 0)
    }

    /// 바닥은 **아무것도 안 찍힌 프레임**을 막는 자리다. 실제로 관측한 가장 평평한 채널이
    /// 0.13 이므로 그 아래로 두되, 0 으로 두지는 않는다.
    func testChannelFloorStillBoundsAnEmptyFrame() throws {
        let flat = makeFloatImage(width: 64, height: 16) { _, _ in
            (self.base.x, self.base.y, self.base.z)
        }
        let stats = try XCTUnwrap(NegativeInversion.sampleStats(
            flat, base: FilmBase(rgb: base, source: .manual)
        ))
        XCTAssertEqual(stats.dmaxNorm.x, 0.10, accuracy: 1e-9)
        XCTAssertEqual(stats.dmaxNorm.y, 0.10, accuracy: 1e-9)
        XCTAssertEqual(stats.dmaxNorm.z, 0.10, accuracy: 1e-9)
    }

    /// 건강한 스캔은 앞 판에서도 신뢰도가 1 이라 잰 값을 그대로 썼다 — 여기서도 같은 값이다.
    func testHealthyScanUsesTheMeasuredRangeUnchanged() throws {
        let image = healthyNegative()
        let stats = try XCTUnwrap(NegativeInversion.sampleStats(
            image, base: FilmBase(rgb: base, source: .manual)
        ))
        XCTAssertEqual(stats.dmaxNorm.x, 0.90, accuracy: 0.02)
        XCTAssertEqual(stats.dmaxNorm.y, 0.90 * 0.98, accuracy: 0.02)
        XCTAssertEqual(stats.dmaxNorm.z, 0.90 * 0.95, accuracy: 0.02)
    }

    private func makeFloatImage(
        width: Int,
        height: Int,
        pixel: (Int, Int) -> (Double, Double, Double)
    ) -> CIImage {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = pixel(x, y)
                let offset = (y * width + x) * 4
                pixels[offset] = Float(r)
                pixels[offset + 1] = Float(g)
                pixels[offset + 2] = Float(b)
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: extendedLinear
        )
    }
}
