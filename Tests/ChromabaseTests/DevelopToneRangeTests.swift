import XCTest
@testable import Chromabase

// 노출 조정 범위 계약.
//
// 슬라이드 필름의 노출 부족은 3스톱을 넘길 수 있어 ±5(Lightroom·Capture One 관례)로 둔다.
// 자동 톤이 내는 노출은 그보다 좁은 자체 한도 안에 있어야 한다 — 슬라이더 상한을 넘는 값을
// 대입하면 UI 가 표현하지 못하는 상태가 된다.
final class DevelopToneRangeTests: XCTestCase {
    func testExposureRangeCoversDeepUnderexposure() {
        XCTAssertEqual(DevelopToneRange.exposure.lowerBound, -5, accuracy: 1e-9)
        XCTAssertEqual(DevelopToneRange.exposure.upperBound, 5, accuracy: 1e-9)
    }

    // MARK: 키보드 nudge 는 범위를 넓혀도 폭이 그대로다(절대 스텝)

    func testKeyboardNudgeKeepsAbsoluteStepAndClampsToRange() {
        let fine = DevelopKeyboardNudge.adjustedValue(
            0, range: DevelopToneRange.exposure, direction: .increase, coarse: false
        )
        XCTAssertEqual(fine, DevelopKeyboardNudge.fineStep, accuracy: 1e-9,
                       "범위가 넓어져도 미세 조정 폭은 절대값이어야 한다")

        let clampedHigh = DevelopKeyboardNudge.adjustedValue(
            5, range: DevelopToneRange.exposure, direction: .increase, coarse: true
        )
        XCTAssertEqual(clampedHigh, 5, accuracy: 1e-9)

        let clampedLow = DevelopKeyboardNudge.adjustedValue(
            -5, range: DevelopToneRange.exposure, direction: .decrease, coarse: true
        )
        XCTAssertEqual(clampedLow, -5, accuracy: 1e-9)
    }

    // MARK: 자동 톤 한도는 슬라이더보다 좁다

    func testAutoExposureLimitIsThreeStopsAndInsideSliderRange() {
        XCTAssertEqual(AutoAdjust.autoExposureLimit, 3, accuracy: 1e-9)
        XCTAssertLessThan(AutoAdjust.autoExposureLimit, DevelopToneRange.exposure.upperBound,
                          "자동 결과가 손으로 갈 수 있는 끝까지 밀어붙이면 안 된다")
    }

    // MARK: 자동 톤은 슬라이더 범위 안에 머문다

    func testAutoToneExposureStaysInsideSliderRange() {
        // 극단적으로 어두운 장면과 밝은 장면 모두에서 확인한다.
        for bin in [0, 8, 128, 247, 255] {
            var hist = [Double](repeating: 0, count: 256)
            hist[bin] = 1
            let stats = AutoAdjust.ImageStats(
                avgR: Double(bin) / 255, avgG: Double(bin) / 255, avgB: Double(bin) / 255,
                lumaHist: hist,
                avgSaturation: 0.2
            )
            let delta = AutoAdjust.autoTone(stats)
            XCTAssertTrue(DevelopToneRange.exposure.contains(delta.exposure),
                          "자동 톤 노출 \(delta.exposure) 이 슬라이더 범위를 벗어났다 (bin \(bin))")
        }
    }
}
