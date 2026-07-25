import Foundation

extension DefectComponentMask {
    static func passesDustGate(count: Int, boxW: Int, boxH: Int, aspect: Double,
                                       maxDustArea: Int, dustMaxAspect: Double,
                                       minThickDefect: Int, maxThickDefect: Int) -> Bool {
        if count <= maxDustArea, aspect <= dustMaxAspect { return true }
        let avgThick = Double(count) / Double(max(1, max(boxW, boxH)))
        return avgThick >= Double(minThickDefect) && avgThick <= Double(maxThickDefect)
    }

    /// PCA 경로로 스크래치를 인정하는 최소 주축 길이. 대각선 얇은 스크래치(수십~수백 px)를 살리되,
    /// 구조물 모서리의 대각 ridge 블립(짧은 45° 응답, ≤ 짧은 적분 창 ~7px)은 기하 증거 부족으로
    /// 기각한다 — bbox 게이트(aspect 1)가 원래 걸러 주던 것을 PCA 가 우회하지 않게 하는 하한.
    static let pcaMinLength = 12.0

    /// 스크래치 형태 게이트 — 회전 불변. bbox(축 정렬) 게이트는 기존 그대로, 거기에 더해 PCA(주축)
    /// 신장도가 충분히 "길게" 확인될 때(pcaMinLength 이상)도 통과시켜 대각선 얇은 스크래치
    /// (bbox aspect≈1)가 각도 때문에 기각되지 않게 한다(LSD 의 임의 각도 직사각형 근사와 같은 정신).
    /// 평균 두께가 maxScratchThickness 를 넘는 "스크래치"는 카펫이므로 기각.
    /// 통과 시 PCA 메트릭을 돌려준다(weak-only 기하 판정 재사용).
    static func passesScratchGate(_ comp: [Int], width: Int,
                                          minX: Int, maxX: Int, minY: Int, maxY: Int,
                                          minScratchLength: Int, minScratchAspect: Double)
        -> (length: Double, thickness: Double, aspect: Double)? {
        let boxW = maxX - minX + 1, boxH = maxY - minY + 1
        let longSide = max(boxW, boxH), shortSide = max(1, min(boxW, boxH))
        let pca = pcaMetrics(comp, width: width)
        guard pca.thickness <= maxScratchThickness else { return nil }
        let boxPass = longSide >= minScratchLength
            && Double(longSide) / Double(shortSide) >= minScratchAspect
        let pcaPass = pca.length >= max(Double(minScratchLength), pcaMinLength)
            && pca.aspect >= minScratchAspect
        guard boxPass || pcaPass else { return nil }
        return pca
    }

    /// 컴포넌트 PCA 형태 측정 — DefectShape 공유 구현(분류기와 동일 수치).
    static func pcaMetrics(_ comp: [Int], width: Int)
        -> (length: Double, thickness: Double, aspect: Double) {
        let m = DefectShape.pcaMetrics(comp, width: width)
        return (m.length, m.thickness, m.aspect)
    }

    /// 내부 hole 채움 상한: 전달된 상한과 "컴포넌트 크기×2" 중 작은 쪽. 뚱뚱 먼지의 경계 고리
    /// (둘레≈픽셀수) 안 작은 중앙은 채우되, 가는 루프(머리카락 고리) 안의 넓은 정상 이미지는
    /// 채우지 않는다 — Region/브러시 공통 루프-내부 와이프 방지 구조 가드.
    static func holeCap(_ maxHoleArea: Int, componentCount: Int) -> Int {
        min(maxHoleArea, componentCount * 2)
    }

    struct RawComponent {
        let pixels: [Int]
        let minX: Int; let maxX: Int; let minY: Int; let maxY: Int
    }

    static func rawComponents(of cand: [Bool], width: Int, height: Int) -> [RawComponent] {
        var out: [RawComponent] = []
        forEachComponent(cand, width: width, height: height) { comp, minX, maxX, minY, maxY in
            out.append(RawComponent(pixels: comp, minX: minX, maxX: maxX, minY: minY, maxY: maxY))
        }
        return out
    }

    /// 덩어리(≥ isolationMinStruct px) 먼지 후보 픽셀 맵 — 고립 게이트의 "주변 구조" 판정 기준.
    static func chunkyMap(_ comps: [RawComponent], width: Int, height: Int) -> [Bool] {
        var chunky = [Bool](repeating: false, count: width * height)
        for c in comps where c.pixels.count >= isolationMinStruct {
            for p in c.pixels { chunky[p] = true }
        }
        return chunky
    }

