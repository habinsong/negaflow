import Foundation

// 이미지 구조선(난간·창틀·보도블럭 줄눈 등)으로 검출된 스크래치를 **연장 증거**로 기각한다
// (전역 자동 전용, 순수 제거).
//
// 원리: 필름 스크래치는 끝나는 자리에서 진짜로 끝나지만, 이미지 구조선은 검출이 임계 미달로
// 끊긴 자리에도 원본에 선이 계속 이어진다 — 검출된 조각은 그 선의 일부 구간일 뿐이다. 그래서
// 컴포넌트 주축을 양 끝 바깥으로 연장해, 방향 적분 응답(검출기가 이미 만든 맵)이 본체와 비슷한
// 세기로 계속되는지 본다. 한쪽이 거의 끊김 없이 이어지거나 양쪽이 함께 이어지면 구조선으로 본다.
//
// 밀도·평행·주기성에 의존하지 않으므로 고립된 구조선 하나(난간 가로바 한 줄)도 잡는다 — 개수
// 기반인 gridLineDrops 의 사각지대다. 판정 기준은 "본체 대비 비율"이라 장면 밝기·대비에 일반화되고,
// 검출 임계·SNR 게이트는 전혀 건드리지 않는다(컴포넌트를 제거만 하므로 검출을 악화시킬 수 없다).
enum DefectStructureLineFilter {
    /// 연장을 시작하는 간격(px). 방향 적분 반길이(DefectScratchDetector.longHalf=12)보다 커야
    /// 컴포넌트 자신의 적분 꼬리를 "이어짐"으로 오독하지 않는다.
    static let continuationGap = 16
    /// 연장해서 보는 최소/최대 길이(px). 주축 길이에 비례하되 이 범위로 자른다 — 너무 짧으면
    /// 증거가 약하고, 너무 길면 무관한 다른 구조를 만난다.
    static let continuationMinSpan = 24
    static let continuationMaxSpan = 80
    /// 판정 대상 최소 주축 길이. 이보다 짧으면 PCA 주축이 불안정해 연장선이 엉뚱한 곳을 향한다.
    static let continuationMinLength = 12.0
    /// 짧은(minSpan 미만) 조각을 판정 대상에 넣는 최소 신장도. 가늘고 곧으면 짧아도 방향이
    /// 명확하다 — 구조선이 임계 근처에서 잘게 끊긴 조각이 판정 밖으로 새는 것을 막는다.
    static let continuationShortMinAspect = 4.0
    /// 연장 경로 샘플 간격(px)과 주축 수직 탐색 반경(px). 구조선이 완만히 휘어도 따라간다.
    static let continuationStep = 2
    static let continuationPerpTolerance = 2
    /// 샘플이 "선이 있다"로 인정되는 본체 응답 대비 비율.
    static let continuationLevelRatio: Float = 0.5
    /// 양쪽 모두가 "이어짐"으로 인정되는 최소 샘플 비율(약한 증거는 양쪽이 모여야 한다).
    static let continuationCoverage = 0.6
    /// 한쪽만으로 판정을 끝내는 비율. 연장 구간이 **거의 끊김 없이** 이어지면 그 자체로 이미지
    /// 구조선의 증거다 — 구조선의 끝 조각(줄눈이 프레임 밖으로 나가거나 다른 구조와 만나 끝나는
    /// 자리)은 한쪽만 이어지므로, 양쪽을 모두 요구하면 정작 가장 흔한 오검출이 전부 살아남는다.
    static let strongContinuationCoverage = 0.8
    /// 본체 응답이 이보다 약하면 판정을 보류한다(보존) — 비율 판정의 분모를 믿을 수 없다.
    static let continuationMinBodyResponse: Float = 1e-4


    /// 양 끝 연장선에 같은 선이 계속되는 스크래치 컴포넌트의 인덱스를 낸다.
    /// - responseAt: (x, y) → 방향 적분 응답(임계 전 연속값). 좌표가 판정 범위 밖이면 nil.
    ///   타일 로컬 배열과 프레임 전역 저해상도 맵(DefectScratchResponseMap)을 같은 판정으로 쓴다.
    static func continuationDrops(scratch: [DefectComponentMask.RawComponent],
                                  width: Int,
                                  responseAt: (Int, Int) -> Float?) -> Set<Int> {
        guard width > 0 else { return [] }
        var drop = Set<Int>()
        for (index, component) in scratch.enumerated()
        where isStructureLine(component, width: width, responseAt: responseAt) {
            drop.insert(index)
        }
        return drop
    }

    /// 타일 로컬 응답 배열용 편의 진입점.
    static func continuationDrops(scratch: [DefectComponentMask.RawComponent],
                                  response: [Float],
                                  width: Int, height: Int) -> Set<Int> {
        guard width > 0, height > 0, response.count == width * height else { return [] }
        return continuationDrops(scratch: scratch, width: width) { x, y in
            guard x >= 0, x < width, y >= 0, y < height else { return nil }
            return response[y * width + x]
        }
    }

