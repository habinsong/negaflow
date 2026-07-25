import Foundation

extension DefectComponentMask {
    static func build(width: Int, height: Int,
                      dust: [Bool], scratch: [Bool],
                      dustStrong: [Bool]? = nil,
                      maxDustArea: Int, minScratchLength: Int,
                      minScratchAspect: Double = 2.5,
                      dustMaxAspect: Double = 4.0,
                      minThickDefect: Int = .max, maxThickDefect: Int = 0,
                      dustDilate: Int = 0,
                      scratchResponse: [Float]? = nil,
                      regionArea: Int? = nil) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)

        // 먼지: 면적 상한 이하만(넓은 하이라이트 halo 등 제외). 뚱뚱한 먼지는 경계만 대비가
        // 커서 검출되고 균일한 중앙은 미검출되므로, 닫힌 경계로 둘러싸인 내부 hole을 채워
        // 중앙까지 결함에 포함시킨다(과검출 방지: hole 면적이 컴포넌트 크기에 비례하는 상한 이하일
        // 때만 — 루프(고리) 결함의 넓은 내부를 정상 이미지째 채우는 와이프 방지).
        let dustComps = rawComponents(of: dust, width: width, height: height)
        let chunky = chunkyMap(dustComps, width: width, height: height)
        var acceptedDust: [RawComponent] = []
        for c in dustComps {
            // 히스테리시스: strong 코어가 하나라도 있어야 채택 — 코어 없는 컴포넌트(컨텍스트 게이트에
            // 걸린 구조물/디테일)는 버린다.
            if let strong = dustStrong, !c.pixels.contains(where: { strong[$0] }) { continue }
            let boxW = c.maxX - c.minX + 1, boxH = c.maxY - c.minY + 1
            let aspect = Double(max(boxW, boxH)) / Double(max(1, min(boxW, boxH)))
            // 컴팩트한 blob 또는 두꺼운 선/곡선 결함만 통과(passesDustGate). dustMaxAspect 를 올리면
            // 꼬불꼬불·길쭉한 먼지를, 두께 게이트는 두꺼운 스크래치까지 허용한다 — grain/하늘은 이미
            // 후보 단계(임계)에서 걸러지므로 형태 게이트 완화로 폭발하지 않는다.
            guard passesDustGate(count: c.pixels.count, boxW: boxW, boxH: boxH, aspect: aspect,
                                 maxDustArea: maxDustArea, dustMaxAspect: dustMaxAspect,
                                 minThickDefect: minThickDefect, maxThickDefect: maxThickDefect),
                  isIsolated(c, chunky: chunky, width: width, height: height) else { continue }
            acceptedDust.append(c)
        }

        // 스크래치: 길고 가는 연결요소만.
        var acceptedScratch: [RawComponent] = []
        forEachComponent(scratch, width: width, height: height) { comp, minX, maxX, minY, maxY in
            guard passesScratchGate(comp, width: width, minX: minX, maxX: maxX, minY: minY, maxY: maxY,
                                    minScratchLength: minScratchLength,
                                    minScratchAspect: minScratchAspect) != nil else { return }
            acceptedScratch.append(RawComponent(pixels: comp, minX: minX, maxX: maxX, minY: minY, maxY: maxY))
        }

        // 그레인 필드 필터: 빽빽한 작은 컴포넌트(낱알 그레인)만 버린다.
        let drops = grainFieldDrops(dust: acceptedDust, scratch: acceptedScratch, width: width)
        var dustOrder = acceptedDust.indices.filter { !drops.dust.contains($0) }
        var scratchOrder = acceptedScratch.indices.filter { !drops.scratch.contains($0) }

        // 와이프 퓨즈(브러시 경로 전용) — 채택 우선순위·예산 계산(상수 주석 참조).
        var totalBudget = Int.max
        var scratchBudget = Int.max
        if let area = regionArea {
            totalBudget = max(64, Int(Double(area) * totalBudgetAreaFraction))
            // 먼지: 큰 것(사용자가 노린 결함일 확률이 높은 순) 우선.
            dustOrder.sort { acceptedDust[$0].pixels.count > acceptedDust[$1].pixels.count }
            // 스크래치: 방향 적분 응답 세기 순 — 그레인 줄무늬(임계 언저리)보다 실제 결함이 앞선다.
            if let resp = scratchResponse {
                let means = acceptedScratch.map { c -> Float in
                    var s: Float = 0
                    for p in c.pixels { s += resp[p] }
                    return s / Float(max(1, c.pixels.count))
                }
                scratchOrder.sort { means[$0] > means[$1] }
            } else {
                scratchOrder.sort { acceptedScratch[$0].pixels.count > acceptedScratch[$1].pixels.count }
            }
            if let first = scratchOrder.first {
                let c = acceptedScratch[first]
                let firstPaint = min(c.pixels.count * 9,
                                     (c.maxX - c.minX + 3) * (c.maxY - c.minY + 3))
                scratchBudget = max(Int(Double(firstPaint) * scratchBudgetLargestMultiple),
                                    Int(Double(area) * scratchBudgetAreaFraction))
            }
        }

        // 페인트 상한 추정: 팽창 픽셀곱과 팽창 bbox 중 작은 쪽 — 솔리드 blob 은 bbox 가,
        // 성긴 곡선은 픽셀곱이 실제에 가깝다(둘 다 상한이라 예산을 넘겨 채택할 일은 없다).
        func paintEstimate(_ c: RawComponent, dilate r: Int) -> Int {
            let byPixels = c.pixels.count * (2 * r + 1) * (2 * r + 1)
            let byBox = (c.maxX - c.minX + 1 + 2 * r) * (c.maxY - c.minY + 1 + 2 * r)
            return min(byPixels, byBox)
        }

        // 각 카테고리 최강(rank 0)은 예산 무관 채택 + 예산 미소비 — 사용자가 결함을 꽉 맞게 칠해
        // 결함이 칠 면적의 대부분인 정당한 경우(밀착 브러시)에 결함의 나머지 조각이 잘리지 않게
        // 한다. 예산은 꼬리(rank ≥ 1)의 총량만 제한한다 — 줄무늬/blob 폭주는 꼬리에서 생긴다.
        var totalPainted = 0
        for (rank, i) in dustOrder.enumerated() {
            let c = acceptedDust[i]
            let estimate = paintEstimate(c, dilate: dustDilate)
            if rank > 0 {
                if totalPainted + estimate > totalBudget { continue }
                totalPainted += estimate
            }
            // brush 영역에선 반경 dustDilate(>0)로 팽창 — 흰 먼지의 부드러운 경계(halo)까지 마스크로
            // 덮어, 잔존 흰색과 복원 시 그 흰색을 성한 픽셀로 참조해 번지는 것을 막는다. 전역(0)은
            // 넓은 하이라이트 오탐을 막기 위해 팽창하지 않는다.
            for p in c.pixels { paint(p, width: width, height: height, radius: dustDilate, into: &bytes) }
            fillInteriorHoles(&bytes, minX: c.minX, maxX: c.maxX, minY: c.minY, maxY: c.maxY,
                              width: width, height: height,
                              maxHoleArea: holeCap(maxDustArea, componentCount: c.pixels.count))
        }
        var scratchPainted = 0
        for (rank, i) in scratchOrder.enumerated() {
            let c = acceptedScratch[i]
            let estimate = paintEstimate(c, dilate: 1)
            if rank > 0 {
                if scratchPainted + estimate > scratchBudget
                    || totalPainted + estimate > totalBudget { continue }
                scratchPainted += estimate
                totalPainted += estimate
            }
            // 1px 팽창으로 선 두께 보강.
            for p in c.pixels { paint(p, width: width, height: height, radius: 1, into: &bytes) }
        }
        return bytes
    }

    /// 먼지/두꺼운 결함 통과 게이트.
    ///  (1) 컴팩트 blob: 면적 ≤ maxDustArea 이고 aspect ≤ dustMaxAspect.
    ///  (2) 두꺼운 선·곡선 결함: 평균 두께(픽셀수/긴변)가 [minThick, maxThick]. 두꺼운 스크래치/꼬불꼬불
    ///      먼지를 aspect·면적 무관하게 살리되, 가는 정상선(두께 부족)·넓은 정상면(두께 과다)은 배제한다.
    /// 기본값(minThick=.max)에선 (2)가 비활성 — brush/전역 경로는 기존 컴팩트 게이트만 쓴다.
}
