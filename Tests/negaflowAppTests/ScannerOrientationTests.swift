import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class ScannerOrientationTests: XCTestCase {
    // 스캐너 원본은 물리적으로 180° 뒤집혀 저장될 수 있고, 스캐너 로더/프리뷰는 장치 메타데이터의
    // EXIF 회전을 적용하지 않는다. 사용자 방향이 없으면 스캐너 고유 180°를 기본으로 주고, 사용자가
    // 방향을 잡으면 그 방향(이미 180° 포함)을 이어받아 이중 적용하지 않는다.
    func testScannerUsesDefaultRotationWhenNoUserOrientation() {
        // 기본값(180°) 적용.
        XCTAssertEqual(
            AppModel.scannerInitialTransform(carryover: nil, template: .identity, defaultRotation: .deg180).rotation,
            .deg180
        )
        // 설정에서 다른 기본 방향을 고르면 그 값이 적용된다.
        XCTAssertEqual(
            AppModel.scannerInitialTransform(carryover: nil, template: .identity, defaultRotation: .deg90).rotation,
            .deg90
        )
        // 0°를 고르면 회전 없음(identity).
        XCTAssertTrue(
            AppModel.scannerInitialTransform(carryover: nil, template: .identity, defaultRotation: .deg0).isIdentity
        )
    }

    func testUserTemplateOverridesScannerDefaultWithoutDoubleRotation() {
        let userTemplate = ImageTransform(rotation: .deg270)
        XCTAssertEqual(
            AppModel.scannerInitialTransform(carryover: nil, template: userTemplate, defaultRotation: .deg180),
            userTemplate
        )
    }

    func testPreviewCarryoverTakesPrecedence() {
        let carry = ImageTransform(rotation: .deg180)
        XCTAssertEqual(
            AppModel.scannerInitialTransform(carryover: carry, template: .identity, defaultRotation: .deg90),
            carry
        )
    }
}
