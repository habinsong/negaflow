import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

/// 자동 베이스가 얇은 리베이트를 놓쳤을 때 도는 구조길의 계약.
///
/// 리베이트(사진이 찍히지 않은 필름 여백)가 얇으면 256 폭 격자에서 주변과 평균되어 사라지고,
/// 다음으로 밝은 덩어리인 **사진 내용**이 베이스로 뽑힌다. 반전의 0 점이 낮게 앉아 사진이
/// 통째로 어두워진다.
///
/// 조각마다 계약을 건다. 끝에서 끝까지 한 번에 거는 시험은 추정기 전체의 동작을 합성
/// 이미지로 흉내 내야 하는데, 그 이미지는 사진이 아니라서 무엇을 고정하는지가 흐려진다.
final class FilmBaseRebateTests: XCTestCase {
    private let width = 1024
    private let height = 708
    private let rebateRGB = SIMD3<Double>(0.357, 0.150, 0.0763)
    private let extendedLinear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    /// 스캔 한 장. `rebateRows` 가 0 이면 리베이트가 찍히지 않은 사진이다.
    private func makeScan(rebateRows: Int) -> CIImage {
        makeFloatImage(width: width, height: height) { x, y in
            if y < 6 || y + 12 >= self.height {
                // 스캐너가 아무것도 읽지 않은 자리.
                return (0.001, 0.001, 0.001)
            }
            if rebateRows > 0, y < 6 + rebateRows {
                return (self.rebateRGB.x, self.rebateRGB.y, self.rebateRGB.z)
            }
            let shade = 0.85 + 0.30 * Double(x) / Double(self.width)
            return (0.110 * shade, 0.0455 * shade, 0.0170 * shade)
        }
    }

    /// 리베이트 세 줄. 격자에서는 위아래 여백과 평균되어 값이 뭉개진다 — 그래서 **찾기만**
    /// 축소본에서 하고 **재기** 는 원본에서 한다. 이 시험이 고정하는 것이 그 두 단계의 분리다.
    func testBandIsMeasuredAtFullResolutionNotOnTheGrid() throws {
        let image = makeScan(rebateRows: 3)
        let grid = try XCTUnwrap(FilmBaseSampleGrid(image: image))
        let measured = try XCTUnwrap(FilmBaseRebate.rebateBase(
            image: image, grid: grid, neutralBase: false, gateOpen: true
        ))
        XCTAssertEqual(measured.rgb.x, rebateRGB.x, accuracy: 0.01, "빨강이 뭉개지지 않은 리베이트")
        XCTAssertEqual(measured.rgb.y, rebateRGB.y, accuracy: 0.01, "초록이 뭉개지지 않은 리베이트")
        XCTAssertEqual(measured.rgb.z, rebateRGB.z, accuracy: 0.01, "파랑이 뭉개지지 않은 리베이트")
    }

    /// 리베이트가 없으면 가장 밝은 유지 수준은 장면 자신이다. 그 값이 지금 값보다 밝을 수는
    /// 없으므로 채택 심사에서 걸리고, 사진은 손대지 않은 채 남는다.
    func testPhotographWithoutRebateIsLeftAlone() throws {
        let image = makeScan(rebateRows: 0)
        let grid = try XCTUnwrap(FilmBaseSampleGrid(image: image))
        let measured = FilmBaseRebate.rebateBase(
            image: image, grid: grid, neutralBase: false, gateOpen: true
        )
        if let measured {
            XCTAssertFalse(
                FilmBaseRebate.accept(rebate: measured.rgb,
                                      current: SIMD3(0.1265, 0.0523, 0.0196)),
                "장면 베이스보다 밝지 않은 띠는 거절해야 합니다"
            )
        }
    }

    func testGateCountsFilmBrighterThanTheBase() throws {
        let image = makeScan(rebateRows: 3)
        let grid = try XCTUnwrap(FilmBaseSampleGrid(image: image))
        // 장면 한복판을 베이스라고 우기면 필름의 절반이 그보다 밝다 — 모순이고, 문지기가 열려야 한다.
        let wrong = FilmBaseRebate.brighterThanBaseFraction(
            grid: grid, dmin: SIMD3(0.100, 0.0414, 0.0155)
        )
        XCTAssertGreaterThan(wrong, FilmBaseEstimator.rebateGateFraction,
                             "장면 아래에 앉은 베이스는 문지기를 연다")
        // 리베이트를 베이스로 잡으면 그보다 밝은 것은 없다.
        let right = FilmBaseRebate.brighterThanBaseFraction(grid: grid, dmin: rebateRGB)
        XCTAssertLessThanOrEqual(right, FilmBaseEstimator.rebateGateFraction,
                                 "진짜 베이스는 문지기를 닫아 둔다")
    }

    /// 맨 광원은 센서 최대치에 붙는다. 필름 베이스는 자기도 밀도가 있어 절대 포화되지 않으므로,
    /// 포화된 띠를 채택하면 사진이 새까매진다. 색이 없는 흑백에서는 이것이 유일한 구분점이다.
    func testClippedBandIsRefused() {
        let current = SIMD3<Double>(0.14, 0.06, 0.03)
        XCTAssertFalse(FilmBaseRebate.accept(rebate: SIMD3(0.9995, 0.9995, 0.9995),
                                             current: current),
                       "센서를 포화시킨 맨 광원은 거절")
        XCTAssertTrue(FilmBaseRebate.accept(rebate: rebateRGB, current: current),
                      "포화되지 않은 더 밝은 띠는 채택")
        XCTAssertFalse(FilmBaseRebate.accept(rebate: SIMD3(0.10, 0.04, 0.02), current: current),
                       "지금 값보다 어두운 띠는 거절")
    }

    /// **문지기만으로는 못 잡는 경우다.** 이 스캔에서 추정기는 리베이트를 아예 놓치는 대신
    /// 축소본에서 뭉개진 값을 고른다. 그 값은 장면보다는 밝아서 "베이스보다 밝은 화소" 가 거의
    /// 없고, 문지기가 열리지 않는다. 그래도 사진은 어둡게 나온다.
    ///
    /// 얇은 띠는 그 자체로 "여기서 읽은 값은 못 믿는다" 는 표시이므로, 그때는 문지기와 무관하게
    /// 원본에서 확인한다.
    func testDilutedRebateIsRecoveredEvenThoughTheGateStaysShut() throws {
        let image = makeScan(rebateRows: 3)
        let grid = try XCTUnwrap(FilmBaseSampleGrid(image: image))
        let resolved = try XCTUnwrap(FilmBaseEstimator.estimate(from: image))

        XCTAssertLessThanOrEqual(
            FilmBaseRebate.brighterThanBaseFraction(grid: grid, dmin: resolved.rgb),
            FilmBaseEstimator.rebateGateFraction,
            "문지기는 닫혀 있다 — 문지기가 볼 수 없는 경우가 이것이다"
        )
        XCTAssertEqual(resolved.measurementDiagnostics?.method, .rebateBand,
                       "얇은 띠는 원본 해상도에서 확인한다")
        XCTAssertEqual(resolved.rgb.x, rebateRGB.x, accuracy: 0.01)
        XCTAssertEqual(resolved.rgb.y, rebateRGB.y, accuracy: 0.01)
        XCTAssertEqual(resolved.rgb.z, rebateRGB.z, accuracy: 0.01)
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