    /// 게이트 통과 컴포넌트 중 그레인 필드(빽빽한 작은 컴포넌트)에 속한 것의 인덱스를 낸다.
    /// 작은(≤ grainFieldSmallMax px) 컴포넌트끼리만 서로 센다 — 큰 결함 옆의 작은 먼지,
    /// 조각난 스크래치의 소수 파편(반경 내 < count 개)은 보존된다.
    static func grainFieldDrops(dust: [RawComponent], scratch: [RawComponent], width: Int,
                                smallMax: Int = grainFieldSmallMax)
        -> (dust: Set<Int>, scratch: Set<Int>) {
        struct Small { let cx: Int; let cy: Int; let isDust: Bool; let index: Int }
        var smalls: [Small] = []
        func centroid(_ c: RawComponent) -> (Int, Int) {
            var sx = 0, sy = 0
            for p in c.pixels { sx += p % width; sy += p / width }
            return (sx / c.pixels.count, sy / c.pixels.count)
        }
        for (i, c) in dust.enumerated() where c.pixels.count <= smallMax {
            let (cx, cy) = centroid(c)
            smalls.append(Small(cx: cx, cy: cy, isDust: true, index: i))
        }
        for (i, c) in scratch.enumerated() where c.pixels.count <= smallMax {
            let (cx, cy) = centroid(c)
            smalls.append(Small(cx: cx, cy: cy, isDust: false, index: i))
        }
        guard smalls.count >= grainFieldCount else { return ([], []) }
        // 그리드 버킷(변 = radius)으로 반경 내 이웃 수를 O(n) 근처로 센다(Chebyshev 거리).
        let r = grainFieldRadius
        var buckets = [Int: [Int]]()
        for (si, s) in smalls.enumerated() {
            buckets[(s.cx / r) * 1_000_003 + (s.cy / r), default: []].append(si)
        }
        var dustDrop = Set<Int>(), scratchDrop = Set<Int>()
        for s in smalls {
            var near = 0
            let bx = s.cx / r, by = s.cy / r
            outer: for nx in (bx - 1)...(bx + 1) {
                for ny in max(0, by - 1)...(by + 1) {
                    for si in buckets[nx * 1_000_003 + ny] ?? [] {
                        let o = smalls[si]
                        if abs(o.cx - s.cx) <= r, abs(o.cy - s.cy) <= r {
                            near += 1   // 자기 포함
                            if near >= grainFieldCount { break outer }
                        }
                    }
                }
            }
            if near >= grainFieldCount {
                if s.isDust { dustDrop.insert(s.index) } else { scratchDrop.insert(s.index) }
            }
        }
        return (dustDrop, scratchDrop)
    }

