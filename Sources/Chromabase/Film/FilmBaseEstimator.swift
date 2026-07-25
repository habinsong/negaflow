import Foundation
import CoreImage

// MARK: - FilmBaseEstimator (plan §8.5)
//
// 네거티브 반전의 핵심. 필름 베이스(오렌지 마스크 기저색)를 추정한다.
//
// 자동 방식 (plan §8.5):
//   1. 이미지 가장자리(프레임 밖 필름 베이스 영역)에서 후보 픽셀 수집
//   2. 너무 어둡거나 너무 밝은 영역 제외
//   3. RGB 채널 중앙값 기반 추정 + 이상치 제거
public enum FilmBaseEstimator {
    /// 가장자리 영역에서 필름 베이스를 추정한다.
    /// - Parameter neutralBase: B&W 네거티브처럼 오렌지 마스크가 없는 중립(회색) 베이스를 찾는다.
    ///   기존에는 R−B≥0.06 조건이 회색 베이스를 전부 탈락시켜 B&W가 항상 오렌지 폴백으로
    ///   떨어졌다(반전 캐스트의 원인) — 필름 타입에 맞는 후보 판정을 쓴다.
    /// - Parameter confidentOnly: true 면 두 샘플러(가장자리/분산)의 확신 있는 실측만 반환하고,
    ///   마지막 폴백(스트립 평균 — 베이스 후보 판정 없이 밝기만 보는 약한 추정)은 건너뛴다.
    ///   preset 모드의 "실측 우선"은 약한 추정이 프리셋 물성을 덮어쓰면 안 되므로 이것을 쓴다.
    public static func estimate(from image: CIImage, edgeFraction: Double = 0.06,
                                neutralBase: Bool = false,
                                confidentOnly: Bool = false) -> FilmBase? {
        let extent = image.extent
        guard extent.width > 4, extent.height > 4 else { return nil }

        let sampleGrid = FilmBaseSampleGrid(image: image)

        // 1차: 연결 성분 기반 검출(2026-07-14 v3) — 공간 구조 불변량이라 percentile/고정
        // luma 창 방식과 달리 광원 불균일·경계 혼합 셀에 강하다.
        if let componentSample = sampleGrid.flatMap({
            connectedBaseComponent(from: $0, neutralBase: neutralBase)
        }) {
            return componentSample.filmBase(source: .auto)
        }

        // 2차: 기존 샘플러(작은 이미지/후보 희소 등 성분 검출이 불가능한 경우).
        let exclusion = sampleGrid.flatMap {
            nonFilmExclusion(for: $0, neutralBase: neutralBase)
        }
        let edgeSample = sampleGrid.flatMap {
            sampleBrightOrangeBase(from: $0, edgeFraction: edgeFraction,
                                   neutralBase: neutralBase, excluding: exclusion)
        }
        let distributedSample = sampleGrid.flatMap {
            sampleDistributedOrangeBase(from: $0, neutralBase: neutralBase, excluding: exclusion)
        }
        if let edgeSample, let distributedSample {
            let edgeLuma = (edgeSample.rgb.x + edgeSample.rgb.y + edgeSample.rgb.z) / 3
            let distributedLuma = (distributedSample.rgb.x + distributedSample.rgb.y + distributedSample.rgb.z) / 3
            if edgeLuma >= distributedLuma * 0.85 {
                return edgeSample.filmBase(source: .border)
            }
            return distributedSample.filmBase(source: .auto)
        }
        if let edgeSample {
            return edgeSample.filmBase(source: .border)
        }
        if let distributedSample {
            return distributedSample.filmBase(source: .auto)
        }
        if confidentOnly { return nil }

        // 그리드 보더 폴백 — 기존 스트립 평균과 같은 의미론이지만 비필름 마스크를 존중한다.
        // 과거의 CIAreaAverage 스트립 평균은 백라이트/퍼포레이션 픽셀을 그대로 섞어,
        // 가져온 스캔(백라이트 위 필름)에서 베이스가 광원 쪽으로 새는 원인이었다.
        if let grid = sampleGrid {
            return borderFallback(from: grid, edgeFraction: edgeFraction, excluding: exclusion)?
                .filmBase(source: .border)
        }

        // 이하는 그리드 생성 실패(극소 이미지) 시에만 도달하는 기존 폴백이다.
        // 가장자리 스트립 영역 정의 (위/아래/좌/우 테두리).
        let ex = edgeFraction
        let top    = image.cropped(to: CGRect(x: extent.minX, y: extent.maxY - extent.height*ex,
                                              width: extent.width, height: extent.height*ex))
        let bottom = image.cropped(to: CGRect(x: extent.minX, y: extent.minY,
                                              width: extent.width, height: extent.height*ex))
        let left   = image.cropped(to: CGRect(x: extent.minX, y: extent.minY,
                                              width: extent.width*ex, height: extent.height))
        let right  = image.cropped(to: CGRect(x: extent.maxX - extent.width*ex, y: extent.minY,
                                              width: extent.width*ex, height: extent.height))

        // 각 채널의 중앙값을 구하기 위해 픽셀을 샘플링한다.
        // Core Image의 CIAreaAverage로 영역 평균을 구한 뒤, 여러 스트립의 중앙값을 취한다.
        let samples = [top, bottom, left, right].compactMap { region -> SIMD3<Double>? in
            averageRGB(of: region)
        }
        guard !samples.isEmpty else { return nil }

        // 이상치(극단적으로 어둡거나 밝은 스트립) 제거.
        let filtered = samples.filter { s in
            let lum = (s.x + s.y + s.z) / 3
            return lum > 0.25 && lum < 0.97   // 필름 베이스는 보통 이 범위
        }
        guard !filtered.isEmpty else { return nil }
        let use = filtered

        // 채널별 중앙값.
        let fallbackSamples = use.enumerated().map {
            FilmBaseSample(x: $0.offset, y: 0, color: $0.element)
        }
        return FilmBaseMeasurementBuilder.build(
            method: .stripFallback,
            sampledPixelCount: samples.count,
            candidateCount: filtered.count,
            selected: fallbackSamples,
            gridWidth: samples.count,
            gridHeight: 1
        )?.filmBase(source: .border)
    }

