import Foundation

// 후보 bool 맵 → 연결요소 형태 게이트 → RGBA8 마스크(흰색=결함).
// 먼지는 작은 blob, 스크래치는 길고 가는 선만 통과시킨다.
enum ICEComponentMask {
    static func build(width: Int, height: Int,
                      dust: [Bool], scratch: [Bool],
                      maxDustArea: Int, minScratchLength: Int,
                      minScratchAspect: Double = 2.5,
                      dustMaxAspect: Double = 4.0,
                      minThickDefect: Int = .max, maxThickDefect: Int = 0,
                      dustDilate: Int = 0) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)

        // 먼지: 면적 상한 이하만(넓은 하이라이트 halo 등 제외). 뚱뚱한 먼지는 경계만 대비가
        // 커서 검출되고 균일한 중앙은 미검출되므로, 닫힌 경계로 둘러싸인 내부 hole을 채워
        // 중앙까지 결함에 포함시킨다(과검출 방지: hole 면적이 maxDustArea 이하일 때만).
        forEachComponent(dust, width: width, height: height) { comp, minX, maxX, minY, maxY in
            let boxW = maxX - minX + 1, boxH = maxY - minY + 1
            let aspect = Double(max(boxW, boxH)) / Double(max(1, min(boxW, boxH)))
            // 컴팩트한 blob 또는 두꺼운 선/곡선 결함만 통과(passesDustGate). dustMaxAspect 를 올리면
            // 꼬불꼬불·길쭉한 먼지를, 두께 게이트는 두꺼운 스크래치까지 허용한다 — grain/하늘은 이미
            // 후보 단계(임계)에서 걸러지므로 형태 게이트 완화로 폭발하지 않는다.
            guard passesDustGate(count: comp.count, boxW: boxW, boxH: boxH, aspect: aspect,
                                 maxDustArea: maxDustArea, dustMaxAspect: dustMaxAspect,
                                 minThickDefect: minThickDefect, maxThickDefect: maxThickDefect) else { return }
            // brush 영역에선 반경 dustDilate(>0)로 팽창 — 흰 먼지의 부드러운 경계(halo)까지 마스크로
            // 덮어, 잔존 흰색과 복원 시 그 흰색을 성한 픽셀로 참조해 번지는 것을 막는다. 전역(0)은
            // 넓은 하이라이트 오탐을 막기 위해 팽창하지 않는다.
            for p in comp { paint(p, width: width, height: height, radius: dustDilate, into: &bytes) }
            fillInteriorHoles(&bytes, minX: minX, maxX: maxX, minY: minY, maxY: maxY,
                              width: width, height: height, maxHoleArea: maxDustArea)
        }

        // 스크래치: 길고 가는 연결요소만. 1px 팽창으로 선 두께 보강.
        forEachComponent(scratch, width: width, height: height) { comp, minX, maxX, minY, maxY in
            let boxW = maxX - minX + 1, boxH = maxY - minY + 1
            let longSide = max(boxW, boxH), shortSide = max(1, min(boxW, boxH))
            guard longSide >= minScratchLength, Double(longSide) / Double(shortSide) >= minScratchAspect else { return }
            for p in comp { paint(p, width: width, height: height, radius: 1, into: &bytes) }
        }
        return bytes
    }

    /// 먼지/두꺼운 결함 통과 게이트.
    ///  (1) 컴팩트 blob: 면적 ≤ maxDustArea 이고 aspect ≤ dustMaxAspect.
    ///  (2) 두꺼운 선·곡선 결함: 평균 두께(픽셀수/긴변)가 [minThick, maxThick]. 두꺼운 스크래치/꼬불꼬불
    ///      먼지를 aspect·면적 무관하게 살리되, 가는 정상선(두께 부족)·넓은 정상면(두께 과다)은 배제한다.
    /// 기본값(minThick=.max)에선 (2)가 비활성 — brush/전역 경로는 기존 컴팩트 게이트만 쓴다.
    private static func passesDustGate(count: Int, boxW: Int, boxH: Int, aspect: Double,
                                       maxDustArea: Int, dustMaxAspect: Double,
                                       minThickDefect: Int, maxThickDefect: Int) -> Bool {
        if count <= maxDustArea, aspect <= dustMaxAspect { return true }
        let avgThick = Double(count) / Double(max(1, max(boxW, boxH)))
        return avgThick >= Double(minThickDefect) && avgThick <= Double(maxThickDefect)
    }

    // MARK: connected components (8-이웃)

    private static func forEachComponent(_ cand: [Bool], width: Int, height: Int,
                                         _ body: (_ comp: [Int], _ minX: Int, _ maxX: Int, _ minY: Int, _ maxY: Int) -> Void) {
        let n = width * height
        var visited = [Bool](repeating: false, count: n)
        var stack = [Int](); var comp = [Int]()
        for start in 0..<n where cand[start] && !visited[start] {
            comp.removeAll(keepingCapacity: true)
            stack.removeAll(keepingCapacity: true)
            stack.append(start); visited[start] = true
            var minX = width, maxX = 0, minY = height, maxY = 0
            while let cur = stack.popLast() {
                comp.append(cur)
                let y = cur / width, x = cur - (cur / width) * width
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
                for ny in max(0, y - 1)...min(height - 1, y + 1) {
                    for nx in max(0, x - 1)...min(width - 1, x + 1) where nx != x || ny != y {
                        let next = ny * width + nx
                        if cand[next] && !visited[next] { visited[next] = true; stack.append(next) }
                    }
                }
            }
            body(comp, minX, maxX, minY, maxY)
        }
    }

    /// component bbox 내에서 결함 경계로 둘러싸여 외부와 단절된 0 영역(내부 hole)을 채운다.
    /// bbox 테두리에서 flood 되지 않는 비결함 픽셀 = 내부 hole. 면적이 한도 이하일 때만 채워
    /// 정상 구조(큰 영역)를 결함 처리하지 않는다.
    private static func fillInteriorHoles(_ bytes: inout [UInt8], minX: Int, maxX: Int, minY: Int, maxY: Int,
                                          width: Int, height: Int, maxHoleArea: Int) {
        let x0 = max(0, minX - 1), x1 = min(width - 1, maxX + 1)
        let y0 = max(0, minY - 1), y1 = min(height - 1, maxY + 1)
        let bw = x1 - x0 + 1, bh = y1 - y0 + 1
        guard bw > 2, bh > 2 else { return }
        func isDefect(_ x: Int, _ y: Int) -> Bool { bytes[(y * width + x) * 4] > 8 }
        func bidx(_ x: Int, _ y: Int) -> Int { (y - y0) * bw + (x - x0) }

        var outside = [Bool](repeating: false, count: bw * bh)
        var stack = [Int]()
        for x in x0...x1 {
            for y in [y0, y1] where !isDefect(x, y) && !outside[bidx(x, y)] {
                outside[bidx(x, y)] = true; stack.append(bidx(x, y))
            }
        }
        for y in y0...y1 {
            for x in [x0, x1] where !isDefect(x, y) && !outside[bidx(x, y)] {
                outside[bidx(x, y)] = true; stack.append(bidx(x, y))
            }
        }
        while let i = stack.popLast() {
            let lx = i % bw + x0, ly = i / bw + y0
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = lx + dx, ny = ly + dy
                guard nx >= x0, nx <= x1, ny >= y0, ny <= y1 else { continue }
                if !outside[bidx(nx, ny)] && !isDefect(nx, ny) {
                    outside[bidx(nx, ny)] = true; stack.append(bidx(nx, ny))
                }
            }
        }
        var holes = [Int]()
        for y in y0...y1 {
            for x in x0...x1 where !isDefect(x, y) && !outside[bidx(x, y)] { holes.append(y * width + x) }
        }
        guard !holes.isEmpty, holes.count <= maxHoleArea else { return }
        for p in holes {
            let o = p * 4
            bytes[o] = 255; bytes[o + 1] = 255; bytes[o + 2] = 255; bytes[o + 3] = 255
        }
    }

    private static func paint(_ pixel: Int, width: Int, height: Int, radius r: Int, into bytes: inout [UInt8]) {
        let y = pixel / width, x = pixel - (pixel / width) * width
        for ny in max(0, y - r)...min(height - 1, y + r) {
            for nx in max(0, x - r)...min(width - 1, x + r) {
                let o = (ny * width + nx) * 4
                bytes[o] = 255; bytes[o + 1] = 255; bytes[o + 2] = 255; bytes[o + 3] = 255
            }
        }
    }

    // MARK: Region ICE — 라벨 빌드 / 마스크 렌더 (게이트·페인팅은 build 와 동일 로직)

    /// 후보 → 게이트 통과 컴포넌트에 라벨을 부여한다. build 와 같은 면적/aspect/길이 기준을 쓰되
    /// RGBA8 대신 라벨맵+컴포넌트 목록을 낸다(클릭 제외 편집용). 페인팅(dust dilate/hole-fill,
    /// scratch dilate)은 하지 않는다 — 그건 renderMask 가 build 와 동일하게 처리한다.
    static func buildLabeled(width: Int, height: Int,
                             dust: [Bool], scratch: [Bool],
                             maxDustArea: Int, minScratchLength: Int,
                             minScratchAspect: Double = 2.5,
                             dustMaxAspect: Double = 4.0,
                             minThickDefect: Int = .max, maxThickDefect: Int = 0) -> ICELabelField {
        var labels = [Int32](repeating: -1, count: width * height)
        var components: [ICEComponent] = []
        var nextID: Int32 = 0

        forEachComponent(dust, width: width, height: height) { comp, minX, maxX, minY, maxY in
            let boxW = maxX - minX + 1, boxH = maxY - minY + 1
            let aspect = Double(max(boxW, boxH)) / Double(max(1, min(boxW, boxH)))
            guard passesDustGate(count: comp.count, boxW: boxW, boxH: boxH, aspect: aspect,
                                 maxDustArea: maxDustArea, dustMaxAspect: dustMaxAspect,
                                 minThickDefect: minThickDefect, maxThickDefect: maxThickDefect) else { return }
            let id = nextID; nextID += 1
            for p in comp { labels[p] = id }
            components.append(ICEComponent(id: id, kind: .dust, pixels: comp,
                                           minX: minX, minY: minY, maxX: maxX, maxY: maxY))
        }
        forEachComponent(scratch, width: width, height: height) { comp, minX, maxX, minY, maxY in
            let boxW = maxX - minX + 1, boxH = maxY - minY + 1
            let longSide = max(boxW, boxH), shortSide = max(1, min(boxW, boxH))
            guard longSide >= minScratchLength, Double(longSide) / Double(shortSide) >= minScratchAspect else { return }
            let id = nextID; nextID += 1
            // 먼지와 겹치는 픽셀은 먼지 라벨을 유지(겹침은 드묾). 빈 픽셀만 스크래치로 라벨링.
            for p in comp where labels[p] < 0 { labels[p] = id }
            components.append(ICEComponent(id: id, kind: .scratch, pixels: comp,
                                           minX: minX, minY: minY, maxX: maxX, maxY: maxY))
        }
        return ICELabelField(width: width, height: height, labels: labels, components: components)
    }

    /// 살아남은(excluded 제외) 컴포넌트를 build 와 동일하게 페인팅한 RGBA8 마스크.
    /// dust 는 dustDilate 팽창 + 내부 hole 채움, scratch 는 1px 팽창 — build 페인팅과 일치한다.
    static func renderMask(_ field: ICELabelField, excluded: Set<Int32>,
                           maxHoleArea: Int, dustDilate: Int = 0) -> [UInt8] {
        let width = field.width, height = field.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for comp in field.components where !excluded.contains(comp.id) {
            switch comp.kind {
            case .dust:
                for p in comp.pixels { paint(p, width: width, height: height, radius: dustDilate, into: &bytes) }
                fillInteriorHoles(&bytes, minX: comp.minX, maxX: comp.maxX, minY: comp.minY, maxY: comp.maxY,
                                  width: width, height: height, maxHoleArea: maxHoleArea)
            case .scratch:
                for p in comp.pixels { paint(p, width: width, height: height, radius: 1, into: &bytes) }
            }
        }
        return bytes
    }
}
