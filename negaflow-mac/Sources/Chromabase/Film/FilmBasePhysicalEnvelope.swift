import Foundation

// MARK: - 유제 색과 무관한 마지막 확인 (Windows `lifted_to_physical_envelope` 와 같다)
//
// 위의 탐색은 "베이스는 스캔에서 오렌지(R ≥ G ≥ B)" 라는 가정에 기댄다(`isFilmBaseCandidate`).
// 그 가정은 필름과 원본에 따라 깨진다.
//  - 2026-10-31 GT-X900 으로 스캔한 Kodak Vision3 250D 롤(4~11번)은 프레임 사이 틈의 베이스가
//    0.30/0.34/0.33 처럼 초록·파랑이 빨강보다 밝아 후보에서 통째로 빠졌고, 사진 속 짙은 오렌지
//    면(10번: 0.13/0.08/0.08)이 베이스로 골라져 반전이 어둡고 붉게 잘렸다. 같은 스캐너로 찍은
//    다른 필름은 0.34/0.28/0.22 로 오렌지였다 — 베이스 색은 필름마다 다르다.
//  - 카메라 RAW 음화는 선형 카메라 RGB(단위 화이트밸런스)라 초록 감도가 커서 베이스가 G>R 로
//    찍힌다. Windows 실측에서 리베이트를 통째로 놓쳐 0.002/0.003/0.002 같은 값을 고른 파일이
//    여럿이었다.
//
// 그래서 여기서는 색을 묻지 않고 물리를 본다. 필름 = 광원 × 베이스 × 장면 염료이고 염료는 빛을
// **덜어내기만** 하므로, 베이스는 필름에서 **모든 채널이 함께** 가장 밝다. 고른 값보다 모든 채널이
// 뚜렷이 밝은 필름이 넓게 있으면 그 값은 베이스가 아니다. 그때 모든 채널이 가장 밝은 매끈한 면으로
// 올린다. 오렌지든 보라든 회색이든 같다.
//
// 그보다 밝은 것은 필름이 아닌 맨 광원뿐이다.
//  - 포화 근처는 필름이 아니다(베이스도 밀도가 있어 포화되지 않는다 — `FilmBaseRebate.accept` 와
//    같은 문턱).
//  - 오렌지로 보이는 면은 위의 탐색이 이미 보고 판정했다(광원이면 강등했다). 여기서는 그 탐색이
//    **보지 못한** 오렌지가 아닌 밝은 필름만 구제한다 — 따뜻한 백라이트를 다시 끌어올리지 않는다.
//  - 포화되지 않은 광원은 상대 색도(`looksLikeLight`)로 거른다. 지금 값과도, 그 아래 더 어두운
//    면과도 견준다(베이스 = 광원 × 마스크는 색 공간과 무관한 상대 관계다).
//  - 크롭이 있으면 사진 안만 증거로 삼으므로 띠의 광원은 증거에 끼지 않는다.
// 남는 한계는 하나다 — 마스크가 회색이라 베이스와 광원의 색이 같고, 광원이 포화되지 않은 채 크롭
// 없이 넓게 찍혀 있으면 색으로도 밝기로도 가를 수 없다. 흑백 탐색과 같은 한계다.
//
// 검증(Windows, 같은 규칙): 카탈로그 컬러 네거티브 169 장 중 19 장이 바뀌었고, 바뀐 것은 모두
// 어둡게 뭉개지던 값이 실제 베이스(프레임 사이 틈·리베이트) 쪽으로 온 경우였다. 오렌지 필름 옆의
// 따뜻한 백라이트를 강등하는 기존 시험은 그대로 통과한다.
extension FilmBaseEstimator {
    /// 모든 채널이 이만큼 밝아야 "베이스보다 밝은 필름" 으로 센다.
    static let envelopeChannelFactor = 1.15
    /// 이 이상은 필름이 아닌 맨 광원이다.
    static let envelopeSaturation = 0.985

    static func isPlausibleFilmCell(_ color: SIMD3<Double>) -> Bool {
        guard color.x.isFinite, color.y.isFinite, color.z.isFinite else { return false }
        let luma = (color.x + color.y + color.z) / 3
        let peak = max(color.x, max(color.y, color.z))
        return luma >= minimumCandidateLuma && luma <= 0.85 && peak < envelopeSaturation
    }

    static func isBrighterInEveryChannel(_ color: SIMD3<Double>, than base: SIMD3<Double>,
                                         by factor: Double) -> Bool {
        color.x >= base.x * factor && color.y >= base.y * factor && color.z >= base.z * factor
    }

    /// 고른 베이스보다 모든 채널이 1.15 배 이상 밝은 필름 칸의 비율. 크롭이 있으면 사진 안만 센다.
    static func filmBrighterFraction(grid: FilmBaseSampleGrid, base: SIMD3<Double>,
                                     region: AnalysisRegion?) -> Double {
        var counted = 0
        var brighter = 0
        for sample in grid.samples {
            if let region, !grid.isInterior(sample, of: region) { continue }
            let color = sample.color
            guard color.x.isFinite, color.y.isFinite, color.z.isFinite else { continue }
            counted += 1
            if isPlausibleFilmCell(color),
               isBrighterInEveryChannel(color, than: base, by: envelopeChannelFactor) {
                brighter += 1
            }
        }
        return counted > 0 ? Double(brighter) / Double(counted) : 0
    }

