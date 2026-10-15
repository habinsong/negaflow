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
    /// - Parameter excludingInterior: 사용자가 크롭한 사진 영역. 있으면 베이스를 **크롭 바깥 띠**
    ///   (리베이트)에서 먼저 찾고, 거기서 확신 있는 답이 없을 때만 프레임 전체로 돌아간다. 크롭
    ///   안에서는 찾지 않는다 — 크롭 안의 가장 얇은 곳은 베이스가 아니라 장면 최암부다(2026-10-14
    ///   실측: 유채색 그림자를 베이스로 잡아 중립 웨지 암부 R/B 3.47).
    public static func estimate(from image: CIImage, edgeFraction: Double = 0.06,
                                neutralBase: Bool = false,
                                confidentOnly: Bool = false,
                                excludingInterior region: AnalysisRegion? = nil) -> FilmBase? {
        let extent = image.extent
        guard extent.width > 4, extent.height > 4 else { return nil }

        // 축소본은 여기서 **한 번만** 짓는다. 뒤이어 도는 구조길(FilmBaseRebate)이 같은 격자를
        // 보므로 그대로 넘겨준다 — 따로 지으면 큰 스캔 한 장에 축소 비용이 통째로 한 번 더 붙는다.
        let sampleGrid = FilmBaseSampleGrid(image: image)
        // 비필름 마스크는 2 차 샘플러와 구조길이 함께 쓴다. 둘 다 안 부르는 경우(성분 검출이
        // 곧바로 성공하고 구조길도 원본을 안 읽는 경우)가 대부분이라 값을 미뤄 둔다.
        var cachedExclusion: [Bool]??
        func exclusion() -> [Bool]? {
            if let cachedExclusion { return cachedExclusion }
            let value = sampleGrid.flatMap { nonFilmExclusion(for: $0, neutralBase: neutralBase) }
            cachedExclusion = .some(value)
            return value
        }
        if let region, let sampleGrid,
           let cropped = estimateAroundCrop(image: image, grid: sampleGrid, region: region,
                                            edgeFraction: edgeFraction, neutralBase: neutralBase) {
            return cropped
        }
        guard let resolved = estimateWithoutRebate(
            from: image, grid: sampleGrid, edgeFraction: edgeFraction,
            neutralBase: neutralBase, confidentOnly: confidentOnly, exclusion: exclusion
        ) else { return nil }
        guard let sampleGrid else { return resolved }
        let rescued = rescuedWithRebate(image: image, grid: sampleGrid, resolved: resolved,
                                        neutralBase: neutralBase, exclusion: exclusion)
        let excluded = exclusion()
        return liftedToFilmEnvelope(rescued, grid: sampleGrid, neutralBase: neutralBase, exclusion: excluded) {
            excluded?[$0.y * sampleGrid.width + $0.x] != true
        }
    }

    /// 베이스 판정의 모순 문턱 — `FilmBaseRebate.contradictingFraction` 의 실측(정상 0~0.8%, 모순 7.1%~).
    static let contradictionFraction = 0.02

    /// 고른 값보다 뚜렷이 밝은 필름이 있으면(모순) 필름에서 가장 밝은 5%(분산 샘플러)로 올린다.
    /// 베이스가 화면에 없는 컷(리베이트 없이 사진만 스캔)에서 성분 검출은 결이 있는 얇은 면 — 이웃
    /// 15% 문턱에 걸려 조각난다 — 을 놓치고 더 어두운 매끈한 면을 고른다(2026-10-15 실측: 같은 롤
    /// 베이스 0.23/0.096/0.068, 고른 값 0.104/0.051/0.032, 그보다 밝은 필름 11% 가 반전에서 검정으로
    /// 잘렸다). 필름에서 베이스에 가장 가까운 것은 가장 얇은 면이므로 그 위로는 올리지 않는다.
    static func liftedToFilmEnvelope(
        _ base: FilmBase, grid: FilmBaseSampleGrid, neutralBase: Bool, exclusion: [Bool]?,
        counting include: (FilmBaseSample) -> Bool
    ) -> FilmBase {
        guard FilmBaseRebate.contradictingFraction(
            grid: grid, dmin: base.rgb, neutralBase: neutralBase, counting: include
        ) > contradictionFraction,
            let envelope = sampleDistributedOrangeBase(from: grid, neutralBase: neutralBase, excluding: exclusion)
        else { return base }
        func luma(_ c: SIMD3<Double>) -> Double { (c.x + c.y + c.z) / 3 }
        guard luma(envelope.rgb) > luma(base.rgb) else { return base }
        return envelope.filmBase(source: base.source)
    }

    /// 베이스를 어디서 찾는가. 크롭이 있으면 크롭 바깥 띠(`ring`) → 크롭 안 사진(`photo`) 순서다.
    enum SearchScope {
        /// 프레임 전체 — 백라이트·퍼포레이션이 섞일 수 있어 밝기 사전확률 강등을 쓴다.
        case frame
        /// 크롭 바깥 띠 — 리베이트·백라이트·홀더가 남는다. 광원은 색도 관계로 가른다.
        case ring
        /// 크롭 안 사진 — 전부 필름이라 광원이 없다. 강등하지 않는다.
        case photo
    }

    /// 크롭이 있을 때의 베이스. 디카 스캔은 원본에 퍼포레이션·백라이트·홀더가 함께 찍혀 프레임
    /// 전체를 뒤지면 광원을 베이스로 잡기 쉽다 — 그래서 크롭이 있으면 프레임 전체로 가지 않는다.
    ///  1. 크롭 바깥 띠(리베이트)에서 찾고, 그 값이 크롭 안 사진과 모순이 없으면 쓴다.
    ///  2. 모순이면 띠의 광원 강등이 틀렸을 수 있다(진짜 리베이트를 광원으로, 더 오렌지인 짙은 장면을
    ///     베이스로 본 경우) — 강등 없이 띠에서 가장 밝은 성분을 보고, 사진과 모순이 없고 광원처럼
    ///     보이지도 않으면 쓴다.
    ///  3. 띠에 베이스가 없으면(크롭이 리베이트를 잘라 냄) 크롭 안 사진에서 가장 얇은 필름 면을
    ///     쓴다. 사진은 전부 필름이라 광원이 끼지 않고, 필름에서 베이스에 가장 가까운 것은 가장
    ///     얇은 면이다 — 베이스가 보이지 않는 프레임에서 남는 가장 확실한 근사다.
    /// 셋 다 없을 때만 nil — 그때는 예전처럼 프레임 전체에서 찾는다.
    static func estimateAroundCrop(
        image: CIImage,
        grid: FilmBaseSampleGrid,
        region: AnalysisRegion,
        edgeFraction: Double,
        neutralBase: Bool
    ) -> FilmBase? {
        let ringGrid = grid.excludingInterior(of: region)
        var cachedRingExclusion: [Bool]??
        func ringExclusion() -> [Bool]? {
            if let cachedRingExclusion { return cachedRingExclusion }
            let value = nonFilmExclusion(for: ringGrid, neutralBase: neutralBase)
            cachedRingExclusion = .some(value)
            return value
        }
        func ringBase(demotes: Bool) -> FilmBase? {
            estimateWithoutRebate(
                from: image, grid: ringGrid, edgeFraction: edgeFraction, neutralBase: neutralBase,
                confidentOnly: true, scope: .ring, demotes: demotes, exclusion: ringExclusion
            ).map {
                rescuedWithRebate(image: image, grid: ringGrid, resolved: $0,
                                  neutralBase: neutralBase, scope: .ring, exclusion: ringExclusion)
            }
        }
        // 크롭 안은 사진, 곧 전부 필름이다. 필름에는 베이스보다 밝은 것이 없으므로 그 안에 고른
        // 값보다 뚜렷이 밝은 곳이 많으면 띠에서 고른 것은 베이스가 아니다 — 크롭이 홀더와 리베이트를
        // 잘라 띠에 베이스가 없을 때 띠 안의 짙은 하늘을 잡는다(2026-10-14 실측: 고른 값
        // 0.034/0.013/0.006 보다 밝은 필름 60%). 느슨한 크롭에 걸린 광원은 비필름 마스크로 뺀다.
        func contradicted(_ base: FilmBase) -> Bool {
            FilmBaseRebate.contradictingFraction(grid: grid, dmin: base.rgb, neutralBase: neutralBase) {
                grid.isInterior($0, of: region)
            } > contradictionFraction
        }
        // 사진 안 탐색은 띠가 실패했을 때만 돈다(대부분의 프레임은 띠에서 끝난다).
        var cachedPhoto: FilmBase??
        func photo() -> FilmBase? {
            if let cachedPhoto { return cachedPhoto }
            let photoGrid = grid.keepingInterior(of: region)
            let value = estimateWithoutRebate(
                from: image, grid: photoGrid, edgeFraction: edgeFraction,
                neutralBase: neutralBase, confidentOnly: true, scope: .photo, exclusion: { nil }
            ).map {
                liftedToFilmEnvelope($0, grid: photoGrid, neutralBase: neutralBase, exclusion: nil) {
                    grid.isInterior($0, of: region)
                }
            }
            cachedPhoto = .some(value)
            return value
        }
        guard let ring = ringBase(demotes: true) else { return photo() }
        if !contradicted(ring) { return ring }
        // 2026-10-15 실측: 오른쪽 띠의 리베이트(0.34/0.158/0.092)를 광원으로 강등하고 짙은 장면
        // (0.11/0.032/0.012)을 골랐다 — 사진의 97% 가 그보다 밝았다.
        if !neutralBase, let top = ringBase(demotes: false), top.rgb != ring.rgb, !contradicted(top),
           !(photo().map { looksLikeLight(top.rgb, comparedWith: $0.rgb) } ?? false) {
            return top
        }
        return photo()
    }

    /// `candidate` 가 `film` 을 비춘 광원처럼 보이는가. 필름 = 광원 × 마스크 × 장면 염료라, 광원이면
    /// 필름이 마스크 색도(띠 강등과 같은 문턱)만큼 두 축 모두 더 오렌지다.
    static func looksLikeLight(_ candidate: SIMD3<Double>, comparedWith film: SIMD3<Double>) -> Bool {
        func logRatio(_ a: Double, _ b: Double) -> Double { log10(max(a, 1e-5) / max(b, 1e-5)) }
        let redGreen = logRatio(film.x, film.y) - logRatio(candidate.x, candidate.y)
        let greenBlue = logRatio(film.y, film.z) - logRatio(candidate.y, candidate.z)
        return redGreen >= ringMaskChroma.redGreen && greenBlue >= ringMaskChroma.greenBlue
    }

    /// 이 지점을 넘으면 **틀렸다고 볼 이유가 있을 때만** 원본을 한 화소라도 더 읽는다.
    static let rebateGateFraction = 0.05

    /// 고른 값이 물리적으로 말이 되는지 보고, 안 되면 리베이트 띠에서 원본 해상도로 다시 잰다.
    /// 받아들이지 않으면 기존 값이 그대로 남는다 — 구조길이 아무 답도 못 내는 사진은 앞 판과
    /// 완전히 같게 동작한다.
    static func rescuedWithRebate(
        image: CIImage,
        grid: FilmBaseSampleGrid,
        resolved: FilmBase,
        neutralBase: Bool,
        scope: SearchScope = .frame,
        exclusion: () -> [Bool]? = { nil }
    ) -> FilmBase {
        let brighter = FilmBaseRebate.brighterThanBaseFraction(grid: grid, dmin: resolved.rgb)
        // 띠 찾기는 축소본 위에서만 도는 선형 두 번이라 늘 돌려도 싸다. 원본을 다시 읽을지는
        // 그 안에서 정한다 — 문지기가 열렸거나, 띠가 뭉개질 만큼 얇을 때만이다.
        guard let rebate = FilmBaseRebate.rebateBase(
            image: image, grid: grid, neutralBase: neutralBase,
            gateOpen: brighter > rebateGateFraction, nonFilmExclusion: exclusion
        ), FilmBaseRebate.accept(rebate: rebate.rgb, current: resolved.rgb) else {
            return resolved
        }
        // 크롭 바깥 띠에서는 베이스를 색도 증거로 골랐다. 리베이트 띠는 베이스 그 자체라 색도가
        // 같아야 한다 — 마스크 색도만큼 덜 오렌지인 "더 밝은 띠"는 광원이다(교체하지 않는다).
        if scope == .ring, !neutralBase {
            func logRB(_ c: SIMD3<Double>) -> Double { log10(max(c.x, 1e-5) / max(c.z, 1e-5)) }
            guard logRB(rebate.rgb) >= logRB(resolved.rgb) - backlightMaskLogMargin else { return resolved }
        }
        return rebate.filmBase(source: resolved.source)
    }

    private static func estimateWithoutRebate(
        from image: CIImage,
        grid sampleGrid: FilmBaseSampleGrid?,
        edgeFraction: Double,
        neutralBase: Bool,
        confidentOnly: Bool,
        scope: SearchScope = .frame,
        demotes: Bool = true,
        exclusion: () -> [Bool]?
    ) -> FilmBase? {
        let extent = image.extent

        // 1차: 연결 성분 기반 검출(2026-07-14 v3) — 공간 구조 불변량이라 percentile/고정
        // luma 창 방식과 달리 광원 불균일·경계 혼합 셀에 강하다.
        if let componentSample = sampleGrid.flatMap({
            connectedBaseComponent(from: $0, neutralBase: neutralBase, scope: scope, demotes: demotes)
        }) {
            return componentSample.filmBase(source: .auto)
        }

        // 2차: 기존 샘플러(작은 이미지/후보 희소 등 성분 검출이 불가능한 경우).
        let excluded = exclusion()
        let edgeSample = sampleGrid.flatMap {
            sampleBrightOrangeBase(from: $0, edgeFraction: edgeFraction,
                                   neutralBase: neutralBase, excluding: excluded)
        }
        let distributedSample = sampleGrid.flatMap {
            sampleDistributedOrangeBase(from: $0, neutralBase: neutralBase, excluding: excluded)
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
            return borderFallback(from: grid, edgeFraction: edgeFraction,
                                  neutralBase: neutralBase, excluding: excluded)?
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

        // 이상치(장면 쪽으로 치우친 어두운 스트립, 준클리핑 무필름) 제거. 어두운 쪽 컷은
        // 가장 밝은 스트립 기준의 비율이다 — 선형 raw 처럼 전체가 낮게 실린 스캔에서
        // 고정 컷(옛 0.25)은 네 스트립을 모두 버렸다.
        let filtered = brightStrips(samples)
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
        neutralBase: Bool,
        scope: SearchScope = .frame,
        demotes: Bool = true
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

        // 후보 판정 + 이 스캔의 밝기 바닥 + 불변량 A(경계 혼합 셀 제외).
        let floor = candidateLumaFloor(for: grid, neutralBase: neutralBase)
        var eligible = [Bool](repeating: false, count: count)
        for sample in grid.samples {
            let i = sample.y * width + sample.x
            guard !hardExcluded[i], sample.luma >= floor,
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
        func medianLogRB(_ cells: [Int]) -> Double {
            var values = cells.map { cell -> Double in
                let color = grid.samples[cell].color
                return log10(max(color.x, 1e-5) / max(color.z, 1e-5))
            }
            values.sort()
            return values.isEmpty ? 0 : values[values.count / 2]
        }
        /// 채널별 log10 중앙값(밀도의 음수) — 두 성분의 차가 채널별 밀도 차다.
        func medianLogChannels(_ cells: [Int]) -> SIMD3<Double> {
            func median(_ channel: (SIMD3<Double>) -> Double) -> Double {
                var values = cells.map { log10(max(channel(grid.samples[$0].color), 1e-5)) }
                values.sort()
                return values.isEmpty ? 0 : values[values.count / 2]
            }
            return SIMD3(median(\.x), median(\.y), median(\.z))
        }

        var bestIndex = 0
        if !neutralBase, scope == .frame, demotes,
           let secondIndex = components.firstIndex(where: {
               $0.p75 < components[0].p75 * demoteRatioRange.upperBound
           }),
           demoteRatioRange.contains(components[secondIndex].p75 / components[0].p75),
           components[0].p75 >= demoteMinLuma,
           medianRB(components[0].cells) < medianRB(components[secondIndex].cells) * demoteRBRatio {
            bestIndex = secondIndex
        }
        // 크롭 바깥 띠에는 주로 리베이트·백라이트·홀더가 남는다. 그래서 밝기 사전확률(≥0.6)과
        // 밝기 비 창 없이 **"베이스 = 광원 × 마스크" 의 색도 관계**로 광원을 가른다. 오렌지 마스크는
        // 초록과 파랑을 함께 깎는다 — 베이스는 광원보다 log10(R/G) 가 Dmin_G − Dmin_R, log10(G/B) 가
        // Dmin_B − Dmin_G 만큼 크다. 색도는 조도와 무관해 비네팅·패널 가장자리로 광원이 베이스만큼
        // 어두워져도(실측 p75 0.40 vs 0.35, 광원 쪽 조도 −1.5EV) 그대로 성립한다(2026-10-14 실측
        // 추정/실제 0.55/0.79/1.25 를 바로잡음). R/B 하나만 보면 안 된다 — 홀더가 광원을 가려 최상위가
        // 진짜 베이스일 때, 띠에 걸친 이웃 프레임의 얇은 푸른 그림자도 베이스보다 R/B 가 크다(실측: 그
        // 면을 베이스로 잡아 암부 R/B 수천 배). 그런 면은 파랑만 깎여 R/G 관계를 채우지 못한다.
        // 장면이 섞이는 프레임 전체 탐색에서는 쓰지 않는다.
        let ringChromaDemotion = scope == .ring && !neutralBase
        if ringChromaDemotion, demotes, bestIndex == 0 {
            let top = medianLogChannels(components[0].cells)
            if let maskIndex = components.indices.dropFirst().first(where: { index in
                let candidate = medianLogChannels(components[index].cells)
                let redGreen = (candidate.x - candidate.y) - (top.x - top.y)
                let greenBlue = (candidate.y - candidate.z) - (top.y - top.z)
                return components[index].p75 >= components[0].p75 * demoteRatioRange.lowerBound
                    && redGreen >= ringMaskChroma.redGreen && greenBlue >= ringMaskChroma.greenBlue
            }) {
                bestIndex = maskIndex
            }
        }
        let bestLogRB = ringChromaDemotion ? medianLogRB(components[bestIndex].cells) : 0

        // 선택 성분 + 형제 성분(p75 ≥ 0.90×) 병합 — 멀티 스트립에서 스트립마다 분리된
        // 베이스 네트워크를 함께 쓴다(공간 커버리지·표본 수 ↑).
        let bestScore = components[bestIndex].p75
        var bestCells = components[bestIndex].cells
        for (index, component) in components.enumerated()
        where index != bestIndex && component.p75 >= bestScore * 0.90 && component.p75 <= bestScore / 0.90
            && (!ringChromaDemotion
                || abs(medianLogRB(component.cells) - bestLogRB) < backlightMaskLogMargin) {
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
    /// 크롭 바깥 띠에서 광원과 베이스를 가르는 문턱 — 번들 컬러 네거티브(C-41·ECN-2) 마스크
    /// 색도의 전형값(중앙값)의 절반(측정 잡음·광원 색 여유). 강등은 두 색도 축(R/G, G/B)을 함께
    /// 보고, 형제 병합·리베이트 교체는 R/B 차를 본다. 마스크가 약한 예외 필름(ORWO·Harman, R/G
    /// 0.02–0.10)은 띠 강등에 걸리지 않고 밝기 사전확률 강등만 받는다.
    static let backlightMaskLogMargin = 0.5 * colorNegativeMaskMedian { $0.z - $0.x }
    static let ringMaskChroma = (redGreen: 0.5 * colorNegativeMaskMedian { $0.y - $0.x },
                                 greenBlue: 0.5 * colorNegativeMaskMedian { $0.z - $0.y })

    private static func colorNegativeMaskMedian(_ value: (SIMD3<Double>) -> Double) -> Double {
        let values = FilmStockDminRegistry.all
            .filter { $0.process == "C-41" || $0.process == "ECN-2" }
            .map { value($0.dminDensity) }
            .sorted()
        return values.isEmpty ? 0 : values[values.count / 2]
    }

    static func nonFilmExclusion(for grid: FilmBaseSampleGrid,
                                 neutralBase: Bool) -> [Bool]? {
        let floor = candidateLumaFloor(for: grid, neutralBase: neutralBase)
        let candidates = grid.samples.filter {
            $0.luma >= floor && isFilmBaseCandidate(r: $0.color.x, g: $0.color.y, b: $0.color.z,
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
        let floor = candidateLumaFloor(for: grid, neutralBase: neutralBase)
        let all = grid.samples.filter {
            !isExcluded($0, in: grid, excluded: excluded) && $0.luma >= floor && isFilmBaseCandidate(
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
        let floor = candidateLumaFloor(for: grid, neutralBase: neutralBase)
        let candidates = grid.samples.filter {
            !isExcluded($0, in: grid, excluded: excluded) && $0.luma >= floor && isFilmBaseCandidate(
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
    /// 스트립이 베이스를 보고 있다고 인정할 최소 수준(이 스캔의 베이스 수준 대비).
    static let stripBaseLevelFraction = 0.5

    static func borderFallback(
        from grid: FilmBaseSampleGrid,
        edgeFraction: Double,
        neutralBase: Bool = false,
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
        // 스트립 평균이 이 스캔의 베이스 수준에 못 미치면 그 스트립은 장면(또는 산발적 밝은
        // 얼룩과 어두운 필름의 혼합)이다 — 약한 폴백이 그것을 베이스로 확정하면 안 된다.
        let baseLevel = candidateLumaPeak(for: grid, neutralBase: neutralBase)
        let filtered = brightStrips(samples).filter {
            ($0.x + $0.y + $0.z) / 3 >= baseLevel * stripBaseLevelFraction
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
    /// 마스크 분리와 중립성은 **비율**로 판정한다. 염료 투과는 곱셈이라 R−B 같은 가산량은
    /// 노출에 비례해 줄어든다. 고정 가산 임계(옛 0.06)는 선형 raw 처럼 값이 낮게 실리는
    /// 스캔에서 같은 필름의 베이스를 통째로 탈락시켰다(실측: Kodak계 R<0.075, Fuji계 R<0.097,
    /// 흑백 luma<0.10 에서 자동 추정이 nil → 상수 폴백으로 반전이 어긋남).
    /// 노이즈가 비율만으로 통과하지 못하도록 작은 절대 바닥을 함께 둔다.
    /// 후보의 절대 바닥. 노이즈/블랙을 막되, 선형 raw 의 어두운 베이스(16bit 에서도 유효한
    /// 값 대역)는 통과시킨다 — sRGB 로 보면 0.1 정도에 해당한다.
    static let minimumCandidateLuma = 0.012
    static let minimumMaskRatio = 0.10
    static let minimumMaskSeparation = 0.004
    static let maximumNeutralSpreadRatio = 0.12
    static let neutralSpreadFloor = 0.01

    /// 이 스캔에서 베이스일 수 있는 최소 밝기. 베이스는 필름에서 가장 밝은 곳이므로, 가장 밝은
    /// 후보보다 한참 어두운 셀은 베이스가 아니라 밀도 높은 장면이다. 비율 판정만으로는 오렌지
    /// 장면 전체가 후보로 들어오므로(마스크 비율은 밀도와 무관하게 유지된다) 이 바닥이 필요하다.
    /// 어두운 광원을 베이스로 강등하는 경로(demoteRatioRange 하한 0.12)를 막지 않도록 0.10 을 쓴다.
    static let candidateFloorFraction = 0.10

    static func candidateLumaFloor(for grid: FilmBaseSampleGrid, neutralBase: Bool) -> Double {
        candidateLumaPeak(for: grid, neutralBase: neutralBase) * candidateFloorFraction
    }

    /// 이 스캔에서 베이스일 수 있는 가장 밝은 수준(후보 luma p99).
    static func candidateLumaPeak(for grid: FilmBaseSampleGrid, neutralBase: Bool) -> Double {
        let lumas = grid.samples
            .filter { isFilmBaseCandidate(r: $0.color.x, g: $0.color.y, b: $0.color.z,
                                          neutralBase: neutralBase) }
            .map(\.luma)
        guard !lumas.isEmpty else { return 0 }
        return FilmBaseStatistics.percentile(lumas, 0.99)
    }

    static func isFilmBaseCandidate(r: Double, g: Double, b: Double,
                                    neutralBase: Bool = false) -> Bool {
        let luma = (r + g + b) / 3
        let peak = max(r, max(g, b))
        if neutralBase {
            // B&W 네거티브: 마스크 없는 중립(회색) 베이스. 채널 편차는 밝기에 비례해 허용한다
            // (밝은 베이스에서 ±0.08 이던 폭과 같은 뜻이고, 어두운 스캔에서는 그만큼 좁아진다).
            guard luma >= minimumCandidateLuma, luma <= 0.92 else { return false }
            let tolerance = maximumNeutralSpreadRatio * peak + neutralSpreadFloor
            return abs(r - g) <= tolerance && abs(g - b) <= tolerance
        }
        // luma 상한: 미노광 베이스는 스캐너에서 중간~밝게 나오지만, 거의 흰(0.90+) 무필름 빈 공간
        // (홀더/마운트 간극)은 베이스가 아니다. 0.85 상한은 Fuji 옅은/황 베이스(최대 ~0.82)까지 커버.
        guard luma >= minimumCandidateLuma, luma <= 0.85 else { return false }
        // R≥G≥B 단조 (허용 오차: 노이즈/베이스 불균일성). 컬러 네거티브 베이스는 항상 R≥G≥B.
        let eps = 0.01
        guard r >= g - eps, g >= b - eps else { return false }
        // R−B 최소 분리(비율): 진짜 베이스(마젠타+황 염료)는 B가 R보다 뚜렷이 낮다. 필름마다
        // 강도가 다르나(Fuji 옅음 0.32, Kodak 진함 0.8 수준) 거의 중립인 무필름 빈 공간과는
        // 이 비율로 갈린다 — 노출이 낮아도 비율은 유지된다.
        guard peak > 0 else { return false }
        return (r - b) >= max(minimumMaskSeparation, minimumMaskRatio * peak)
    }

    /// 스트립 평균 중 베이스로 쓸 것들. 준클리핑(무필름)은 절대값으로 자르고, 어두운 쪽은
    /// 가장 밝은 스트립의 비율로 자른다 — 스캔 전체 노출과 무관하게 같은 판정을 하기 위해서다.
    static let stripBrightFraction = 0.55
    static let stripClippingCut = 0.97

    static func brightStrips(_ samples: [SIMD3<Double>]) -> [SIMD3<Double>] {
        func luma(_ s: SIMD3<Double>) -> Double { (s.x + s.y + s.z) / 3 }
        let usable = samples.filter { luma($0) < stripClippingCut }
        guard let brightest = usable.map(luma).max(), brightest > 0 else { return [] }
        return usable.filter { luma($0) >= brightest * stripBrightFraction }
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