    /// 컴포넌트가 "원본 이미지에서 계속 이어지는 선"의 일부인가.
    private static func isStructureLine(_ component: DefectComponentMask.RawComponent,
                                        width: Int, responseAt: (Int, Int) -> Float?) -> Bool {
        let metrics = DefectShape.pcaMetrics(component.pixels, width: width)
        // 주축 방향을 믿을 수 있는 조각만 판정한다 — 방향이 흔들리면 연장선이 엉뚱한 곳을 향한다.
        guard metrics.length >= continuationMinLength else { return false }
        guard metrics.length >= Double(continuationMinSpan)
                || metrics.aspect >= continuationShortMinAspect else { return false }
        let body = medianResponse(component.pixels, width: width, responseAt: responseAt)
        guard body >= continuationMinBodyResponse else { return false }

        // 주축 단위 벡터. 라벨맵은 y-down 이고 pcaMetrics 의 각도도 같은 좌표계다.
        let radians = metrics.angleDegrees * .pi / 180
        let ux = cos(radians), uy = sin(radians)
        guard let ends = axisEndpoints(component.pixels, width: width, ux: ux, uy: uy) else { return false }

        let span = min(continuationMaxSpan, max(continuationMinSpan, Int(metrics.length)))
        let level = body * continuationLevelRatio
        // 연장 구간이 이미지 밖으로 나가면 해당 방향은 판정 불가(음수)다 — 증거로 세지 않는다.
        // 프레임을 관통하는 진짜 스크래치가 경계에서 지워지지 않게 하는 안전 방향이다.
        let forward = continuationCoverageOf(
            fromX: ends.maxPoint.x, fromY: ends.maxPoint.y, dx: ux, dy: uy,
            span: span, level: level, responseAt: responseAt)
        let backward = continuationCoverageOf(
            fromX: ends.minPoint.x, fromY: ends.minPoint.y, dx: -ux, dy: -uy,
            span: span, level: level, responseAt: responseAt)
        // 한쪽이 거의 끊김 없이 이어지면 그것만으로 구조선. 그보다 약한 증거는 양쪽이 모여야 한다.
        if forward >= strongContinuationCoverage || backward >= strongContinuationCoverage { return true }
        return forward >= continuationCoverage && backward >= continuationCoverage
    }

    /// 주축 방향 투영이 최소/최대인 픽셀 = 컴포넌트의 양 끝점.
    private static func axisEndpoints(_ pixels: [Int], width: Int, ux: Double, uy: Double)
        -> (minPoint: (x: Double, y: Double), maxPoint: (x: Double, y: Double))? {
        guard !pixels.isEmpty else { return nil }
        var minT = Double.greatestFiniteMagnitude, maxT = -Double.greatestFiniteMagnitude
        var minPoint = (x: 0.0, y: 0.0), maxPoint = (x: 0.0, y: 0.0)
        for pixel in pixels {
            let y = pixel / width, x = pixel - y * width
            let t = Double(x) * ux + Double(y) * uy
            if t < minT { minT = t; minPoint = (Double(x), Double(y)) }
            if t > maxT { maxT = t; maxPoint = (Double(x), Double(y)) }
        }
        return (minPoint, maxPoint)
    }

    /// 끝점에서 (dx,dy) 방향으로 연장하며 응답이 level 이상으로 이어지는 샘플 비율(0~1).
    /// 샘플 경로가 이미지(타일) 밖으로 나가면 판정 불가를 뜻하는 음수를 돌려준다.
    private static func continuationCoverageOf(fromX: Double, fromY: Double, dx: Double, dy: Double,
                                               span: Int, level: Float,
                                               responseAt: (Int, Int) -> Float?) -> Double {
        let px = -dy, py = dx
        var samples = 0, hits = 0
        var t = continuationGap
        while t <= continuationGap + span {
            let cx = fromX + dx * Double(t), cy = fromY + dy * Double(t)
            var strongest: Float = 0
            var inside = false
            for k in -continuationPerpTolerance...continuationPerpTolerance {
                let sx = Int((cx + px * Double(k)).rounded())
                let sy = Int((cy + py * Double(k)).rounded())
                guard let value = responseAt(sx, sy) else { continue }
                inside = true
                strongest = max(strongest, value)
            }
            guard inside else { return -1 }
            samples += 1
            if strongest >= level { hits += 1 }
            t += continuationStep
        }
        return samples > 0 ? Double(hits) / Double(samples) : -1
    }

    /// 컴포넌트 본체의 대표 응답(중앙값) — 비율 판정의 분모. 평균은 밝은 교차점 하나에 끌려간다.
    private static func medianResponse(_ pixels: [Int], width: Int,
                                       responseAt: (Int, Int) -> Float?) -> Float {
        var values = pixels.compactMap { pixel -> Float? in
            let y = pixel / width
            return responseAt(pixel - y * width, y)
        }
        guard !values.isEmpty else { return 0 }
        values.sort()
        return values[values.count / 2]
    }
}