    // MARK: 연결 성분 기반 베이스 검출 (2026-07-14 v3)
    //
    // 실측 실패(멀티 스트립 카메라 스캔 — 클리핑 안 된 백라이트 띠 + 퍼포레이션 + 광원
    // 불균일)에서 얻은 교훈: percentile/고정 luma 창 기반 선택은 (1) 경계 혼합 셀,
    // (2) 비네팅으로 퍼진 베이스 luma 에 취약하다. 더 견고한 원리는 **공간 구조**를 쓰는
    // 것이다(필름 경계·보더/스프로킷을 검출해 제외하거나 사용자가 영역을 지정).
    //
    // 물리 불변량 두 가지만 쓴다:
    //  A. 필름 위에는 베이스보다 밝은 것이 없다(염료는 흡수만) — 반경 2셀 안에 자기보다
    //     1.15× 밝은 셀이 있는 후보는 필름↔광원 경계의 혼합 셀이므로 제외한다. 필름 내부의
    //     조도 변화(비네팅)는 인접 2셀에서 15%를 넘지 않는다.
    //  B. 베이스는 대면적의 **연결된** 네트워크(프레임 사이 간격·가장자리·퍼포레이션 여백)이고,
    //     필름의 어떤 연결 영역보다 밝다 — 후보 연결 성분 중 p75 luma 가 가장 높은 성분이
    //     베이스다(장면 성분은 채널별로 항상 베이스보다 어둡다). 고정 luma 창이 없어 비네팅으로
    //     베이스 밝기가 퍼져도 하나의 성분으로 잡힌다.
    static let brighterNeighborRatio = 1.15
    static let neighborRadius = 2

