import CoreImage
import XCTest
@testable import Chromabase

/// 노출이 낮게 실린 선형 스캔에서도 필름 베이스 자동 실측이 성립해야 한다.
///
/// 스캐너 raw 는 gamma 1.0 으로 오는 경우가 있고(예: epson2 를 선형 감마로 구동), 같은 필름이라도
/// 값이 감마 인코딩 스캔보다 훨씬 낮게 실린다. 마스크 분리(R−B)와 중립성은 밝기에 비례하는 양이라
/// 고정 가산 임계로 판정하면 어두운 스캔에서만 베이스가 통째로 탈락한다 — 그 회귀를 막는다.
final class FilmBaseLinearExposureTests: XCTestCase {
    /// 선형 투과율 비율. Kodak 계열은 마스크가 진하고 Fuji 계열은 옅다.
    private let kodakRatio = SIMD3<Double>(1.0, 0.45, 0.20)
    private let fujiRatio = SIMD3<Double>(1.0, 0.62, 0.38)

    private func linearImage(
        width: Int, height: Int, pixel: (Int, Int) -> SIMD3<Float>
    ) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let color = pixel(x, y)
                let offset = (y * width + x) * 4
                pixels[offset] = color.x
                pixels[offset + 1] = color.y
                pixels[offset + 2] = color.z
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    /// 가장자리는 베이스(0D), 안쪽은 0.4~1.6D 장면인 합성 네거티브.
    private func negative(base: SIMD3<Double>, width: Int = 160, height: Int = 120) -> CIImage {
        let bx = Int(Double(width) * 0.08), by = Int(Double(height) * 0.08)
        return linearImage(width: width, height: height) { x, y in
            let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
            let density = isBorder ? 0.0 : 0.4 + 1.2 * Double(x) / Double(width - 1)
            let rgb = base * pow(10.0, -density)
            return SIMD3<Float>(Float(rgb.x), Float(rgb.y), Float(rgb.z))
        }
    }

    private func assertRecoversBase(
        _ base: SIMD3<Double>,
        neutralBase: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let estimated = FilmBaseEstimator.estimate(
            from: negative(base: base),
            neutralBase: neutralBase,
            confidentOnly: true
        ) else {
            return XCTFail(
                "노출이 낮은 선형 스캔에서도 확신 있는 실측이 나와야 한다: base=\(base)",
                file: file, line: line
            )
        }
        let tolerance = max(0.01, base.x * 0.12)
        XCTAssertEqual(estimated.rgb.x, base.x, accuracy: tolerance, "R", file: file, line: line)
        XCTAssertEqual(estimated.rgb.y, base.y, accuracy: tolerance, "G", file: file, line: line)
        XCTAssertEqual(estimated.rgb.z, base.z, accuracy: tolerance, "B", file: file, line: line)
    }

    /// 옛 고정 임계(R−B ≥ 0.06)에서 실패하던 밝기 대역. Kodak 계열은 R<0.075, Fuji 계열은
    /// R<0.097 에서 후보가 전멸했다.
    func testDimLinearScanStillMeasuresTheColorBase() {
        for scale in [0.30, 0.12, 0.06, 0.03] {
            assertRecoversBase(kodakRatio * scale)
            assertRecoversBase(fujiRatio * scale)
        }
    }

    /// 흑백 중립 베이스도 같은 이유로 luma 0.10 아래에서 전멸했다.
    func testDimLinearScanStillMeasuresTheNeutralBase() {
        for level in [0.30, 0.12, 0.06, 0.035] {
            assertRecoversBase(SIMD3(repeating: level), neutralBase: true)
        }
    }

    /// 밝은 스캔의 판정은 그대로여야 한다(기존 동작 보존).
    func testBrightScanBehaviorIsUnchanged() {
        assertRecoversBase(SIMD3(0.82, 0.55, 0.34))
        assertRecoversBase(SIMD3(0.75, 0.75, 0.75), neutralBase: true)
    }

    /// 무필름 빈 공간처럼 거의 중립인 밝은 영역은 어떤 밝기에서도 베이스 후보가 아니다.
    /// 비율 판정이 어두운 노이즈까지 후보로 열어주면 안 된다.
    func testNearNeutralAreaIsNeverAColorBaseCandidate() {
        for level in [0.90, 0.50, 0.20, 0.06] {
            let neutral = SIMD3<Double>(level, level * 0.98, level * 0.96)
            XCTAssertFalse(
                FilmBaseEstimator.isFilmBaseCandidate(
                    r: neutral.x, g: neutral.y, b: neutral.z, neutralBase: false
                ),
                "중립에 가까운 \(level) 영역이 컬러 베이스 후보가 되면 안 된다"
            )
        }
    }

    /// 오렌지 마스크는 어떤 노출에서도 후보다 — 비율은 노출과 무관하기 때문이다.
    func testMaskCandidacyIsExposureInvariant() {
        for scale in [0.9, 0.5, 0.2, 0.08, 0.03] {
            for ratio in [kodakRatio, fujiRatio] {
                let rgb = ratio * scale
                XCTAssertTrue(
                    FilmBaseEstimator.isFilmBaseCandidate(
                        r: rgb.x, g: rgb.y, b: rgb.z, neutralBase: false
                    ),
                    "마스크 베이스 \(rgb) 는 노출과 무관하게 후보여야 한다"
                )
            }
        }
    }

    /// 흑백 판정도 비율이다: 밝은 곳에서 통과하던 편차 폭이 어두운 곳에서는 그만큼 좁아진다.
    func testNeutralToleranceScalesWithLevel() {
        XCTAssertTrue(FilmBaseEstimator.isFilmBaseCandidate(
            r: 0.75, g: 0.72, b: 0.69, neutralBase: true
        ))
        XCTAssertFalse(FilmBaseEstimator.isFilmBaseCandidate(
            r: 0.10, g: 0.07, b: 0.04, neutralBase: true
        ), "어두운 곳의 0.03 편차는 중립이 아니다")
    }
}