    /// 구조물 선(보도블럭·벽돌·창틀·펜스·블라인드 등)에 속한 스크래치 컴포넌트 인덱스를 낸다
    /// (전역 자동 전용, 순수 제거). 두 메커니즘의 합집합이다:
    ///   A) 방향 무관 국소 밀도 — dash 텍스처(곡선/방사형/격자 포함)를 잡는다.
    ///   B) 방향 기반 평행/격자 — 성긴 긴 구조선(펜스·창살)을 잡는다.
    /// 고립 스크래치·조각난 단일 스크래치(이웃 소수, 평행 동반 없음)는 두 메커니즘 모두 보존한다.
    static func gridLineDrops(scratch: [RawComponent], width: Int, height: Int) -> Set<Int> {
        guard scratch.count >= gridLineMinField else { return [] }
        struct Line {
            let cx: Int; let cy: Int
            let minX: Int; let maxX: Int; let minY: Int; let maxY: Int
            let angle: Double; let length: Double; let index: Int
        }
        var lines: [Line] = []
        for (i, c) in scratch.enumerated() {
            let m = DefectShape.pcaMetrics(c.pixels, width: width)
            guard m.length >= gridLineMinLength else { continue }
            var sx = 0, sy = 0
            for p in c.pixels { sx += p % width; sy += p / width }
            lines.append(Line(cx: sx / c.pixels.count, cy: sy / c.pixels.count,
                              minX: c.minX, maxX: c.maxX, minY: c.minY, maxY: c.maxY,
                              angle: m.angleDegrees, length: m.length, index: i))
        }
        guard lines.count >= gridLineMinField else { return [] }
        var drop = Set<Int>()

        /// 두 선이 "끊긴 같은 결함의 조각"인가 — 평행하고 같은 축 위(축 이탈 ≤ 허용)면 참.
        /// 이런 조각은 서로를 이웃 선으로 세지 않는다(하나의 스크래치가 스스로를 기각하는 것 방지).
        @inline(__always) func sameLineFragment(_ a: Line, _ b: Line) -> Bool {
            guard orientationDifference(a.angle, b.angle) <= gridLineOrientTol else { return false }
            let rad = a.angle * .pi / 180
            // a 의 주축에 대한 b 중심점의 수직 거리.
            let offset = abs(Double(b.cy - a.cy) * cos(rad) - Double(b.cx - a.cx) * sin(rad))
            return offset <= gridLineCollinearOffset
        }

        /// 구조 텍스처 판정에 표를 던질 수 있는 이웃인가 — 자기 자신이 아니고, 같은 결함의 조각도
        /// 아니고, 길이가 비슷해야 한다. 규칙 구조(벽돌·블라인드·격자)는 길이가 고르지만 스크래치는
        /// 주변 잔선보다 훨씬 길다 — 짧은 잔선이 긴 스크래치를 구조로 몰아세우지 못하게 한다.
        @inline(__always) func votesAsStructureNeighbour(_ subject: Int, _ other: Int) -> Bool {
            guard other != subject else { return true }   // 자신 포함 계약 유지
            guard !sameLineFragment(lines[subject], lines[other]) else { return false }
            let longer = max(lines[subject].length, lines[other].length)
            let shorter = max(1.0, min(lines[subject].length, lines[other].length))
            return longer / shorter <= gridLineComparableLengthRatio
        }

        // A) 국소 밀도: 중심점이 반경 rD(Chebyshev) 안에 있는 다른 선 수. dash 는 짧아 중심점이
        //    위치를 잘 대표하므로 곡선/방사형/격자에서 방향 무관하게 텍스처 밀집을 잡는다.
        //    같은 축 위 조각은 제외한다 — 조각난 스크래치 하나는 텍스처가 아니다.
        let rD = max(gridLineRadiusMin, min(width, height) / gridLineRadiusDivisor)
        var buckets = [Int: [Int]]()
        for (li, l) in lines.enumerated() {
            buckets[(l.cx / rD) * 1_000_003 + (l.cy / rD), default: []].append(li)
        }
        for (i, l) in lines.enumerated() {
            var near = 0
            let bx = l.cx / rD, by = l.cy / rD
            outer: for nx in (bx - 1)...(bx + 1) {
                for ny in (by - 1)...(by + 1) {
                    for li in buckets[nx * 1_000_003 + ny] ?? [] {
                        let o = lines[li]
                        if abs(o.cx - l.cx) <= rD, abs(o.cy - l.cy) <= rD {
                            guard votesAsStructureNeighbour(i, li) else { continue }
                            near += 1
                            if near >= gridLineDenseCount { break outer }
                        }
                    }
                }
            }
            if near >= gridLineDenseCount { drop.insert(l.index) }
        }

        // B) 방향 기반(성긴 긴 구조선). 확장 bbox 중첩으로 이웃 판정 — 긴 두 선은 중심점이 멀어도
        //    실제로 교차/근접하면 확장 bbox 가 겹친다. 평행 규칙 필드 또는 직교 격자면 코어로 보고,
        //    코어에 인접-평행한 가장자리 선까지 2-패스로 확장 배제한다. O(n²)(타일당 수백).
        let rS = max(gridLineRadiusMin, min(width, height) / gridLineStructRadiusDivisor)
        @inline(__always) func nearBox(_ a: Line, _ b: Line) -> Bool {
            a.minX - rS <= b.maxX && b.minX - rS <= a.maxX
                && a.minY - rS <= b.maxY && b.minY - rS <= a.maxY
        }
        var isCore = [Bool](repeating: false, count: lines.count)
        for (i, l) in lines.enumerated() {
            var along = 0, perp = 0
            for (j, o) in lines.enumerated() where nearBox(l, o) {
                let d = orientationDifference(o.angle, l.angle)
                if d <= gridLineOrientTol {
                    guard votesAsStructureNeighbour(i, j) else { continue }
                    along += 1
                } else if abs(d - 90) <= gridLineOrientTol,
                          votesAsStructureNeighbour(i, j) {
                    perp += 1
                }
            }
            isCore[i] = along >= gridLineParallelField
                || (along >= gridLineMinAlong && perp >= gridLineMinPerp)
        }
        for (i, l) in lines.enumerated() where !drop.contains(l.index) {
            if isCore[i] { drop.insert(l.index); continue }
            // 코어에 인접-평행한 가장자리 선까지 확장 배제하되, 코어보다 훨씬 긴 선은 그 구조의
            // 일부가 아니다(구조를 가로지르는 스크래치).
            for (j, o) in lines.enumerated() where isCore[j] && nearBox(l, o)
                && orientationDifference(o.angle, l.angle) <= gridLineOrientTol
                && votesAsStructureNeighbour(i, j) {
                drop.insert(l.index); break
            }
        }
        return drop
    }