    /// 색을 묻지 않는 매끈한 밝은 면들(p75 내림차순). `connectedBaseComponent` 와 같은 틀이다 —
    /// 이웃 2 칸 안에 1.15 배 넘게 밝은 칸이 없는 칸만 잇고, 격자의 0.4%(최소 24 칸)보다 작은
    /// 조각은 버린다(퍼포레이션 구멍·먼지 같은 작은 광원이 여기서 빠진다). 홀더 그늘은 밝은 필름의
    /// 10% 아래로 잘라 낸다.
    static func envelopeComponents(grid: FilmBaseSampleGrid) -> [(cells: [Int], p75: Double)] {
        let width = grid.width, height = grid.height
        let count = width * height
        guard count > 0, grid.samples.count == count else { return [] }
        var luma = [Double](repeating: 0, count: count)
        var plausible = [Bool](repeating: false, count: count)
        var filmLumas: [Double] = []
        for sample in grid.samples {
            let index = sample.y * width + sample.x
            luma[index] = sample.luma
            if isPlausibleFilmCell(sample.color) {
                plausible[index] = true
                filmLumas.append(sample.luma)
            }
        }
        guard !filmLumas.isEmpty else { return [] }
        let floor = FilmBaseStatistics.percentile(filmLumas, 0.99) * candidateFloorFraction
        let radius = neighborRadius
        var smooth = [Bool](repeating: false, count: count)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                guard plausible[index], luma[index] >= floor else { continue }
                let ceiling = luma[index] * brighterNeighborRatio
                var isBoundary = false
                for ny in max(0, y - radius)...min(height - 1, y + radius) {
                    for nx in max(0, x - radius)...min(width - 1, x + radius)
                    where luma[ny * width + nx] > ceiling {
                        isBoundary = true
                        break
                    }
                    if isBoundary { break }
                }
                smooth[index] = !isBoundary
            }
        }
        let coherentCount = max(24, Int(Double(count) * 0.004))
        var label = [Int](repeating: -1, count: count)
        var components: [(cells: [Int], p75: Double)] = []
        var nextLabel = 0
        var queue: [Int] = []
        for start in 0..<count where smooth[start] && label[start] < 0 {
            var cells: [Int] = []
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            label[start] = nextLabel
            while let cell = queue.popLast() {
                cells.append(cell)
                let cx = cell % width, cy = cell / width
                for (nx, ny) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)] {
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let next = ny * width + nx
                    if smooth[next] && label[next] < 0 {
                        label[next] = nextLabel
                        queue.append(next)
                    }
                }
            }
            nextLabel += 1
            guard cells.count >= coherentCount else { continue }
            components.append((cells, FilmBaseStatistics.percentile(cells.map { luma[$0] }, 0.75)))
        }
        components.sort { $0.p75 > $1.p75 }
        return components
    }

    /// 고른 베이스와 모순되는(모든 채널이 뚜렷이 더 밝은) 필름이 넓게 있으면, 오렌지가 아닌 가장
    /// 밝은 매끈한 필름 면으로 올린다. 컬러 네거티브만 부른다.
    static func liftedToPhysicalEnvelope(_ base: FilmBase, grid: FilmBaseSampleGrid,
                                         region: AnalysisRegion?) -> FilmBase {
        guard filmBrighterFraction(grid: grid, base: base.rgb, region: region) > contradictionFraction
        else { return base }
        let components = envelopeComponents(grid: grid)
        // 성분마다 밝은 절반(최소 24 칸) — 연결 성분 탐색이 베이스를 재는 방식과 같다.
        let measurements: [FilmBaseMeasurement?] = components.map { component in
            let members = component.cells.map { grid.samples[$0] }.sorted { $0.luma > $1.luma }
            let selected = Array(members.prefix(max(members.count / 2, min(members.count, 24))))
            return FilmBaseMeasurementBuilder.build(
                method: .connectedComponent,
                sampledPixelCount: grid.samples.count,
                candidateCount: component.cells.count,
                selected: selected,
                gridWidth: grid.width,
                gridHeight: grid.height
            )
        }
        func luma(_ c: SIMD3<Double>) -> Double { (c.x + c.y + c.z) / 3 }
        let currentLuma = luma(base.rgb)
        for index in components.indices {
            guard let measured = measurements[index] else { continue }
            let candidate = measured.rgb
            // 밝은 순서이므로 지금 값보다 뚜렷이 밝지 않은 성분이 나오면 더 볼 것이 없다.
            if luma(candidate) < currentLuma * envelopeChannelFactor { break }
            // 오렌지로 보이는 면은 위의 탐색이 이미 판정했다.
            if isFilmBaseCandidate(r: candidate.x, g: candidate.y, b: candidate.z) { continue }
            let saturated = candidate.x >= envelopeSaturation || candidate.y >= envelopeSaturation
                || candidate.z >= envelopeSaturation
            // 베이스는 지금 값보다 어느 채널도 어둡지 않다.
            let notDarker = candidate.x >= base.rgb.x && candidate.y >= base.rgb.y
                && candidate.z >= base.rgb.z
            if saturated || !notDarker || looksLikeLight(candidate, comparedWith: base.rgb)
                || filmBrighterFraction(grid: grid, base: candidate, region: region) > contradictionFraction {
                continue
            }
            // 광원은 그것이 비춘 필름보다 마스크 색도만큼 덜 오렌지다. 띠 강등과 같은 밝기 창
            // (0.12~0.87 배) 안에 그런 더 어두운 면이 있으면 이 면은 광원이다.
            var litFilmBelow = false
            for darker in components.indices where darker > index && !litFilmBelow {
                let ratio = components[darker].p75 / max(components[index].p75, 1e-9)
                guard demoteRatioRange.contains(ratio), let below = measurements[darker] else { continue }
                litFilmBelow = looksLikeLight(candidate, comparedWith: below.rgb)
            }
            if litFilmBelow { continue }
            return measured.filmBase(source: base.source)
        }
        return base
    }
}
