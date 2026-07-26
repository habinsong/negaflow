import XCTest
@testable import Chromabase

// 연장 증거 구조선 배제 검증 — 합성 응답 맵 전용.
//
// 판정 원리: 필름 스크래치는 끝나는 자리에서 진짜로 끝나지만, 이미지 구조선(난간·줄눈)은 검출이
// 끊긴 자리에도 원본에 선이 계속 이어진다. 검증 축:
//  ① 연장선에 같은 선이 계속되는 조각 → 기각.
//  ② 끝이 진짜 끝인 고립 결함 → 보존.
//  ③ 한쪽만 이어지는 구조선 끝 조각 → 기각(양쪽 AND 만 요구하면 가장 흔한 오검출이 다 샌다).
//  ④ 연장선이 이미지 밖으로 나가는 프레임 관통 결함 → 판정 불가이므로 보존.
final class DefectStructureLineFilterTests: XCTestCase {
    private let width = 400
    private let height = 200

    /// y 행에 [x0, x1) 구간의 수평 응답을 채운 맵.
    private func responseMap(segments: [(y: Int, x0: Int, x1: Int)]) -> [Float] {
        var map = [Float](repeating: 0, count: width * height)
        for segment in segments {
            for x in segment.x0..<segment.x1 where x >= 0 && x < width {
                map[segment.y * width + x] = 0.02
            }
        }
        return map
    }

    /// [x0, x1) 구간의 1px 수평 컴포넌트.
    private func horizontalComponent(y: Int, x0: Int, x1: Int) -> DefectComponentMask.RawComponent {
        let pixels = (x0..<x1).map { y * width + $0 }
        return DefectComponentMask.RawComponent(pixels: pixels, minX: x0, maxX: x1 - 1, minY: y, maxY: y)
    }

    private func drops(_ components: [DefectComponentMask.RawComponent],
                       _ response: [Float]) -> Set<Int> {
        DefectStructureLineFilter.continuationDrops(scratch: components, response: response,
                                                    width: width, height: height)
    }

    // MARK: ① 양쪽으로 이어지는 구조선 → 기각

    func testSegmentOfContinuingLineRejected() {
        // 원본에는 y=100 에 x=20..380 의 긴 선이 있고, 검출은 그 가운데 조각만 잡았다.
        let response = responseMap(segments: [(y: 100, x0: 20, x1: 380)])
        let component = horizontalComponent(y: 100, x0: 180, x1: 220)
        XCTAssertEqual(drops([component], response), [0],
                       "연장선에 같은 선이 계속되면 이미지 구조선으로 기각되어야 한다")
    }

    // MARK: ② 진짜로 끝나는 고립 결함 → 보존

    func testIsolatedDefectPreserved() {
        // 응답이 컴포넌트 구간에만 있다 = 선이 거기서 진짜 끝난다.
        let response = responseMap(segments: [(y: 100, x0: 180, x1: 220)])
        let component = horizontalComponent(y: 100, x0: 180, x1: 220)
        XCTAssertTrue(drops([component], response).isEmpty,
                      "끝이 진짜 끝인 고립 결함은 보존되어야 한다")
    }

    // MARK: ③ 한쪽만 이어지는 구조선 끝 조각 → 기각

    func testEndSegmentOfStructureLineRejected() {
        // 왼쪽으로만 선이 계속되고 오른쪽은 끝난다(줄눈이 다른 구조와 만나 끝나는 자리).
        let response = responseMap(segments: [(y: 100, x0: 20, x1: 220)])
        let component = horizontalComponent(y: 100, x0: 180, x1: 220)
        XCTAssertEqual(drops([component], response), [0],
                       "한쪽이 끊김 없이 이어지면 구조선 끝 조각으로 기각되어야 한다")
    }

    // MARK: ④ 프레임을 관통하는 결함 → 판정 불가이므로 보존

    func testFrameSpanningComponentPreservedAtBoundary() {
        // 이미지 왼쪽 끝에 붙은 조각 — 왼쪽 연장은 이미지 밖이라 판정할 수 없고,
        // 오른쪽은 이어지지 않는다. 경계에서 진짜 스크래치를 지우지 않는 안전 방향.
        let response = responseMap(segments: [(y: 100, x0: 0, x1: 40)])
        let component = horizontalComponent(y: 100, x0: 0, x1: 40)
        XCTAssertTrue(drops([component], response).isEmpty,
                      "연장선이 이미지 밖으로 나가면 판정 불가 — 보존되어야 한다")
    }

    // MARK: 짧지만 가늘고 곧은 조각도 판정 대상

    func testShortButElongatedSegmentJudged() {
        let response = responseMap(segments: [(y: 100, x0: 20, x1: 380)])
        let component = horizontalComponent(y: 100, x0: 190, x1: 206)   // 길이 16, aspect 16
        XCTAssertEqual(drops([component], response), [0],
                       "짧아도 가늘고 곧으면 연장 판정 대상이어야 한다")
    }

    // MARK: 응답이 없으면 판정 보류

    func testNoResponseEvidencePreserves() {
        let response = [Float](repeating: 0, count: width * height)
        let component = horizontalComponent(y: 100, x0: 180, x1: 220)
        XCTAssertTrue(drops([component], response).isEmpty,
                      "본체 응답이 없으면 비율 판정의 분모를 믿을 수 없다 — 보존")
    }
}
