import XCTest
@testable import negaflowApp

final class PrintRulerScaleTests: XCTestCase {
    func testEightInchRulerLabelsEveryInchWithQuarterTicks() {
        let ticks = PrintRulerScale.ticks(lengthPoints: 8 * 72, unit: .inches)

        XCTAssertEqual(ticks.count, 33)
        XCTAssertEqual(ticks.compactMap(\.label), Array(0...8))
        XCTAssertEqual(ticks.first?.fraction, 0)
        XCTAssertEqual(ticks.last?.fraction, 1)
    }

    func testTwentyCentimeterRulerLabelsEveryCentimeterWithHalfTicks() {
        let ticks = PrintRulerScale.ticks(
            lengthPoints: 20 * 72 / 2.54,
            unit: .centimeters
        )

        XCTAssertEqual(ticks.count, 41)
        XCTAssertEqual(ticks.compactMap(\.label), Array(0...20))
        XCTAssertEqual(ticks.first?.fraction, 0)
        XCTAssertEqual(try XCTUnwrap(ticks.last?.fraction), 1, accuracy: 0.000_001)
    }

    func testRulerRejectsNonfiniteAndEmptyLengths() {
        XCTAssertTrue(PrintRulerScale.ticks(lengthPoints: 0, unit: .inches).isEmpty)
        XCTAssertTrue(PrintRulerScale.ticks(lengthPoints: .nan, unit: .centimeters).isEmpty)
    }
}
