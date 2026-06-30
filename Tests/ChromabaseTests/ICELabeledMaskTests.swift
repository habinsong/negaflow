import XCTest
@testable import Chromabase

// ICEComponentMask.buildLabeled / renderMask 의 라벨링·게이트·클릭 제외를 합성 후보로 검증한다.
final class ICELabeledMaskTests: XCTestCase {
    private func idx(_ x: Int, _ y: Int, _ w: Int) -> Int { y * w + x }

    func testDustBlobLabeled() {
        let w = 40, h = 40
        var dust = [Bool](repeating: false, count: w * h)
        let scratch = [Bool](repeating: false, count: w * h)
        for dy in -1...1 { for dx in -1...1 { dust[idx(10 + dx, 10 + dy, w)] = true } }   // 3x3 블롭
        let field = ICEComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                  maxDustArea: 150, minScratchLength: 8)
        XCTAssertEqual(field.components.count, 1)
        XCTAssertEqual(field.components.first?.kind, .dust)
        XCTAssertEqual(field.componentID(atX: 10, y: 10), field.components.first?.id)
        XCTAssertNil(field.componentID(atX: 0, y: 0))
        XCTAssertEqual(field.components.first?.pixelCount, 9)
    }

    func testScratchLineLabeled() {
        let w = 60, h = 60
        let dust = [Bool](repeating: false, count: w * h)
        var scratch = [Bool](repeating: false, count: w * h)
        for y in 5..<45 { scratch[idx(30, y, w)] = true }   // 길이 40 세로선
        let field = ICEComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                  maxDustArea: 150, minScratchLength: 8, minScratchAspect: 2.5)
        XCTAssertEqual(field.components.count, 1)
        XCTAssertEqual(field.components.first?.kind, .scratch)
    }

    func testGatesRejectOversizeDustAndShortScratch() {
        let w = 50, h = 50
        var dust = [Bool](repeating: false, count: w * h)
        var scratch = [Bool](repeating: false, count: w * h)
        for y in 10..<30 { for x in 10..<30 { dust[idx(x, y, w)] = true } }   // 20x20=400 > maxDustArea
        for y in 40..<44 { scratch[idx(45, y, w)] = true }                    // 길이 4 < minScratchLength
        let field = ICEComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                  maxDustArea: 150, minScratchLength: 8)
        XCTAssertEqual(field.components.count, 0, "과대 먼지·과소 스크래치는 게이트에서 제외돼야 한다")
    }

    func testRenderMaskExcludesSelectedComponent() {
        let w = 40, h = 20
        var dust = [Bool](repeating: false, count: w * h)
        let scratch = [Bool](repeating: false, count: w * h)
        dust[idx(8, 10, w)] = true
        dust[idx(30, 10, w)] = true
        let field = ICEComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                  maxDustArea: 150, minScratchLength: 8)
        XCTAssertEqual(field.components.count, 2)

        let all = ICEComponentMask.renderMask(field, excluded: [], maxHoleArea: 150, dustDilate: 0)
        XCTAssertGreaterThan(all[idx(8, 10, w) * 4], 0)
        XCTAssertGreaterThan(all[idx(30, 10, w) * 4], 0)

        let firstID = field.componentID(atX: 8, y: 10)!
        let masked = ICEComponentMask.renderMask(field, excluded: [firstID], maxHoleArea: 150, dustDilate: 0)
        XCTAssertEqual(masked[idx(8, 10, w) * 4], 0, "제외한 컴포넌트는 마스크에서 빠져야 한다")
        XCTAssertGreaterThan(masked[idx(30, 10, w) * 4], 0, "제외하지 않은 컴포넌트는 남아야 한다")
    }

    func testNearestComponentWithinRadius() {
        let w = 30, h = 30
        var dust = [Bool](repeating: false, count: w * h)
        let scratch = [Bool](repeating: false, count: w * h)
        dust[idx(15, 15, w)] = true   // 1픽셀 먼지
        let field = ICEComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                  maxDustArea: 150, minScratchLength: 8)
        let id = field.componentID(atX: 15, y: 15)
        XCTAssertNotNil(id)
        XCTAssertNil(field.componentID(atX: 17, y: 15))                          // 정확 위치엔 없음
        XCTAssertEqual(field.nearestComponentID(atX: 17, y: 15, radius: 3), id)  // 반경 내 최근접
        XCTAssertNil(field.nearestComponentID(atX: 25, y: 25, radius: 3))        // 반경 밖
    }

    // dust aspect 상한은 파라미터로 완화 가능해야 한다 — 꼬불꼬불·길쭉한 먼지(곡선 결함)를 살리려고.
    func testDustAspectGateRelaxable() {
        let w = 60, h = 30
        var dust = [Bool](repeating: false, count: w * h)
        let scratch = [Bool](repeating: false, count: w * h)
        for y in 13..<17 { for x in 18..<42 { dust[idx(x, y, w)] = true } }   // 24×4 길쭉(aspect 6)
        let strict = ICEComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                   maxDustArea: 200, minScratchLength: 8)   // dustMaxAspect=4 기본
        XCTAssertEqual(strict.components.count, 0, "aspect 6 길쭉 먼지는 기본 게이트(4)에서 제외")
        let relaxed = ICEComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                    maxDustArea: 200, minScratchLength: 8, dustMaxAspect: 8.0)
        XCTAssertEqual(relaxed.components.count, 1, "aspect 6 길쭉 먼지는 완화 게이트(8)에서 통과")
        XCTAssertEqual(relaxed.components.first?.kind, .dust)
    }
}
