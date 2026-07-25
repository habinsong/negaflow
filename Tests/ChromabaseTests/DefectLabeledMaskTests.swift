import XCTest
@testable import Chromabase

// DefectComponentMask.buildLabeled / renderMask 의 라벨링·게이트·클릭 제외를 합성 후보로 검증한다.
final class DefectLabeledMaskTests: XCTestCase {
    private func idx(_ x: Int, _ y: Int, _ w: Int) -> Int { y * w + x }

    func testDustBlobLabeled() {
        let w = 40, h = 40
        var dust = [Bool](repeating: false, count: w * h)
        let scratch = [Bool](repeating: false, count: w * h)
        for dy in -1...1 { for dx in -1...1 { dust[idx(10 + dx, 10 + dy, w)] = true } }   // 3x3 블롭
        let field = DefectComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
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
        let field = DefectComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
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
        let field = DefectComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                  maxDustArea: 150, minScratchLength: 8)
        XCTAssertEqual(field.components.count, 0, "과대 먼지·과소 스크래치는 게이트에서 제외돼야 한다")
    }

    func testRenderMaskExcludesSelectedComponent() {
        let w = 40, h = 20
        var dust = [Bool](repeating: false, count: w * h)
        let scratch = [Bool](repeating: false, count: w * h)
        dust[idx(8, 10, w)] = true
        dust[idx(30, 10, w)] = true
        let field = DefectComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                  maxDustArea: 150, minScratchLength: 8)
        XCTAssertEqual(field.components.count, 2)

        let all = DefectComponentMask.renderMask(field, excluded: [], maxHoleArea: 150, dustDilate: 0)
        XCTAssertGreaterThan(all[idx(8, 10, w) * 4], 0)
        XCTAssertGreaterThan(all[idx(30, 10, w) * 4], 0)

        let firstID = field.componentID(atX: 8, y: 10)!
        let masked = DefectComponentMask.renderMask(field, excluded: [firstID], maxHoleArea: 150, dustDilate: 0)
        XCTAssertEqual(masked[idx(8, 10, w) * 4], 0, "제외한 컴포넌트는 마스크에서 빠져야 한다")
        XCTAssertGreaterThan(masked[idx(30, 10, w) * 4], 0, "제외하지 않은 컴포넌트는 남아야 한다")
    }

    func testNearestComponentWithinRadius() {
        let w = 30, h = 30
        var dust = [Bool](repeating: false, count: w * h)
        let scratch = [Bool](repeating: false, count: w * h)
        dust[idx(15, 15, w)] = true   // 1픽셀 먼지
        let field = DefectComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                  maxDustArea: 150, minScratchLength: 8)
        let id = field.componentID(atX: 15, y: 15)
        XCTAssertNotNil(id)
        XCTAssertNil(field.componentID(atX: 17, y: 15))                          // 정확 위치엔 없음
        XCTAssertEqual(field.nearestComponentID(atX: 17, y: 15, radius: 3), id)  // 반경 내 최근접
        XCTAssertNil(field.nearestComponentID(atX: 25, y: 25, radius: 3))        // 반경 밖
    }

    func testComponentIDReturnsNilForMissingOrShortLabelStorage() {
        let empty = DefectLabelField(width: 1, height: 1, labels: [], components: [])
        XCTAssertNil(empty.componentID(atX: 0, y: 0))
        XCTAssertNil(empty.nearestComponentID(atX: 0, y: 0, radius: 2))

        let short = DefectLabelField(width: 2, height: 2, labels: [-1], components: [])
        XCTAssertNil(short.componentID(atX: 1, y: 1))
    }

    // 그레인 필드 필터: 빽빽한 작은 컴포넌트(낱알 그레인)는 통째 기각, 고립된 작은 먼지와 큰 결함은
    // 보존한다. 실제 필름 그레인이 aggressive 임계를 낱알로 통과해 칠 자국이 층층이 밀리는 와이프 방지.
    func testGrainFieldDropsDenseSmallComponentsKeepsIsolatedAndLarge() {
        let w = 200, h = 200
        var dust = [Bool](repeating: false, count: w * h)
        let scratch = [Bool](repeating: false, count: w * h)
        // 빽빽한 작은 blob 필드(2×2 를 12px 간격 5×5 = 25개 — 반경 48 안에 ≥10개)
        for gy in stride(from: 40, to: 100, by: 12) {
            for gx in stride(from: 40, to: 100, by: 12) {
                for dy in 0..<2 { for dx in 0..<2 { dust[idx(gx + dx, gy + dy, w)] = true } }
            }
        }
        // 고립된 작은 먼지(필드에서 멀리)
        for dy in 0..<2 { for dx in 0..<2 { dust[idx(160 + dx, 160 + dy, w)] = true } }
        // 큰 결함(작은 컴포넌트 풀에 안 들어감 — 필드 근처여도 보존)
        for dy in 0..<6 { for dx in 0..<6 { dust[idx(130 + dx, 50 + dy, w)] = true } }
        let field = DefectComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                  maxDustArea: 400, minScratchLength: 8)
        XCTAssertEqual(field.components.count, 2, "빽빽한 낱알 필드는 기각, 고립 먼지+큰 결함만 남아야 한다")
        XCTAssertNil(field.componentID(atX: 41, y: 41), "그레인 필드의 낱알은 기각되어야 한다")
        XCTAssertNotNil(field.nearestComponentID(atX: 160, y: 160, radius: 2), "고립된 작은 먼지는 보존")
        XCTAssertNotNil(field.nearestComponentID(atX: 132, y: 52, radius: 2), "큰 결함은 보존")
    }

    // dust aspect 상한은 파라미터로 완화 가능해야 한다 — 꼬불꼬불·길쭉한 먼지(곡선 결함)를 살리려고.
    func testDustAspectGateRelaxable() {
        let w = 60, h = 30
        var dust = [Bool](repeating: false, count: w * h)
        let scratch = [Bool](repeating: false, count: w * h)
        for y in 13..<17 { for x in 18..<42 { dust[idx(x, y, w)] = true } }   // 24×4 길쭉(aspect 6)
        let strict = DefectComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                   maxDustArea: 200, minScratchLength: 8)   // dustMaxAspect=4 기본
        XCTAssertEqual(strict.components.count, 0, "aspect 6 길쭉 먼지는 기본 게이트(4)에서 제외")
        let relaxed = DefectComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                    maxDustArea: 200, minScratchLength: 8, dustMaxAspect: 8.0)
        XCTAssertEqual(relaxed.components.count, 1, "aspect 6 길쭉 먼지는 완화 게이트(8)에서 통과")
        XCTAssertEqual(relaxed.components.first?.kind, .dust)
    }
}
