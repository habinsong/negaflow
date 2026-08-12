import Chromabase
import CoreGraphics
import XCTest
@testable import negaflowApp

/// 자동으로 찾은 프레임을 화면에 올릴지 말지 거르는 규칙.
///
/// 필름을 홀더에 어디까지 밀어 넣었느냐에 따라 슬롯의 마지막 컷은 스캔 영역 경계에 걸친다.
/// 예전에는 그 하나 때문에 제대로 찾은 컷 전부가 폐기돼 "자동 검출이 아무것도 못 찾는" 것처럼
/// 보였다(실기 로그: grid=18 → 화면 0개).
@MainActor
final class FlatbedFrameDetectionAcceptanceTests: XCTestCase {
    private func detection(
        _ rect: CGRect,
        row: Int = 0,
        column: Int = 0,
        angle: Double = 0,
        confidence: Double = 0.9
    ) -> FlatbedFrameDetection {
        FlatbedFrameDetection(
            normalizedRect: rect,
            straightenAngle: angle,
            confidence: confidence,
            row: row,
            column: column
        )
    }

    func testFrameHangingOverThePreviewEdgeIsClampedNotDropped() throws {
        // 246mm 프리뷰에서 36mm 컷의 끝이 0.9mm 넘친 실측 상황.
        let overhang = detection(CGRect(x: 0.016, y: 0.857, width: 0.161, height: 0.1463))
        let usable = try XCTUnwrap(AppModel.usableFlatbedFrameDetection(overhang))
        XCTAssertEqual(usable.normalizedRect.maxY, 1, accuracy: 1e-9)
        XCTAssertEqual(usable.normalizedRect.minY, 0.857, accuracy: 1e-9)
        XCTAssertEqual(usable.row, overhang.row)
        XCTAssertEqual(usable.column, overhang.column)
    }

    func testFrameFullyInsideIsPassedThroughUnchanged() throws {
        let inside = detection(CGRect(x: 0.016, y: 0.1, width: 0.161, height: 0.146))
        XCTAssertEqual(AppModel.usableFlatbedFrameDetection(inside), inside)
    }

    /// 절반도 안 남는 것은 컷으로 쓸 수 없다. 값이 망가진 것도 마찬가지다.
    func testUnusableDetectionsAreRejected() {
        XCTAssertNil(AppModel.usableFlatbedFrameDetection(
            detection(CGRect(x: 0.02, y: 0.95, width: 0.16, height: 0.146))
        ), "10%만 남는 컷")
        XCTAssertNil(AppModel.usableFlatbedFrameDetection(
            detection(CGRect(x: .nan, y: 0.1, width: 0.16, height: 0.146))
        ))
        XCTAssertNil(AppModel.usableFlatbedFrameDetection(
            detection(CGRect(x: 0.02, y: 0.1, width: 0, height: 0.146))
        ))
        XCTAssertNil(AppModel.usableFlatbedFrameDetection(
            detection(CGRect(x: 0.02, y: 0.1, width: 0.16, height: 0.146), angle: 80)
        ))
        XCTAssertNil(AppModel.usableFlatbedFrameDetection(
            detection(CGRect(x: 0.02, y: 0.1, width: 0.16, height: 0.146), confidence: 1.4)
        ))
        XCTAssertNil(AppModel.usableFlatbedFrameDetection(
            detection(CGRect(x: 0.02, y: 0.1, width: 0.16, height: 0.146), row: -1)
        ))
    }

    /// 한 컷이 걸쳤다고 나머지 17컷을 버리면 안 된다.
    func testOneOverhangingFrameDoesNotDiscardTheWholeSlot() {
        var detections: [FlatbedFrameDetection] = []
        for index in 0..<6 {
            detections.append(detection(
                CGRect(x: 0.016, y: 0.099 + 0.1517 * Double(index), width: 0.161, height: 0.1463),
                row: 0,
                column: index
            ))
        }
        let usable = detections.compactMap(AppModel.usableFlatbedFrameDetection)
        XCTAssertEqual(usable.count, 6, "마지막 컷이 경계에 걸쳐도 여섯 컷 모두 남아야 한다.")
        XCTAssertTrue(usable.allSatisfy { $0.normalizedRect.maxY <= 1 + 1e-9 })
    }
}
