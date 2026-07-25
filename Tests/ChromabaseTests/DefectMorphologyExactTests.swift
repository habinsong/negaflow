import XCTest
import Foundation
@testable import Chromabase

// deque 기반 O(N) morphMin/morphMax 가 naïve 클램프-윈도우 구현과 **정확히 동일**한지 검증.
// 속도 최적화(van Herk/Gil-Werman 계열)가 결과를 바꾸지 않음을 보장하는 회귀 가드.
final class DefectMorphologyExactTests: XCTestCase {
    private func legacyBoxMean(_ src: [Float], _ w: Int, _ h: Int, _ r: Int) -> [Float] {
        let iw = w + 1
        var integral = [Double](repeating: 0, count: iw * (h + 1))
        for y in 0..<h {
            var rowSum = 0.0
            let srcRow = y * w, intRow = (y + 1) * iw, intPrev = y * iw
            for x in 0..<w {
                rowSum += Double(src[srcRow + x])
                integral[intRow + x + 1] = integral[intPrev + x + 1] + rowSum
            }
        }
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let y0 = max(0, y - r), y1 = min(h - 1, y + r)
            for x in 0..<w {
                let x0 = max(0, x - r), x1 = min(w - 1, x + r)
                let sum = integral[(y1 + 1) * iw + (x1 + 1)] - integral[y0 * iw + (x1 + 1)]
                    - integral[(y1 + 1) * iw + x0] + integral[y0 * iw + x0]
                out[y * w + x] = Float(sum / Double((y1 - y0 + 1) * (x1 - x0 + 1)))
            }
        }
        return out
    }

    private func naiveMin(_ s: [Float], _ w: Int, _ h: Int, _ r: Int) -> [Float] {
        var tmp = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            var acc = Float.greatestFiniteMagnitude
            for xx in max(0, x - r)...min(w - 1, x + r) { acc = min(acc, s[y * w + xx]) }
            tmp[y * w + x] = acc
        } }
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            var acc = Float.greatestFiniteMagnitude
            for yy in max(0, y - r)...min(h - 1, y + r) { acc = min(acc, tmp[yy * w + x]) }
            out[y * w + x] = acc
        } }
        return out
    }
    private func naiveMax(_ s: [Float], _ w: Int, _ h: Int, _ r: Int) -> [Float] {
        var tmp = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            var acc = -Float.greatestFiniteMagnitude
            for xx in max(0, x - r)...min(w - 1, x + r) { acc = max(acc, s[y * w + xx]) }
            tmp[y * w + x] = acc
        } }
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            var acc = -Float.greatestFiniteMagnitude
            for yy in max(0, y - r)...min(h - 1, y + r) { acc = max(acc, tmp[yy * w + x]) }
            out[y * w + x] = acc
        } }
        return out
    }

    func testDequeMorphologyMatchesNaive() {
        var seed: UInt64 = 0x1234_5678
        func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1; return Float(seed >> 40) / Float(1 << 24) }
        // 다양한 크기·반경(창 > 폭 포함)에서 min/max 를 정수 비교.
        for (w, h) in [(1, 1), (5, 3), (17, 9), (33, 40), (64, 48)] {
            let src = (0..<(w * h)).map { _ in rnd() }
            for r in [0, 1, 2, 4, 8, 12, max(w, h) + 3] {
                XCTAssertEqual(DefectMorphology.morphMin(src, width: w, height: h, radius: r),
                               naiveMin(src, w, h, r), "morphMin 불일치 w=\(w) h=\(h) r=\(r)")
                XCTAssertEqual(DefectMorphology.morphMax(src, width: w, height: h, radius: r),
                               naiveMax(src, w, h, r), "morphMax 불일치 w=\(w) h=\(h) r=\(r)")
            }
        }
    }

    func testSharedIntegralBoxMeansMatchIndependentLegacyResults() {
        var seed: UInt64 = 0xC0FF_EE12
        func rnd() -> Float {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Float(seed >> 40) / Float(1 << 24)
        }
        for (w, h) in [(1, 1), (7, 5), (31, 23), (96, 64)] {
            let src = (0..<(w * h)).map { _ in rnd() }
            let radii = [0, 1, 3, 8, 12, 36, max(w, h) + 5]
            let expected = radii.map { legacyBoxMean(src, w, h, $0) }
            XCTAssertEqual(
                DefectMorphology.boxMeans(src, width: w, height: h, radii: radii),
                expected
            )
            XCTAssertEqual(
                DefectMorphology.boxMeans(src, width: w, height: h, radii: radii, parallel: true),
                expected
            )
        }
    }

    func testSharedIntegralBoxMeansPerformanceWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["DEFECT_BOX_MEAN_PERF"] == "1" else {
            throw XCTSkip("Set DEFECT_BOX_MEAN_PERF=1 and use Release to run the shared-integral benchmark.")
        }
        let w = 1_400, h = 1_200
        var seed: UInt64 = 0x51A7_E123
        let src = (0..<(w * h)).map { _ -> Float in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Float(seed >> 40) / Float(1 << 24)
        }
        var legacyTimes: [Double] = []
        var sharedTimes: [Double] = []
        for _ in 0..<5 {
            let legacyStarted = Date()
            let legacy = [
                legacyBoxMean(src, w, h, 12),
                legacyBoxMean(src, w, h, 36),
            ]
            legacyTimes.append(Date().timeIntervalSince(legacyStarted))

            let sharedStarted = Date()
            let shared = DefectMorphology.boxMeans(src, width: w, height: h, radii: [12, 36])
            sharedTimes.append(Date().timeIntervalSince(sharedStarted))
            XCTAssertEqual(shared, legacy)
        }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        let legacyMedian = median(legacyTimes)
        let sharedMedian = median(sharedTimes)
        print("[box-mean] legacyMedian=\(legacyMedian)s sharedMedian=\(sharedMedian)s")
        XCTAssertLessThan(sharedMedian, legacyMedian)
    }
}
