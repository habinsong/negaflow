import CoreGraphics
import CoreImage
import Foundation

// MARK: - FilmBaseRebate
//
// 자동 베이스가 **틀렸을 때만** 도는 구조길이다.
//
// 지금 추정기는 원본을 256 폭으로 줄인 격자에서 베이스를 찾는다(FilmBaseSampleGrid).
// 리베이트(사진이 찍히지 않은 필름 여백)가 얇으면 그 축소에서 주변 화소와 평균되어 사라지고,
// 다음으로 밝은 덩어리인 **사진 내용**이 베이스로 뽑힌다. 그러면 반전의 0 점이 낮게 앉아
// 사진이 통째로 어두워진다.
//
// 여기서는 그것을 **되돌리지 않는다.** 기존 경로가 낸 값을 그대로 두고, 그 값이 물리적으로
// 말이 되는지만 보고, 안 되면 그때만 원본 해상도에서 다시 잰다. 정상 사진은 문지기에서
// 걸러져 원본을 한 화소도 더 읽지 않는다.
enum FilmBaseRebate {
    /// 줄 길이의 이만큼이 **연속으로** 이어져야 그 줄이 수준 L 을 유지한 것으로 본다.
    /// 리베이트는 필름 폭을 가로지르므로 버티고, 먼지·흠집은 짧아서 못 버틴다.
    static let runFraction = 0.10
    static let minimumRun = 4

    /// 찾은 띠가 이보다 두꺼우면 리베이트가 아니라 장면이다. 기각하면 기존 값이 남는다.
    static let maximumBandFraction = 0.25

    /// 최고 수준의 이 비율 위까지를 같은 띠로 본다.
    static let bandLevelRatio = 0.90

    /// 원본에서 이보다 많이 모이면 건너뛰며 읽는다. 중앙값을 내는 데 필요한 것은 분포이지
    /// 화소 수가 아니고, 이 상한이 띠가 넓게 잡힌 최악의 경우에 비용을 묶는다.
    static let measurementSampleCap = 50000

    /// 원본을 한 번에 올리는 최대 화소 수. 띠가 두껍게 잡힌 경우에도 메모리를 묶는다
    /// (방문 순서와 건너뛰기는 조각 경계와 무관하게 이어진다).
    static let readChunkPixels = 4_000_000

    /// 다시 잰 값이 최소 이만큼 밝아야 받는다.
    static let acceptanceRatio = 1.15

    /// 맨 광원은 센서 최대치에 붙는다. 필름 베이스는 자기도 밀도가 있어 절대 포화되지 않는다.
    static let saturationCut = 0.985

    /// 고른 베이스보다 밝은 필름 화소의 비율.
    ///
    /// 필름에서 베이스보다 밝은 것은 없다 — 베이스는 아무것도 안 찍힌 자리라 빛을 가장 많이
    /// 통과시킨다. 그러니 "베이스보다 밝은 화소가 잔뜩 있다" 는 것은 사진이 어두운지 밝은지와
    /// 무관하게 **그 자체로 모순**이며, 고른 값이 베이스가 아니라는 뜻이다.
    ///
    /// 이 판정이 밝기가 아니라 모순을 보기 때문에 야경도 안전하다. 야경은 네거티브에서 오히려
    /// 베이스 쪽으로 붙으므로(빛을 적게 받아 얇다) 베이스보다 밝은 화소가 생기지 않는다.
    static func brighterThanBaseFraction(grid: FilmBaseSampleGrid, dmin: SIMD3<Double>) -> Double {
        guard !grid.samples.isEmpty, dmin.x.isFinite, dmin.y.isFinite, dmin.z.isFinite else {
            return 0
        }
        let level = (dmin.x + dmin.y + dmin.z) / 3
        let brighter = grid.samples.reduce(into: 0) { total, sample in
            if sample.luma > level { total += 1 }
        }
        return Double(brighter) / Double(grid.samples.count)
    }

    struct Band {
        var horizontal: Bool
        var first: Int
        var last: Int
        var level: Double
    }

    /// 창 크기 `window` 안 최솟값들의 최댓값.
    ///
    /// 후보가 아닌 칸은 0 으로 들어오므로 그 칸을 품은 창은 전부 0 이 되어 탈락한다. 단조
    /// 덱이라 줄 길이에 선형이고 분기가 없다.
    static func sustainedLevel(_ line: [Double], window: Int) -> Double {
        guard window > 0, line.count >= window else { return 0 }
        var ascending: [Int] = []
        ascending.reserveCapacity(line.count)
        var head = 0
        var best = 0.0
        for index in 0..<line.count {
            while ascending.count > head, line[ascending[ascending.count - 1]] >= line[index] {
                ascending.removeLast()
            }
            ascending.append(index)
            if ascending[head] + window <= index { head += 1 }
            if index + 1 >= window { best = max(best, line[ascending[head]]) }
        }
        return best
    }

