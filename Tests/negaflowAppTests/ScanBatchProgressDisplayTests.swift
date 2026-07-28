import Foundation
import XCTest
@testable import negaflowApp

/// 여러 컷을 이어 스캔할 때 진행률 표시가 뒤로 되돌아가면 안 된다.
///
/// 백엔드는 본 획득을 0.92까지만 보고한다. 앱은 획득 직후 컷 진행률을 1로 올리지만, 그 대입과
/// 다음 컷의 0 초기화 사이에 중단 지점이 없어서 100%가 화면에 그려지지 않는다. 컷 단위로
/// 표시하면 매 컷이 92%에서 멈췄다가 0%로 튀어, 정상 스캔이 실패처럼 보인다.
@MainActor
final class ScanBatchProgressDisplayTests: XCTestCase {

    /// 컷이 하나뿐이면 예전처럼 그 컷의 진행률을 그대로 보여준다.
    func testSingleFrameScanShowsItsOwnFraction() {
        let model = AppModel()
        model.isScanning = true
        model.batchTotal = 1
        model.batchIndex = 0
        model.scanFraction = 0.92

        XCTAssertEqual(model.displayedScanFraction(), 0.92, accuracy: 1e-9)
    }

    /// 배치에서는 컷이 끝날 때마다 진행률이 앞으로만 간다.
    func testBatchProgressNeverGoesBackwardsBetweenFrames() {
        let model = AppModel()
        model.isScanning = true
        model.batchTotal = 4

        // 1번 컷이 획득을 마친 순간(백엔드가 보고하는 최대치).
        model.batchIndex = 0
        model.scanFraction = 0.92
        let endOfFirstFrame = model.displayedScanFraction()

        // 2번 컷이 시작되며 컷 진행률은 0으로 초기화된다.
        model.batchIndex = 1
        model.scanFraction = 0
        let startOfSecondFrame = model.displayedScanFraction()

        XCTAssertGreaterThanOrEqual(
            startOfSecondFrame,
            endOfFirstFrame,
            "다음 컷으로 넘어갈 때 진행률이 되돌아가면 정상 스캔이 실패처럼 보인다"
        )
    }

    /// 배치 진행률은 컷 순서를 따라 단조 증가해야 한다.
    func testBatchProgressIsMonotonicAcrossEveryFrame() {
        let model = AppModel()
        model.isScanning = true
        model.batchTotal = 6
        var previous = -1.0

        for index in 0..<6 {
            model.batchIndex = index
            for fraction in [0.0, 0.08, 0.5, 0.92] {
                model.scanFraction = fraction
                let displayed = model.displayedScanFraction()
                XCTAssertGreaterThanOrEqual(displayed, previous, "컷 \(index + 1), 진행률 \(fraction)")
                previous = displayed
            }
        }
        XCTAssertLessThanOrEqual(previous, 1)
        XCTAssertGreaterThan(previous, 0.9, "마지막 컷 끝에서는 거의 완료로 보여야 한다")
    }

    /// 배치가 끝나고 완료 상태가 되면 100%로 마무리된다.
    func testCompletedBatchReadsAsFull() {
        let model = AppModel()
        model.isScanning = false
        model.scanPhase = .complete
        model.batchTotal = 0
        model.batchIndex = 0
        model.scanFraction = 0.92

        XCTAssertEqual(model.displayedScanFraction(), 1, accuracy: 1e-9)
    }

    /// 범위를 벗어난 값이 들어와도 0...1을 넘지 않는다.
    func testDisplayedFractionStaysInRange() {
        let model = AppModel()
        model.isScanning = true
        model.batchTotal = 3
        model.batchIndex = 5
        model.scanFraction = 4

        let displayed = model.displayedScanFraction()
        XCTAssertGreaterThanOrEqual(displayed, 0)
        XCTAssertLessThanOrEqual(displayed, 1)
    }
}
