import XCTest
@testable import Chromabase

// deque 기반 O(N) morphMin/morphMax 가 naïve 클램프-윈도우 구현과 **정확히 동일**한지 검증.
// 속도 최적화(van Herk/Gil-Werman 계열)가 결과를 바꾸지 않음을 보장하는 회귀 가드.
final class ICEMorphologyExactTests: XCTestCase {
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
                XCTAssertEqual(ICEMorphology.morphMin(src, width: w, height: h, radius: r),
                               naiveMin(src, w, h, r), "morphMin 불일치 w=\(w) h=\(h) r=\(r)")
                XCTAssertEqual(ICEMorphology.morphMax(src, width: w, height: h, radius: r),
                               naiveMax(src, w, h, r), "morphMax 불일치 w=\(w) h=\(h) r=\(r)")
            }
        }
    }
}
