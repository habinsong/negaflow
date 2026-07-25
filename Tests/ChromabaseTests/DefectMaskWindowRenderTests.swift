import XCTest
@testable import Chromabase

// renderMaskWindow(창 직접 렌더)가 "전체 렌더 후 같은 창으로 crop"과 바이트 동일함을 보증한다.
// 커밋이 전체 필드 크기 버퍼 없이 결함 창만 렌더해도 저장 마스크가 변하지 않는 근거.
final class DefectMaskWindowRenderTests: XCTestCase {
    private func makeField(width: Int, height: Int) -> DefectLabelField {
        // 먼지(내부 hole 포함 고리) + 스크래치(가는 가로선) 두 컴포넌트.
        var labels = [Int32](repeating: -1, count: width * height)
        var dustPixels: [Int] = []
        for y in 40...48 {
            for x in 60...68 where !(y >= 43 && y <= 45 && x >= 63 && x <= 65) {
                let p = y * width + x
                labels[p] = 0
                dustPixels.append(p)
            }
        }
        var scratchPixels: [Int] = []
        for x in 100...160 {
            let p = 52 * width + x
            labels[p] = 1
            scratchPixels.append(p)
        }
        let dust = DefectComponent(id: 0, kind: .dust, pixels: dustPixels,
                                minX: 60, minY: 40, maxX: 68, maxY: 48)
        let scratch = DefectComponent(id: 1, kind: .scratch, pixels: scratchPixels,
                                   minX: 100, minY: 52, maxX: 160, maxY: 52)
        return DefectLabelField(width: width, height: height, labels: labels,
                             components: [dust, scratch])
    }

    func testWindowRenderMatchesFullRenderCrop() {
        let width = 400, height = 300
        let field = makeField(width: width, height: height)
        for excluded: Set<Int32> in [[], [0], [1]] {
            let full = DefectComponentMask.renderMask(
                field, excluded: excluded, maxHoleArea: width * height,
                dustDilate: 2, scratchDilate: 3
            )
            // 창 = 생존 bbox ± (dilate + pad). pad 는 임의(계약: bbox+dilate 를 덮으면 동일).
            let pad = 17 + 3
            let survivors = field.components.filter { !excluded.contains($0.id) }
            guard !survivors.isEmpty else { continue }
            let minX = survivors.map(\.minX).min()!, maxX = survivors.map(\.maxX).max()!
            let minY = survivors.map(\.minY).min()!, maxY = survivors.map(\.maxY).max()!
            let x0 = max(0, minX - pad), x1 = min(width, maxX + 1 + pad)
            let y0 = max(0, minY - pad), y1 = min(height, maxY + 1 + pad)
            let window = DefectComponentMask.renderMaskWindow(
                field, excluded: excluded, maxHoleArea: width * height,
                dustDilate: 2, scratchDilate: 3,
                windowX: x0, windowY: y0, windowWidth: x1 - x0, windowHeight: y1 - y0
            )
            var mismatch = 0
            for y in 0..<(y1 - y0) {
                for x in 0..<(x1 - x0) {
                    let w = window[(y * (x1 - x0) + x) * 4]
                    let f = full[((y + y0) * width + (x + x0)) * 4]
                    if w != f { mismatch += 1 }
                }
            }
            XCTAssertEqual(mismatch, 0, "excluded=\(excluded) 창 렌더 불일치 \(mismatch)px")
            // 창 밖(전체 렌더 기준)에 마스크 픽셀이 없어야 창이 완전하다.
            var outside = 0
            for y in 0..<height {
                for x in 0..<width where full[(y * width + x) * 4] > 0 {
                    if x < x0 || x >= x1 || y < y0 || y >= y1 { outside += 1 }
                }
            }
            XCTAssertEqual(outside, 0, "창이 마스크 픽셀을 놓침(excluded=\(excluded))")
        }
    }

    func testWindowRenderFillsInteriorHoleLikeFullRender() {
        let width = 400, height = 300
        let field = makeField(width: width, height: height)
        // 먼지 고리 내부(3×3 hole)가 창 렌더에서도 채워지는지 표본 확인.
        let x0 = 30, y0 = 20, ww = 120, wh = 60
        let window = DefectComponentMask.renderMaskWindow(
            field, excluded: [], maxHoleArea: width * height,
            dustDilate: 0, scratchDilate: 1,
            windowX: x0, windowY: y0, windowWidth: ww, windowHeight: wh
        )
        let holeOffset = ((44 - y0) * ww + (64 - x0)) * 4
        XCTAssertEqual(window[holeOffset], 255, "고리 내부 hole 이 채워지지 않음")
    }
}