    /// 격자 한 줄의 값 — 후보가 아니거나 이미 비필름으로 판정된 칸이면 0.
    static func line(
        in grid: FilmBaseSampleGrid,
        neutralBase: Bool,
        excluded: [Bool]?,
        horizontal: Bool,
        position: Int
    ) -> [Double] {
        let length = horizontal ? grid.width : grid.height
        var values = [Double](repeating: 0, count: length)
        for step in 0..<length {
            let index = horizontal
                ? position * grid.width + step
                : step * grid.width + position
            if excluded?[index] == true { continue }
            let sample = grid.samples[index]
            let candidate = FilmBaseEstimator.isFilmBaseCandidate(
                r: sample.color.x, g: sample.color.y, b: sample.color.z,
                neutralBase: neutralBase
            )
            values[step] = candidate ? sample.luma : 0
        }
        return values
    }

    /// 축소본에서 리베이트 띠의 **자리** 를 찾는다. 값은 여기서 읽지 않는다.
    static func locateBand(
        in grid: FilmBaseSampleGrid,
        neutralBase: Bool,
        excluded: [Bool]? = nil
    ) -> Band? {
        var best: Band?
        for horizontal in [true, false] {
            let count = horizontal ? grid.height : grid.width
            let length = horizontal ? grid.width : grid.height
            let window = max(minimumRun, Int(Double(length) * runFraction))
            var levels = [Double](repeating: 0, count: count)
            for position in 0..<count {
                levels[position] = sustainedLevel(
                    line(in: grid, neutralBase: neutralBase, excluded: excluded,
                         horizontal: horizontal, position: position),
                    window: window
                )
            }
            guard let peak = levels.max(), peak > 0 else { continue }
            if let best, peak <= best.level { continue }
            // 같은 띠로 볼 줄들을 최고점 양옆으로 넓힌다. 띠에 기울기가 있으면 유지수준이
            // 줄마다 조금씩 다르므로 한 줄만 잡으면 재는 표본이 너무 적다.
            guard let index = levels.firstIndex(of: peak) else { continue }
            let floorLevel = peak * bandLevelRatio
            var first = index
            var last = index
            while first > 0, levels[first - 1] >= floorLevel { first -= 1 }
            while last + 1 < count, levels[last + 1] >= floorLevel { last += 1 }
            debugLog(String(
                format: "[base-rebate] %@ window=%d peak=%.6f at=%d band=%d..%d of %d\n",
                horizontal ? "rows" : "cols", window, peak, index, first, last, count
            ))
            // 두꺼우면 리베이트가 아니라 장면을 집은 것이다.
            if Double(last - first + 1) > Double(count) * maximumBandFraction { continue }
            best = Band(horizontal: horizontal, first: first, last: last, level: peak)
        }
        return best
    }

    /// 리베이트 띠에서 다시 잰 베이스. 띠가 없으면 nil.
    ///
    /// 두 단계다. **찾기** 는 축소본에서 하고 — 띠의 자리만 알면 되므로 축소본으로 충분하다 —
    /// **재기** 는 찾은 자리에서 원본 해상도로 한다. 축소본에서 읽은 값은 주변과 평균되어
    /// 실제보다 낮기 때문이다.
    ///
    /// - Parameter gateOpen: 문지기가 열렸다 — 고른 값이 장면 높이에 앉아 있다는 뜻이다.
    ///   문지기가 닫혀 있어도 **띠가 얇으면** 원본을 본다. 축소본에서 얇은 띠는 이웃과 평균되어
    ///   절반 값으로 뭉개지고, 추정기가 그 뭉개진 값을 고르면 사진이 어두워지는데 — 그 값은
    ///   장면보다는 밝아서 문지기에 안 걸린다. 얇은 띠는 그 자체로 "여기서 읽은 값은 못 믿는다"
    ///   는 표시이므로, 그때만 원본에서 확인한다.
    /// - Parameter nonFilmExclusion: 추정기가 이미 지은 비필름(백라이트/퍼포레이션) 마스크.
    ///   원본을 읽기로 정한 뒤에만 부른다 — 정상 사진에서 마스크 값을 치르지 않기 위해서다.
    static func rebateBase(
        image: CIImage,
        grid: FilmBaseSampleGrid,
        neutralBase: Bool,
        gateOpen: Bool,
        nonFilmExclusion: () -> [Bool]? = { nil }
    ) -> FilmBaseMeasurement? {
        guard let scouted = locateBand(in: grid, neutralBase: neutralBase) else { return nil }
        let extent = image.extent.integral
        let gridCount = scouted.horizontal ? grid.height : grid.width
        let imageCount = scouted.horizontal ? Int(extent.height) : Int(extent.width)
        let span = scouted.last - scouted.first + 1
        let diluted = span <= 2 && gridCount > 0 && imageCount / gridCount >= 3
        guard gateOpen || diluted else { return nil }
        // 원본을 읽기로 했으면, 추정기가 **이미 비필름으로 판정한 자리**는 빼고 다시 찾는다.
        // 어둑한 웜 백라이트는 후보 판정을 통과하므로(R−B 비율이 살아 있다) 띠 찾기만으로는
        // 필름 베이스와 구분되지 않는다 — 추정기는 그것을 응집 모드 강등으로 이미 걷어냈고,
        // 구조길이 그 판정을 되돌리면 광원이 Dmin 으로 앉아 사진이 새까매진다.
        let excluded = nonFilmExclusion()
        let band = excluded == nil
            ? scouted
            : locateBand(in: grid, neutralBase: neutralBase, excluded: excluded)
        guard let band else { return nil }
        // **색으로는 거르지 않는다.** 홀더를 지난 빛(R/B 1.5)과 C-41 베이스(R/B 4.7)를 가르는
        // 문턱을 두고 싶지만, 코드가 이미 들고 있는 필름 표에 Harman Phoenix 200 (R/B 1.51)
        // 과 ORWO Wolfen NC400 (1.41) 이 있다 — 마스크가 옅은 진짜 컬러 네거티브가 홀더와
        // 같은 값이다. 문턱을 두면 그 필름들이 죽는다. 대신 밝기와 포화만 본다(accept).
        let measured = measureBand(image: image, grid: grid, neutralBase: neutralBase,
                                   band: band, excluded: excluded)
        if let measured {
            debugLog(String(format: "[base-rebate] measured=(%.5f,%.5f,%.5f)\n",
                            measured.rgb.x, measured.rgb.y, measured.rgb.z))
        }
        return measured
    }