    /// 두 선 방향(도)의 최소 차이(0~90). 선은 180° 주기이고 좌우 구분이 없다.
    private static func orientationDifference(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 180)
        return min(d, 180 - d)
    }

    /// bbox 둘레 링(pad)에 다른 덩어리 후보가 isolationMaxRingDensity 이하일 때만 고립로 본다.
    /// 링은 bbox 바깥만 보므로 자기 픽셀은 세지 않는다.
    static func isIsolated(_ c: RawComponent, chunky: [Bool], width: Int, height: Int) -> Bool {
        let boxW = c.maxX - c.minX + 1, boxH = c.maxY - c.minY + 1
        let pad = max(8, min(isolationRingPadMax, 2 * min(boxW, boxH)))
        let x0 = max(0, c.minX - pad), x1 = min(width - 1, c.maxX + pad)
        let y0 = max(0, c.minY - pad), y1 = min(height - 1, c.maxY + pad)
        var total = 0, hit = 0
        for y in y0...y1 {
            let inY = y >= c.minY && y <= c.maxY
            for x in x0...x1 {
                if inY, x >= c.minX, x <= c.maxX { continue }   // bbox(자기) 제외 — 링만 본다
                total += 1
                if chunky[y * width + x] { hit += 1 }
            }
        }
        return total == 0 || Double(hit) / Double(total) <= isolationMaxRingDensity
    }

    // MARK: connected components (8-이웃)

    static func forEachComponent(_ cand: [Bool], width: Int, height: Int,
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
    static func fillInteriorHoles(_ bytes: inout [UInt8], minX: Int, maxX: Int, minY: Int, maxY: Int,
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

    static func paint(_ pixel: Int, width: Int, height: Int, radius r: Int, into bytes: inout [UInt8]) {
        let y = pixel / width, x = pixel - (pixel / width) * width
        for ny in max(0, y - r)...min(height - 1, y + r) {
            for nx in max(0, x - r)...min(width - 1, x + r) {
                let o = (ny * width + nx) * 4
                bytes[o] = 255; bytes[o + 1] = 255; bytes[o + 2] = 255; bytes[o + 3] = 255
            }
        }
    }

    // MARK: 영역 결함 제거 — 라벨 빌드 / 마스크 렌더 (게이트·페인팅은 build 와 동일 로직)

    /// 후보 → 게이트 통과 컴포넌트에 라벨을 부여한다. build 와 같은 면적/aspect/길이 기준을 쓰되
    /// RGBA8 대신 라벨맵+컴포넌트 목록을 낸다(클릭 제외 편집용). 페인팅(dust dilate/hole-fill,
    /// scratch dilate)은 하지 않는다 — 그건 renderMask 가 build 와 동일하게 처리한다.
    /// - scratchStrong: 히스테리시스 코어(full-threshold) 마스크. 주어지면 scratch(=strong∪weak)의
    ///   연결요소 중 strong 픽셀을 하나라도 포함한 것만 채택한다 — weak 만으로 된 컴포넌트(그레인/
    ///   저대비 텍스처)를 버려, 조각/저대비로 끊긴 결함만 grain-safe 하게 잇는다. 예외: weak-only 라도
    ///   "매우 길고 매우 가는" 기하 증거(weakGeo*)가 있으면 채택한다 — 초저대비 장선 스크래치.
    /// - dustStrong: 먼지 히스테리시스 코어. 주어지면 strong 코어 없는 먼지 컴포넌트를 버린다.
}
