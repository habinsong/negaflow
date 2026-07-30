import Chromabase
import XCTest
@testable import negaflowApp

@MainActor
final class PrintPackageCaptionFormatterTests: XCTestCase {
    func testSequenceNumberIsIndependentFromStoredFrameNumber() {
        let frame = ScanFrame(
            scanIndex: 27,
            rawScanURL: URL(fileURLWithPath: "/tmp/frame-027.tiff"),
            filmType: .colorNegative
        )

        XCTAssertEqual(
            PrintPackageCaptionFormatter.caption(
                for: frame,
                mode: .frameNumber,
                sequenceNumber: 1
            ),
            "27"
        )
        XCTAssertEqual(
            PrintPackageCaptionFormatter.caption(
                for: frame,
                mode: .sequenceNumber,
                sequenceNumber: 1
            ),
            "1"
        )
    }
}
