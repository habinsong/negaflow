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

        let all = ICEComponentMask.renderMask(field, excluded: [], dustDilate: 0)
        XCTAssertGreaterThan(all[idx(8, 10, w) * 4], 0)
        XCTAssertGreaterThan(all[idx(30, 10, w) * 4], 0)

        let firstID = field.componentID(atX: 8, y: 10)!
        let masked = ICEComponentMask.renderMask(field, excluded: [firstID], dustDilate: 0)
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

    // 내부 hole 채움(buildLabeled bright:)은 "결함 재질"일 때만: 뚱뚱 먼지의 미검출 중앙(결함 톤)은
    // 채우고, 고리로 말린 결함 안쪽의 정상 콘텐츠(배경 톤)는 채우지 않는다. 물리 한도도 지킨다.
    func testInteriorHoleFilledOnlyWhenDefectToned() {
        let w = 60, h = 60
        var dust = [Bool](repeating: false, count: w * h)
        let scratch = [Bool](repeating: false, count: w * h)
        for y in 0..<h {                       // 반지름 14, 두께 ~2 원형 고리 후보(면적 ~176)
            for x in 0..<w {
                let d = Double((x - 30) * (x - 30) + (y - 30) * (y - 30)).squareRoot()
                if abs(d - 14) <= 1.0 { dust[y * w + x] = true }
            }
        }
        func brightField(interior: Float) -> [Float] {
            var b = [Float](repeating: 0.47, count: w * h)   // 배경 톤
            for y in 0..<h {
                for x in 0..<w {
                    let d = Double((x - 30) * (x - 30) + (y - 30) * (y - 30)).squareRoot()
                    if abs(d - 14) <= 1.0 { b[y * w + x] = 0.96 }      // 고리 = 결함 톤
                    else if d < 13 { b[y * w + x] = interior }         // 안쪽
                }
            }
            return b
        }
        // (1) 안쪽이 결함 톤 = 뚱뚱 먼지의 미검출 중앙 → 채워져야 한다(라벨도 붙는다).
        let fat = ICEComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                maxDustArea: 500, minScratchLength: 8,
                                                bright: brightField(interior: 0.96))
        XCTAssertNotNil(fat.componentID(atX: 30, y: 30), "결함 톤 중앙은 채워져야 한다(뚱뚱 먼지 중앙)")
        // (2) 안쪽이 배경 톤 = 말린 결함 안 정상 콘텐츠 → 채우면 안 된다.
        let loop = ICEComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                 maxDustArea: 500, minScratchLength: 8,
                                                 bright: brightField(interior: 0.47))
        XCTAssertNil(loop.componentID(atX: 30, y: 30), "배경 톤 고리 안쪽은 채우면 안 된다(정상 콘텐츠)")
        // (3) 물리 한도: 결함 톤이어도 hole(dilate 닫힘 안쪽 d<11, ~380px)이 maxDustArea(200)를
        //     넘으면 채우지 않는다(고리 자체(~176px)는 게이트 통과).
        let bounded = ICEComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                    maxDustArea: 200, minScratchLength: 8,
                                                    bright: brightField(interior: 0.96))
        XCTAssertNil(bounded.componentID(atX: 30, y: 30), "물리 한도를 넘는 hole 은 채우지 않는다")
        // bright 없이 호출하면(브러시/단위 테스트 경로) 채움 없음 — 기존 동작 유지.
        let plain = ICEComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                  maxDustArea: 500, minScratchLength: 8)
        XCTAssertNil(plain.componentID(atX: 30, y: 30))
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
