import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

/// 유제 색과 무관한 베이스 상한(`FilmBasePhysicalEnvelope.swift`)의 계약.
///
/// Windows `tests/Native.UnitTests/auto_negative_base_rebate_tests.cpp` 의 같은 이름 시험과 같은
/// 장면이다 — 위아래 프레임 사이 틈이 베이스이고 그 사이가 사진이다. 위아래가 대칭이라 CI 의 y 방향과
/// 무관하다.
final class FilmBasePhysicalEnvelopeTests: XCTestCase {
    private let width = 1024
    private let height = 708
    private let extendedLinear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    private func makeFrameWithGap(base: SIMD3<Double>, dense: SIMD3<Double>, thin: SIMD3<Double>,
                                  gapRows: Int, lightRows: Int = 0,
                                  light: SIMD3<Double> = .zero) -> CIImage {
        makeFloatImage { x, y in
            if y < lightRows || y >= self.height - lightRows { return light }
            if y < gapRows || y >= self.height - gapRows { return base }
            return (x / 128 + (y - gapRows) / 128) % 3 == 0 ? thin : dense
        }
    }

    /// 두 틈 사이의 사진 영역(크롭).
    private func photoBetweenGaps(_ gapRows: Int) -> AnalysisRegion? {
        let inset = Double(gapRows + 8) / Double(height)
        return AnalysisRegion(unitRect: CGRect(x: 0.02, y: inset, width: 0.96, height: 1 - 2 * inset))
    }

    /// 2026-10-31 GT-X900 · Kodak Vision3 250D 4~11번의 값이다. 틈의 베이스가 초록·파랑이 빨강보다
    /// 밝아 오렌지 후보에서 빠졌고, 사진 속 짙은 오렌지 면이 베이스로 골라져 반전이 어둡고 붉게
    /// 잘렸다. 베이스는 색이 아니라 "모든 채널이 함께 가장 밝다" 로 찾아야 한다.
    func testBaseThatIsNotOrangeIsStillTheBase() throws {
        let gapRows = 90
        let image = makeFrameWithGap(base: SIMD3(0.30, 0.34, 0.33), dense: SIMD3(0.13, 0.08, 0.08),
                                     thin: SIMD3(0.24, 0.25, 0.22), gapRows: gapRows)
        for region in [photoBetweenGaps(gapRows), nil] {
            let resolved = try XCTUnwrap(FilmBaseEstimator.estimate(from: image, excludingInterior: region))
            XCTAssertEqual(resolved.rgb.x, 0.30, accuracy: 0.01, "빨강이 틈의 베이스")
            XCTAssertEqual(resolved.rgb.y, 0.34, accuracy: 0.01, "초록이 틈의 베이스")
            XCTAssertEqual(resolved.rgb.z, 0.33, accuracy: 0.01, "파랑이 틈의 베이스")
        }
    }

    /// Harman Phoenix 처럼 마스크가 오렌지가 아닌 필름이다(XP2 계열의 보랏빛 베이스).
    func testPurpleBaseIsStillTheBase() throws {
        let gapRows = 90
        let image = makeFrameWithGap(base: SIMD3(0.34, 0.26, 0.36), dense: SIMD3(0.12, 0.07, 0.06),
                                     thin: SIMD3(0.27, 0.20, 0.25), gapRows: gapRows)
        let resolved = try XCTUnwrap(FilmBaseEstimator.estimate(
            from: image, excludingInterior: photoBetweenGaps(gapRows)))
        XCTAssertEqual(resolved.rgb.x, 0.34, accuracy: 0.01)
        XCTAssertEqual(resolved.rgb.y, 0.26, accuracy: 0.01)
        XCTAssertEqual(resolved.rgb.z, 0.36, accuracy: 0.01)
    }

    /// 오렌지 필름 디카 스캔에서 포화되지 않은 맨 광원(중성)이 틈 바깥에 찍힌 경우다. 광원은 모든
    /// 채널이 베이스보다 밝지만 필름이 아니다 — 상대 색도로 걸러져 베이스가 그대로 남아야 한다.
    func testNeutralLightBesideAnOrangeBaseStaysLight() throws {
        let gapRows = 150
        let base = SIMD3<Double>(0.357, 0.150, 0.0763)
        let image = makeFrameWithGap(base: base, dense: SIMD3(0.110, 0.0455, 0.0170),
                                     thin: SIMD3(0.30, 0.12, 0.060), gapRows: gapRows,
                                     lightRows: 60, light: SIMD3(0.70, 0.70, 0.70))
        let resolved = try XCTUnwrap(FilmBaseEstimator.estimate(
            from: image, excludingInterior: photoBetweenGaps(gapRows)))
        XCTAssertEqual(resolved.rgb.x, base.x, accuracy: 0.01)
        XCTAssertEqual(resolved.rgb.y, base.y, accuracy: 0.01)
        XCTAssertEqual(resolved.rgb.z, base.z, accuracy: 0.01)
    }

    private func makeFloatImage(pixel: (Int, Int) -> SIMD3<Double>) -> CIImage {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let rgb = pixel(x, y)
                let offset = (y * width + x) * 4
                pixels[offset] = Float(rgb.x)
                pixels[offset + 1] = Float(rgb.y)
                pixels[offset + 2] = Float(rgb.z)
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