    /// 찾은 자리를 **원본 해상도** 로 되돌려 그 안에서 다시 잰다.
    static func measureBand(
        image: CIImage,
        grid: FilmBaseSampleGrid,
        neutralBase: Bool,
        band: Band,
        excluded: [Bool]? = nil
    ) -> FilmBaseMeasurement? {
        let extent = image.extent.integral
        let gridCount = band.horizontal ? grid.height : grid.width
        let imageCount = band.horizontal ? Int(extent.height) : Int(extent.width)
        let across = band.horizontal ? Int(extent.width) : Int(extent.height)
        guard gridCount > 0, imageCount > 0, across > 0 else { return nil }
        let scale = Double(imageCount) / Double(gridCount)
        let begin = Int((Double(band.first) * scale).rounded(.down))
        let end = min(imageCount, Int((Double(band.last + 1) * scale).rounded(.up)))
        guard begin < end else { return nil }

        let total = (end - begin) * across
        let stride = max(1, total / measurementSampleCap)
        var selected: [FilmBaseSample] = []
        selected.reserveCapacity(min(total, measurementSampleCap) + 1)
        var visited = 0
        let chunk = max(1, readChunkPixels / across)
        var alongStart = begin
        while alongStart < end {
            let alongEnd = min(end, alongStart + chunk)
            guard let strip = readStrip(
                image: image, extent: extent, horizontal: band.horizontal,
                alongStart: alongStart, alongEnd: alongEnd, across: across
            ) else { return nil }
            for alongIndex in 0..<(alongEnd - alongStart) {
                for step in 0..<across {
                    defer { visited += 1 }
                    guard visited % stride == 0 else { continue }
                    if let excluded {
                        // 화소가 속한 격자 칸이 비필름이면 건너뛴다 — 띠 안에 섞인 퍼포레이션·
                        // 백라이트 자국이 원본 해상도에서 다시 살아나지 않게 한다.
                        let along = alongStart + alongIndex
                        let cellX = band.horizontal
                            ? step * grid.width / across
                            : along * grid.width / imageCount
                        let cellY = band.horizontal
                            ? along * grid.height / imageCount
                            : step * grid.height / across
                        let cell = min(grid.height - 1, cellY) * grid.width
                            + min(grid.width - 1, cellX)
                        if excluded[cell] { continue }
                    }
                    let offset = (alongIndex * across + step) * 4
                    let color = SIMD3(
                        Double(strip[offset]),
                        Double(strip[offset + 1]),
                        Double(strip[offset + 2])
                    )
                    guard FilmBaseEstimator.isFilmBaseCandidate(
                        r: color.x, g: color.y, b: color.z, neutralBase: neutralBase
                    ) else { continue }
                    selected.append(FilmBaseSample(
                        x: band.horizontal ? step : alongStart + alongIndex,
                        y: band.horizontal ? alongStart + alongIndex : step,
                        color: color
                    ))
                }
            }
            alongStart = alongEnd
        }
        debugLog(String(
            format: "[base-rebate] measure %@ %d..%d of %d  visited=%d stride=%d candidates=%d\n",
            band.horizontal ? "rows" : "cols", begin, end, imageCount,
            visited, stride, selected.count
        ))
        guard selected.count >= 24 else { return nil }
        // 밝은 위 절반의 채널 중앙값 — 기존 경로(connectedBaseComponent)가 쓰는 그 계산이다.
        let keep = max(selected.count / 2, 24)
        let bright = Array(selected.sorted { $0.luma > $1.luma }.prefix(keep))
        return FilmBaseMeasurementBuilder.build(
            method: .rebateBand,
            sampledPixelCount: total,
            candidateCount: selected.count,
            selected: bright,
            gridWidth: band.horizontal ? across : end - begin,
            gridHeight: band.horizontal ? end - begin : across
        )
    }