    static func connectedBaseComponent(
        from grid: FilmBaseSampleGrid,
        neutralBase: Bool
    ) -> FilmBaseMeasurement? {
        let width = grid.width, height = grid.height
        let count = width * height
        guard count > 0, grid.samples.count == count else { return nil }
        var luma = [Double](repeating: 0, count: count)
        for sample in grid.samples {
            luma[sample.y * width + sample.x] = sample.luma
        }

        // 절대 비필름(준클리핑 광원) + 팽창.
        var hardBright = [Bool](repeating: false, count: count)
        var hasHardBright = false
        for i in 0..<count where luma[i] >= nonFilmLuma {
            hardBright[i] = true
            hasHardBright = true
        }
        let hardExcluded = hasHardBright ? dilate(hardBright, grid: grid) : hardBright

        // 후보 판정 + 불변량 A(경계 혼합 셀 제외).
        var eligible = [Bool](repeating: false, count: count)
        for sample in grid.samples {
            let i = sample.y * width + sample.x
            guard !hardExcluded[i],
                  isFilmBaseCandidate(r: sample.color.x, g: sample.color.y, b: sample.color.z,
                                      neutralBase: neutralBase) else { continue }
            eligible[i] = true
        }
        let radius = neighborRadius
        var interior = eligible
        for y in 0..<height {
            for x in 0..<width where eligible[y * width + x] {
                let ceiling = luma[y * width + x] * brighterNeighborRatio
                var isBoundary = false
                for ny in max(0, y - radius)...min(height - 1, y + radius) {
                    for nx in max(0, x - radius)...min(width - 1, x + radius)
                    where luma[ny * width + nx] > ceiling {
                        isBoundary = true
                        break
                    }
                    if isBoundary { break }
                }
                if isBoundary { interior[y * width + x] = false }
            }
        }

        // 불변량 B: 4-이웃 연결 성분 중 p75 luma 최대 성분 = 베이스.
        let coherentCount = max(24, Int(Double(count) * 0.004))
        var componentLabel = [Int](repeating: -1, count: count)
        var components: [(cells: [Int], p75: Double)] = []
        var nextLabel = 0
        var queue: [Int] = []
        for start in 0..<count where interior[start] && componentLabel[start] < 0 {
            var cells: [Int] = []
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            componentLabel[start] = nextLabel
            while let cell = queue.popLast() {
                cells.append(cell)
                let cx = cell % width, cy = cell / width
                for (nx, ny) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)] {
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let ni = ny * width + nx
                    if interior[ni] && componentLabel[ni] < 0 {
                        componentLabel[ni] = nextLabel
                        queue.append(ni)
                    }
                }
            }
            nextLabel += 1
            guard cells.count >= coherentCount else { continue }
            components.append((cells, FilmBaseStatistics.percentile(cells.map { luma[$0] }, 0.75)))
        }
        guard !components.isEmpty else { return nil }
        components.sort { $0.p75 > $1.p75 }

        func medianRB(_ cells: [Int]) -> Double {
            var values: [Double] = []
            values.reserveCapacity(cells.count)
            for cell in cells {
                let sample = grid.samples[cell]
                values.append(sample.color.x - sample.color.z)
            }
            values.sort()
            return values.isEmpty ? 0 : values[values.count / 2]
        }

        // 웜 백라이트 강등(컬러 전용): 최상위 성분이 밝고(≥0.6), 뚜렷이 아래(0.12–0.87×)에
        // 다음 성분이 있으며, 그 성분보다 뚜렷이 덜 오렌지(rb < 0.75×)면 광원이다 —
        // 베이스 = 백라이트 × 마스크 염료라 항상 백라이트보다 오렌지다. 스트립별로 분리된
        // 베이스 형제 성분(p75 유사)은 강등 후보에서 건너뛴다.
        var bestIndex = 0
        if !neutralBase, components[0].p75 >= demoteMinLuma,
           let secondIndex = components.firstIndex(where: {
               $0.p75 < components[0].p75 * demoteRatioRange.upperBound
           }),
           demoteRatioRange.contains(components[secondIndex].p75 / components[0].p75),
           medianRB(components[0].cells) < medianRB(components[secondIndex].cells) * demoteRBRatio {
            bestIndex = secondIndex
        }

        // 선택 성분 + 형제 성분(p75 ≥ 0.90×) 병합 — 멀티 스트립에서 스트립마다 분리된
        // 베이스 네트워크를 함께 쓴다(공간 커버리지·표본 수 ↑).
        let bestScore = components[bestIndex].p75
        var bestCells = components[bestIndex].cells
        for (index, component) in components.enumerated()
        where index != bestIndex && component.p75 >= bestScore * 0.90 && component.p75 <= bestScore / 0.90 {
            bestCells.append(contentsOf: component.cells)
        }

        // 성분 셀 중 luma 상위 절반(광원 불균일에서 밝은 쪽 = Dmin 에 가장 가까운 실측)의
        // 채널 중앙값. 살짝 밝은 쪽 편향은 반전에서 베이스 영역이 확실히 블랙으로 앉게 한다.
        var samplesByIndex: [Int: FilmBaseSample] = [:]
        samplesByIndex.reserveCapacity(grid.samples.count)
        for sample in grid.samples {
            samplesByIndex[sample.y * width + sample.x] = sample
        }
        let members = bestCells.compactMap { samplesByIndex[$0] }
            .sorted { $0.luma > $1.luma }
        let selected = Array(members.prefix(max(members.count / 2, min(members.count, 24))))
        return FilmBaseMeasurementBuilder.build(
            method: .connectedComponent,
            sampledPixelCount: grid.samples.count,
            candidateCount: members.count,
            selected: selected,
            gridWidth: width,
            gridHeight: height
        )
    }

    /// 비필름 노출광(백라이트/퍼포레이션/무필름 여백) 제외 마스크.
    ///
    /// 물리 근거: 네거티브에서 미노광 베이스는 필름의 **최대 투과율**이다(염료는 흡수만 하므로
    /// 어떤 필름 픽셀도 베이스보다 밝을 수 없다). 즉 베이스보다 유의미하게 밝은 것은 전부
    /// 비필름 노출광이다. 백라이트가 클리핑 근처라는 보장은 없으므로(실사용 스캔에서
    /// linear 0.8x 대역 확인), 고정 임계값이 아니라 **가장 밝은 응집 후보 모드 L\***(대면적
    /// 베이스가 만드는 밀집 luma 대역)을 앵커로 그보다 1.12× 이상 밝은 셀 + 절대 상한
    /// (0.88, 준클리핑)을 비필름으로 본다. 다운샘플 그리드가 퍼포레이션/필름 경계에서 만드는
    /// **혼합 셀**(베이스보다 밝고 후보 판정을 통과하는 얇은 스미어)은 응집 모드가 아니라서
    /// L\* 로 뽑히지 않고, 상대 컷과 Chebyshev 반경 2 팽창이 제거한다.
    ///
    /// 어둡게 노출된 **웜** 백라이트가 컬러 후보 판정(R−B ≥ 0.06)까지 통과하는 경우는 L\*
    /// 자체가 백라이트로 잡힐 수 있다 — 이때는 **강등 규칙**(컬러 전용)으로 판별한다:
    /// 최상위 모드가 (a) luma ≥ 0.6(광원 사전확률), (b) 아래에 0.12–0.87× 떨어진 두 번째
    /// 응집 모드가 있고(오렌지 마스크 luma 밀도 ≈ 0.5–0.9D), (c) 두 모드 사이 luma 대역이
    /// (혼합 헤일로 제외) 사실상 비어 있으며 — 필름에는 베이스보다 밝은 내용이 없으므로 진짜
    /// 베이스 위에는 빈 갭이 생길 수 없다 —, (d) 최상위 모드가 두 번째 모드보다 뚜렷이 덜
    /// 오렌지(rb < 0.75×; 베이스 = 백라이트 × 마스크 염료라 항상 백라이트보다 오렌지)일 때만
    /// 강등한다. B&W 는 중립 베이스와 중립 백라이트가 이미지 내 통계로 구분 불가능하고
    /// (밝은 베이스 + 어두운 장면 크롭과 동형), 오판 시 베이스를 버리므로 강등을 하지 않는다
    /// — B&W 의 어두운 백라이트는 준클리핑 절대 컷과 수동 스포이드가 담당한다.
    ///
    /// 마스크가 후보를 사실상 전멸시키는 경우에는 nil 을 돌려 마스크 없이 동작한다
    /// (백라이트 없는 필름 스캐너 크롭 무회귀).
    static let nonFilmLuma = 0.88
    static let nonFilmRelativeCut = 1.12
    static let nonFilmDilationRadius = 2
    static let minimumMaskedCandidates = 24
    /// 응집 모드 판정: luma ±0.03 창 안의 후보 수가 max(24, 샘플의 0.4%) 이상.
    static let modeWindow = 0.03
    /// 강등 규칙 파라미터(컬러 전용).
    static let demoteMinLuma = 0.60
    static let demoteRatioRange = 0.12...0.87
    static let demoteGapMaxFraction = 0.002
    static let demoteRBRatio = 0.75

    static func nonFilmExclusion(for grid: FilmBaseSampleGrid,
                                 neutralBase: Bool) -> [Bool]? {
        let candidates = grid.samples.filter {
            isFilmBaseCandidate(r: $0.color.x, g: $0.color.y, b: $0.color.z,
                                neutralBase: neutralBase)
        }
        let baseMode = brightestCoherentMode(
            candidates: candidates,
            totalSamples: grid.samples.count,
            grid: grid,
            neutralBase: neutralBase
        )
        let relativeCut = baseMode.map { $0 * nonFilmRelativeCut }
        let cut = min(nonFilmLuma, relativeCut ?? nonFilmLuma)

        let count = grid.width * grid.height
        var bright = [Bool](repeating: false, count: count)
        var hasBright = false
        for sample in grid.samples where sample.luma >= cut {
            bright[sample.y * grid.width + sample.x] = true
            hasBright = true
        }
        guard hasBright else { return nil }
        let excluded = dilate(bright, grid: grid)
        let remaining = grid.samples.reduce(into: 0) { total, sample in
            if !excluded[sample.y * grid.width + sample.x],
               isFilmBaseCandidate(r: sample.color.x, g: sample.color.y, b: sample.color.z,
                                   neutralBase: neutralBase) {
                total += 1
            }
        }
        return remaining >= minimumMaskedCandidates ? excluded : nil
    }

    private static func dilate(_ bright: [Bool], grid: FilmBaseSampleGrid) -> [Bool] {
        var excluded = bright
        let radius = nonFilmDilationRadius
        for y in 0..<grid.height {
            for x in 0..<grid.width where bright[y * grid.width + x] {
                for ny in max(0, y - radius)...min(grid.height - 1, y + radius) {
                    for nx in max(0, x - radius)...min(grid.width - 1, x + radius) {
                        excluded[ny * grid.width + nx] = true
                    }
                }
            }
        }
        return excluded
    }

    /// 가장 밝은 응집 후보 모드(베이스 luma 앵커). 필요 시 강등 규칙을 1회 적용한다.
    static func brightestCoherentMode(
        candidates: [FilmBaseSample],
        totalSamples: Int,
        grid: FilmBaseSampleGrid,
        neutralBase: Bool
    ) -> Double? {
        guard !candidates.isEmpty else { return nil }
        let coherentCount = max(24, Int(Double(totalSamples) * 0.004))
        let sorted = candidates.sorted { $0.luma > $1.luma }
        let lumas = sorted.map(\.luma)

        // 내림차순 luma 에서 각 후보를 중심으로 ±modeWindow 창의 후보 수를 two-pointer 로
        // 세어(중심이 감소하면 두 경계도 단조 감소 — 상환 O(n)), 처음으로 응집 임계를 넘는
        // 가장 밝은 중심을 돌려준다.
        func modeCenter(startingBelow upper: Double) -> Double? {
            var lo = 0   // luma > center + window 인 구간의 끝(첫 창 안 인덱스)
            var hi = 0   // luma ≥ center − window 인 구간의 끝(창 밖 첫 인덱스)
            for k in 0..<lumas.count where lumas[k] < upper {
                let center = lumas[k]
                while lo < lumas.count && lumas[lo] > center + modeWindow { lo += 1 }
                if hi < lo { hi = lo }
                while hi < lumas.count && lumas[hi] >= center - modeWindow { hi += 1 }
                if hi - lo >= coherentCount { return center }
            }
            return nil
        }

        guard let top = modeCenter(startingBelow: .infinity) else { return nil }

        // 강등 규칙(컬러 전용) — 최상위 모드가 어둡게 노출된 웜 백라이트일 때만 발동한다.
        guard !neutralBase,
              top >= demoteMinLuma,
              let second = modeCenter(startingBelow: top * 0.87),
              demoteRatioRange.contains(second / top) else { return top }
        // 갭 검사: 두 모드 사이 대역이 (최상위 모드 셀의 혼합 헤일로 제외) 비어 있어야 한다.
        let gapLow = second + modeWindow * 1.5
        let gapHigh = top - modeWindow * 1.5
        guard gapHigh > gapLow else { return top }
        var topCells = [Bool](repeating: false, count: grid.width * grid.height)
        for sample in grid.samples where sample.luma >= gapHigh {
            topCells[sample.y * grid.width + sample.x] = true
        }
        let halo = dilate(topCells, grid: grid)
        let gapCount = grid.samples.reduce(into: 0) { total, sample in
            if sample.luma > gapLow, sample.luma < gapHigh,
               !halo[sample.y * grid.width + sample.x] {
                total += 1
            }
        }
        guard Double(gapCount) <= Double(totalSamples) * demoteGapMaxFraction else { return top }
        // 백라이트는 베이스보다 뚜렷이 덜 오렌지다(베이스 = 백라이트 × 마스크 염료).
        func medianRB(around center: Double) -> Double {
            let members = sorted.filter { abs($0.luma - center) <= modeWindow }
                .map { $0.color.x - $0.color.z }
                .sorted()
            guard !members.isEmpty else { return 0 }
            return members[members.count / 2]
        }
        guard medianRB(around: top) < medianRB(around: second) * demoteRBRatio else {
            return top
        }
        return second
    }

    private static func isExcluded(_ sample: FilmBaseSample,
                                   in grid: FilmBaseSampleGrid,
                                   excluded: [Bool]?) -> Bool {
        excluded?[sample.y * grid.width + sample.x] ?? false
    }

    static func sampleBrightOrangeBase(
        from grid: FilmBaseSampleGrid,
        edgeFraction: Double,
        neutralBase: Bool = false,
        excluding excluded: [Bool]? = nil
    ) -> FilmBaseMeasurement? {
        let edgeX = max(1, Int(Double(grid.width) * edgeFraction))
        let edgeY = max(1, Int(Double(grid.height) * edgeFraction))
        let all = grid.samples.filter {
            !isExcluded($0, in: grid, excluded: excluded) && isFilmBaseCandidate(
                r: $0.color.x,
                g: $0.color.y,
                b: $0.color.z,
                neutralBase: neutralBase
            )
        }
        let border = all.filter {
            $0.x < edgeX || $0.x >= grid.width - edgeX
                || $0.y < edgeY || $0.y >= grid.height - edgeY
        }

        let candidates = border.count >= 16 ? border : all
        guard candidates.count >= 8 else { return nil }
        let lumaCut = FilmBaseStatistics.percentile(candidates.map(\.luma), 0.95)
        let bright = candidates.filter { $0.luma >= lumaCut }
        guard bright.count >= 4 else { return nil }
        var rowCounts = [Int](repeating: 0, count: grid.height)
        var columnCounts = [Int](repeating: 0, count: grid.width)
        for sample in bright {
            rowCounts[sample.y] += 1
            columnCounts[sample.x] += 1
        }
        let minimumHorizontalCoverage = Int(Double(grid.width) * 0.65)
        let minimumVerticalCoverage = Int(Double(grid.height) * 0.65)
        let hasContinuousEdge = rowCounts.indices.contains { y in
            (y < edgeY || y >= grid.height - edgeY)
                && rowCounts[y] >= minimumHorizontalCoverage
        } || columnCounts.indices.contains { x in
            (x < edgeX || x >= grid.width - edgeX)
                && columnCounts[x] >= minimumVerticalCoverage
        }
        guard hasContinuousEdge else { return nil }

        return FilmBaseMeasurementBuilder.build(
            method: .continuousBorder,
            sampledPixelCount: grid.samples.count,
            candidateCount: candidates.count,
            selected: bright,
            gridWidth: grid.width,
            gridHeight: grid.height
        )
    }

    static func sampleDistributedOrangeBase(
        from grid: FilmBaseSampleGrid,
        neutralBase: Bool = false,
        excluding excluded: [Bool]? = nil
    ) -> FilmBaseMeasurement? {
        let candidates = grid.samples.filter {
            !isExcluded($0, in: grid, excluded: excluded) && isFilmBaseCandidate(
                r: $0.color.x,
                g: $0.color.y,
                b: $0.color.z,
                neutralBase: neutralBase
            )
        }
        guard candidates.count >= 32 else { return nil }

        let lumas = candidates.map(\.luma)
        let lumaCut = FilmBaseStatistics.percentile(lumas, 0.95)
        let medianLuma = FilmBaseStatistics.percentile(lumas, 0.50)
        guard lumaCut - medianLuma >= 0.02 else { return nil }

        let bright = candidates.filter { $0.luma >= lumaCut }
        let minimumCount = max(32, Int(Double(candidates.count) * 0.02))
        guard bright.count >= minimumCount else { return nil }

        return FilmBaseMeasurementBuilder.build(
            method: .distributedMask,
            sampledPixelCount: grid.samples.count,
            candidateCount: candidates.count,
            selected: bright,
            gridWidth: grid.width,
            gridHeight: grid.height
        )
    }

    /// 그리드 보더 폴백 — 기존 CIAreaAverage 스트립 폴백과 같은 의미론(상/하/좌/우 스트립
    /// 평균 → 밝기 필터 → 채널 중앙값)을 그리드 위에서 재현하되, 비필름 마스크(백라이트/
    /// 퍼포레이션)만 평균에서 제외한다. 마스크가 없으면 기존 폴백과 동등하다.
    static func borderFallback(
        from grid: FilmBaseSampleGrid,
        edgeFraction: Double,
        excluding excluded: [Bool]?
    ) -> FilmBaseMeasurement? {
        let edgeX = max(1, Int(Double(grid.width) * edgeFraction))
        let edgeY = max(1, Int(Double(grid.height) * edgeFraction))
        func stripMean(_ contains: (FilmBaseSample) -> Bool) -> SIMD3<Double>? {
            var sum = SIMD3<Double>(repeating: 0)
            var count = 0
            for sample in grid.samples
            where contains(sample) && !isExcluded(sample, in: grid, excluded: excluded) {
                sum += sample.color
                count += 1
            }
            guard count > 0 else { return nil }
            return sum / Double(count)
        }
        let samples = [
            stripMean { $0.y < edgeY },                     // top
            stripMean { $0.y >= grid.height - edgeY },      // bottom
            stripMean { $0.x < edgeX },                     // left
            stripMean { $0.x >= grid.width - edgeX },       // right
        ].compactMap { $0 }
        guard !samples.isEmpty else { return nil }
        let filtered = samples.filter { s in
            let lum = (s.x + s.y + s.z) / 3
            return lum > 0.25 && lum < 0.97   // 필름 베이스는 보통 이 범위
        }
        guard !filtered.isEmpty else { return nil }
        let fallbackSamples = filtered.enumerated().map {
            FilmBaseSample(x: $0.offset, y: 0, color: $0.element)
        }
        return FilmBaseMeasurementBuilder.build(
            method: .stripFallback,
            sampledPixelCount: grid.samples.count,
            candidateCount: filtered.count,
            selected: fallbackSamples,
            gridWidth: filtered.count,
            gridHeight: 1
        )
    }

    /// 필름 베이스 후보 판정. 과거엔 `r > g*1.12 && g > b*1.05`로 "진한 주황"만 강제했으나,
    /// 이는 Kodak Portra/Gold 계열만 통과시키고 Fuji 황/옅은 베이스, Vision3(ECN-2), 퇴색 분홍
    /// 베이스를 전부 탈락시켜 fallback (0.9,0.65,0.45) 로 떨어지게 했다(→ 반전 캐스트의 근원).
    ///
    /// 물리적 정의로 교체: 컬러 네거티브 베이스(미노광 + 잔류 염료)는 **항상 R≥G≥B 단조**다.
    /// 오렌지 마스크는 마젠타+황 염료의 조합이므로 R이 가장 높고 B가 가장 낮으며, 그 비율은
    /// 필름/현상마다 다르다(Fuji는 더 황/투명, Kodak은 더 진한 주황, ECN-2는 또 다름).
    /// 따라서 색 강도가 아니라 **R≥G≥B 단조성**만으로 후보를 식별한다. luma 범위는 미노광/염료
    /// 투과율의 합리적 범위로 유지.
    static func isFilmBaseCandidate(r: Double, g: Double, b: Double,
                                    neutralBase: Bool = false) -> Bool {
        let luma = (r + g + b) / 3
        if neutralBase {
            // B&W 네거티브: 마스크 없는 중립(회색) 베이스. 미노광 베이스는 밝은 회색으로 찍히고
            // 채널 편차가 작다. 채널 간 차이 ≤ 0.08 (필름 틴트/노이즈 허용).
            guard luma >= 0.10, luma <= 0.92 else { return false }
            return abs(r - g) <= 0.08 && abs(g - b) <= 0.08
        }
        // luma 상한: 미노광 베이스는 스캐너에서 중간~밝게 나오지만, 거의 흰(0.90+) 무필름 빈 공간
        // (홀더/마운트 간극)은 베이스가 아니다. 0.85 상한은 Fuji 옅은/황 베이스(최대 ~0.82)까지 커버.
        guard luma >= 0.03, luma <= 0.85 else { return false }
        // R≥G≥B 단조 (허용 오차: 노이즈/베이스 불균일성). 컬러 네거티브 베이스는 항상 R≥G≥B.
        let eps = 0.01
        guard r >= g - eps, g >= b - eps else { return false }
        // R-B 최소 분리: 진짜 베이스(마젠타+황 염료)는 R이 B보다 유의미하게 높다. 필름마다 강도가
        // 다르나(Fuji 옅음, Kodak 진함), 거의 중립 회색에 가까운 무필름 빈 공간(R-B≈0.1)과 구분하기
        // 위해 0.06 하한. Fuji 황 베이스(0.82,0.70,0.56 → R-B=0.26)도 여유 통과.
        return (r - b) >= 0.06
    }

    /// 영역의 평균 RGB를 구한다 (CIAreaAverage).
    static func averageRGB(of image: CIImage) -> SIMD3<Double>? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ])
        guard let out = filter?.outputImage else { return nil }
        var bitmap = [Float](repeating: 0, count: 4)
        // 색관리 linear 샘플링 — FilmBaseSampleGrid 와 동일한 이유(base 소비 도메인 일치).
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)
        let ctx = SamplingContextPool.context(workingColorSpace: linear)
        ctx.render(out, toBitmap: &bitmap,
                   rowBytes: 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBAf, colorSpace: linear)
        return SIMD3(Double(bitmap[0]), Double(bitmap[1]), Double(bitmap[2]))
    }

}
