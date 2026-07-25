import XCTest
@testable import Chromabase

// 롤링 윈도우 boxMean / Bool dilateMask 가 기존 경로와 **비트 동일**함을 보증한다.
//  • boxMean(롤링) vs boxMeans(전체 적분영상) — 같은 산술 순서를 쓰므로 완전 일치해야 한다.
//  • dilateMask(Bool) vs morphMax(0/1 Float) > 0.5 — 클램프 윈도우 OR 동일성.
final class DefectBoxMeanRollingEquivalenceTests: XCTestCase {

    private struct SeededNoise {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
    }

    private func makePlane(width: Int, height: Int, seed: UInt64) -> [Float] {
        var noise = SeededNoise(seed: seed)
        return (0..<(width * height)).map { _ in noise.next() }
    }

    func testRollingBoxMeanMatchesFullIntegralBitExactly() {
        let cases: [(w: Int, h: Int, r: Int)] = [
            (64, 48, 1), (64, 48, 4), (128, 96, 12), (97, 65, 7),
            (256, 224, 24), (256, 224, 48), (33, 129, 5), (200, 10, 3),
        ]
        for (index, testCase) in cases.enumerated() {
            let plane = makePlane(width: testCase.w, height: testCase.h,
                                  seed: UInt64(1000 + index))
            let rolling = DefectMorphology.boxMean(
                plane, width: testCase.w, height: testCase.h, radius: testCase.r
            )
            let reference = DefectMorphology.boxMeans(
                plane, width: testCase.w, height: testCase.h, radii: [testCase.r]
            )[0]
            XCTAssertEqual(rolling.count, reference.count)
            for i in 0..<rolling.count {
                guard rolling[i].bitPattern != reference[i].bitPattern else { continue }
                return XCTFail("""
                boxMean 비트 불일치: case=\(testCase) index=\(i) \
                rolling=\(rolling[i]) reference=\(reference[i])
                """)
            }
        }
    }

    func testRollingBoxMeanFallsBackWhenRadiusDominatesHeight() {
        // 링(2r+2)이 h+1 이상이면 전체 적분 경로로 폴백 — 결과 역시 동일해야 한다.
        let plane = makePlane(width: 40, height: 12, seed: 7)
        let rolling = DefectMorphology.boxMean(plane, width: 40, height: 12, radius: 8)
        let reference = DefectMorphology.boxMeans(plane, width: 40, height: 12, radii: [8])[0]
        for i in 0..<rolling.count {
            XCTAssertEqual(rolling[i].bitPattern, reference[i].bitPattern, "index \(i)")
        }
    }

    func testDilateMaskMatchesFloatMorphMax() {
        var noise = SeededNoise(seed: 55)
        let cases: [(w: Int, h: Int, r: Int)] = [
            (64, 48, 1), (64, 48, 3), (97, 65, 6), (128, 96, 12), (30, 200, 4),
        ]
        for testCase in cases {
            let count = testCase.w * testCase.h
            var mask = [Bool](repeating: false, count: count)
            for i in 0..<count where noise.next() < 0.03 { mask[i] = true }
            // 테두리 케이스 포함.
            mask[0] = true
            mask[count - 1] = true

            let boolDilated = DefectMorphology.dilateMask(
                mask, width: testCase.w, height: testCase.h, radius: testCase.r
            )
            var floatMask = [Float](repeating: 0, count: count)
            for i in 0..<count where mask[i] { floatMask[i] = 1 }
            let floatDilated = DefectMorphology.morphMax(
                floatMask, width: testCase.w, height: testCase.h, radius: testCase.r
            )
            for i in 0..<count {
                XCTAssertEqual(boolDilated[i], floatDilated[i] > 0.5,
                               "dilate 불일치: case=\(testCase) index=\(i)")
            }
        }
    }
}
