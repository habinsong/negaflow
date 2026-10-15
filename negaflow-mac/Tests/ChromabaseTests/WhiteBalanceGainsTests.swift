import CoreImage
import XCTest
@testable import Chromabase

/// 온도·틴트 법칙의 계약(Windows `color_model_tests.cpp` `test_white_balance_law` 와 같다).
final class WhiteBalanceGainsTests: XCTestCase {

    /// |v| ≤ 1 에서는 예전 선형 게인의 채널비를 그대로 지킨다 — 저장된 편집이 바뀌지 않는다.
    func testLegacyChannelRatiosInsideUnitRange() throws {
        for warmth in [-1.0, -0.5, 0.3, 1.0] {
            let g = try XCTUnwrap(WhiteBalanceGains.gains(warmth: warmth, tint: 0))
            XCTAssertEqual(g.x / g.z, (1 + 0.18 * warmth) / (1 - 0.18 * warmth), accuracy: 1e-9)
            XCTAssertEqual(g.y / (g.x * g.z).squareRoot(),
                           (1 + 0.03 * warmth) / ((1 + 0.18 * warmth) * (1 - 0.18 * warmth)).squareRoot(),
                           accuracy: 1e-9)
        }
        for tint in [-1.0, -0.4, 0.7, 1.0] {
            let g = try XCTUnwrap(WhiteBalanceGains.gains(warmth: 0, tint: tint))
            XCTAssertEqual(g.x, g.z, accuracy: 1e-12)
            XCTAssertEqual(g.y / g.x, (1 + 0.24 * tint) / (1 - 0.12 * tint), accuracy: 1e-9)
        }
    }

    /// ±1 너머는 끝점 기울기로 이어지고(연속), ±4 에서 R/B 약 ±2.14 스톱까지 넓어진다.
    func testExtendedRangeIsContinuousAndWide() throws {
        func redBlueStops(_ w: Double) throws -> Double {
            let g = try XCTUnwrap(WhiteBalanceGains.gains(warmth: w, tint: 0))
            return log2(g.x / g.z)
        }
        XCTAssertEqual(try redBlueStops(1.0005) - redBlueStops(0.9995), 0.001 * 0.5368, accuracy: 2e-5)
        XCTAssertEqual(try redBlueStops(1), 0.5250, accuracy: 1e-4)
        XCTAssertEqual(try redBlueStops(4), 2.136, accuracy: 0.005)
        XCTAssertEqual(try redBlueStops(-4), -2.136, accuracy: 0.005)
    }

    /// 화이트밸런스는 색만 바꾼다 — 게인의 Rec.709 휘도는 항상 1(예전 틴트 ±1 은 ±13.7%).
    func testGainsKeepNeutralLuminance() throws {
        for (warmth, tint) in [(1.0, 1.0), (-1.0, -1.0), (4.0, -4.0), (-2.5, 1.5), (0.2, 0)] {
            let g = try XCTUnwrap(WhiteBalanceGains.gains(warmth: warmth, tint: tint))
            XCTAssertEqual(0.2126 * g.x + 0.7152 * g.y + 0.0722 * g.z, 1, accuracy: 1e-12)
        }
        XCTAssertNil(WhiteBalanceGains.gains(warmth: 0.0005, tint: -0.0005))
    }

    /// 자동 화이트밸런스의 온도 해는 |w| ≤ 1 에서 예전 닫힌형 (B−R)/(0.18(R+B)) 과 같다.
    func testAutoWhiteBalanceWarmthMatchesLegacyClosedForm() {
        for (r, b) in [(0.30, 0.27), (0.25, 0.28), (0.40, 0.33)] {
            let stats = AutoAdjust.ImageStats(
                avgR: 0.5, avgG: 0.5, avgB: 0.5, lumaHist: [Double](repeating: 1.0 / 256, count: 256),
                avgSaturation: 0.1, neutralPixelFraction: 0.5,
                neutralLinearR: r, neutralLinearG: (r + b) / 2, neutralLinearB: b
            )
            let legacy = min(max((b - r) / (0.18 * (r + b)) * 0.85, -0.6), 0.6)
            XCTAssertEqual(AutoAdjust.autoWhiteBalance(stats).warmth, legacy, accuracy: 1e-9)
        }
    }

    /// +1 EV 로 밝힌 명부에서도 온도가 지워지지 않는다. 수정 전: k14 이상 R/B 가 정확히 1.000
    /// (표시 경계가 휘도 1 이상 화소의 채도를 0 으로 만들었다).
    func testWarmthSurvivesBrightenedHighlights() {
        let wedge = SyntheticScan.negativeWedge()
        let warm = SyntheticScan.developedDisplayPatches(wedge) {
            $0.exposure = 1
            $0.warmth = 1
        }
        for k in 14..<wedge.patchCenters.count {
            XCTAssertGreaterThan(warm[k].x / warm[k].z, 1.02, "patch \(k)")
        }
        XCTAssertEqual(warm[8].x / warm[8].z, 1.18 / 0.82, accuracy: 0.005)
    }
}