    /// 원본 해상도의 띠 조각을 linear RGBAf 로 읽는다.
    ///
    /// `alongStart..<alongEnd` 는 **격자와 같은 위→아래(행) / 왼→오른쪽(열) 순서**다.
    /// CIImage 는 y-up 이고 `render(toBitmap:)` 은 첫 행이 rect 의 위쪽이므로, 행 띠만
    /// y 를 뒤집어 자른다(열 띠의 x 는 뒤집히지 않는다).
    private static func readStrip(
        image: CIImage,
        extent: CGRect,
        horizontal: Bool,
        alongStart: Int,
        alongEnd: Int,
        across: Int
    ) -> [Float]? {
        guard let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        let count = alongEnd - alongStart
        let rect: CGRect = horizontal
            ? CGRect(x: extent.minX,
                     y: extent.maxY - CGFloat(alongEnd),
                     width: CGFloat(across),
                     height: CGFloat(count))
            : CGRect(x: extent.minX + CGFloat(alongStart),
                     y: extent.minY,
                     width: CGFloat(count),
                     height: CGFloat(across))
        let width = Int(rect.width)
        let height = Int(rect.height)
        guard width > 0, height > 0 else { return nil }
        var bitmap = [Float](repeating: 0, count: width * height * 4)
        SamplingContextPool.context(workingColorSpace: linear).render(
            image,
            toBitmap: &bitmap,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: rect,
            format: .RGBAf,
            colorSpace: linear
        )
        if horizontal { return bitmap }
        // 열 띠는 (x, y) 를 (along, step) 순서로 다시 세운다. 격자의 열 스캔과 같은 순서로
        // 방문해야 건너뛰기(stride)가 두 판본에서 같은 표본을 남긴다.
        var transposed = [Float](repeating: 0, count: bitmap.count)
        for alongIndex in 0..<count {
            for step in 0..<across {
                // bitmap 의 첫 행은 rect 의 위쪽 = 원본의 마지막 행이다.
                let row = across - 1 - step
                let source = (row * width + alongIndex) * 4
                let destination = (alongIndex * across + step) * 4
                transposed[destination] = bitmap[source]
                transposed[destination + 1] = bitmap[source + 1]
                transposed[destination + 2] = bitmap[source + 2]
                transposed[destination + 3] = bitmap[source + 3]
            }
        }
        return transposed
    }

    /// 다시 잰 값을 받아들일지.
    ///
    /// 문지기는 넉넉하게 의심하므로(멀쩡한 사진도 걸린다) 채택은 여기서 깐깐하게 본다.
    /// 받아들이지 않으면 기존 값이 그대로 남는다 — 새 경로가 아무 답도 못 내는 사진은
    /// 구조적으로 지금과 똑같이 동작한다.
    ///
    /// 다시 잰 값이 지금 값보다 **뚜렷하게** 밝아야 받는다. 띠 찾기를 늘 돌리게 되면서
    /// 멀쩡한 사진에서도 같은 자리를 다시 재게 되는데, 그때 나오는 값은 지금 값과 사실상
    /// 같다. 여유 없이 "밝기만 하면" 으로 두면 그 미세한 차이로 멀쩡한 사진이 바뀐다.
    static func accept(rebate: SIMD3<Double>, current: SIMD3<Double>) -> Bool {
        for channel in [rebate.x, rebate.y, rebate.z] {
            guard channel.isFinite, channel > 0, channel < 1 else { return false }
        }
        guard current.x.isFinite, current.y.isFinite, current.z.isFinite else { return false }
        let now = (current.x + current.y + current.z) / 3
        let next = (rebate.x + rebate.y + rebate.z) / 3
        guard next >= now * acceptanceRatio else { return false }
        return rebate.x < saturationCut && rebate.y < saturationCut && rebate.z < saturationCut
    }

    private static func debugLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["NEGA_DEBUG"] != nil else { return }
        FileHandle.standardError.write(Data(message.utf8))
    }
}
