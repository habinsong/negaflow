import XCTest
@testable import negaflowApp

final class LibraryCullingProjectionTests: XCTestCase {
    func testCullingTextIsCompleteForEverySupportedLanguage() {
        for language in AppLanguage.allCases {
            for key in AppCullingText.allCases {
                XCTAssertFalse(
                    AppLocalization.cullingText(key, language: language).isEmpty,
                    "Missing \(key) for \(language)"
                )
            }
        }
    }

    func testSelectedFramesFollowProjectionOrderAndDeduplicateIDs() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        XCTAssertEqual(
            LibraryCullingProjection.selectedFrameIDs(
                orderedFrameIDs: [third, first, third, second],
                selectedFrameIDs: [first, third]
            ),
            [third, first]
        )
    }

    func testCompareUsesActiveSelectionAsCandidateAndFirstOtherAsReference() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        XCTAssertEqual(
            LibraryCullingProjection.compareFrameIDs(
                orderedFrameIDs: [first, second, third],
                selectedFrameIDs: [first, second, third],
                activeFrameID: third
            ),
            [first, third]
        )
    }

    func testCompareRequiresTwoInScopeAndIgnoresHiddenActiveFrame() {
        let first = UUID()
        let second = UUID()
        let hidden = UUID()

        XCTAssertEqual(
            LibraryCullingProjection.compareFrameIDs(
                orderedFrameIDs: [first, second],
                selectedFrameIDs: [first, second, hidden],
                activeFrameID: hidden
            ),
            [first, second]
        )
        XCTAssertTrue(
            LibraryCullingProjection.compareFrameIDs(
                orderedFrameIDs: [first],
                selectedFrameIDs: [first, hidden],
                activeFrameID: hidden
            ).isEmpty
        )
    }
}
