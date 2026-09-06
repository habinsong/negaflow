import XCTest
import Chromabase
@testable import negaflowApp

final class InputGammaValueInputTests: XCTestCase {
    func testAcceptsValidNumbersAndIncompleteDrafts() {
        for text in ["1", "1.0", ".5", "0.1", "4.0", "", ".", "0", "0.", "1."] {
            XCTAssertTrue(InputGammaValueInput.accepts(text), text)
        }
        for text in ["", ".", "0", "0.", "1."] {
            XCTAssertNil(InputGammaValueInput.value(text), text)
        }
        XCTAssertEqual(InputGammaValueInput.value(".5")?.value, 0.5)
    }

    func testRejectsWholeInvalidInputWithoutCoercion() {
        for text in ["-1", "+2", "1e2", "NaN", "Infinity", "2%", "2,2", "text", "１", " 1", "1 ",
                     "4.01", "0.09", "0.10", "2.20", "2.25", "99", "1.234", "1..2", String(repeating: "1", count: 10000)] {
            XCTAssertFalse(InputGammaValueInput.accepts(text), String(text.prefix(20)))
            XCTAssertNil(InputGammaValueInput.value(text), String(text.prefix(20)))
        }
    }

    func testOneDecimalPresentationDoesNotModifyRecordedOrStoredGamma() throws {
        let stored = try InputGammaInterpretation.power(2.19921875)
        XCTAssertEqual(InputGammaValueInput.formatted(stored.value!), "2.2")
        XCTAssertEqual(stored.value, 2.19921875)
        XCTAssertEqual(InputGammaValueInput.formatted(1), "1.0")
        XCTAssertEqual(InputGammaValueInput.rounded(2.25), 2.3)
        XCTAssertEqual(InputGammaValueInput.value("2.3")?.value, 2.3)
        XCTAssertNil(InputGammaValueInput.value("2.19921875"))
    }
}
