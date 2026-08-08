import CoreGraphics
import Foundation
import ImageIO

/// 프리뷰의 실제 물리 크기를 아는 상태에서 필름 프레임을 찾는다.
///
/// 기존 검출기는 프레임 비율만 알고 에지 세기로 경계를 추측한다. 그래서 필름 내용에 휘둘리고,
/// 하늘처럼 평평한 컷이나 미노광 컷에서 무너진다. 평판 프리뷰는 스캔한 영역이 몇 mm인지 이미
/// 알고 있으므로, 36×24mm 가 몇 px인지 정확히 계산할 수 있다. 이 검출기는 그 사전지식을 쓴다.
///
/// 순서는 홀더 구조를 그대로 따라간다.
///   1. 투과 마스크 — 홀더 마스크는 불투명이고 필름은 빛을 통과시킨다.
///   2. 열 투영으로 슬롯(스트립이 놓이는 세로 창)을 찾는다.
///   3. 슬롯 폭을 규격과 대조해 온전한 슬롯만 남긴다. 홀더가 스캔 영역보다 넓어 양끝이 잘린
///      경우를 이 단계에서 걸러낸다 — 홀더 종류를 가정하지 않고 폭만 본다.
///   4. 행 투영으로 슬롯 안의 구획(연속한 필름 구간)을 찾는다.
///   5. 구획마다 프레임 피치로 격자를 맞춘다.
///
/// 5단계가 핵심이다. 컷 경계를 하나씩 믿지 않고 "일정 간격으로 반복된다"는 성질로 한꺼번에
/// 맞춘다. 35mm 이송 피치는 카메라가 달라도 거의 흔들리지 않으므로 강한 단서다. 덕분에 미노광
/// 컷(경계가 안 보임)이나 평평한 컷이 있어도 격자가 채워준다.
public enum FlatbedFrameGridDetector {

    /// 검출에 쓸 프리뷰 한 장. 밝기는 0...1 로 정규화된 행 우선 배열이다.
    public struct Preview: Sendable {
        public let luminance: [Double]
        public let width: Int
        public let height: Int
        /// 이 프리뷰가 담고 있는 실제 영역(mm).
        public let physicalSize: CGSize

        public init(luminance: [Double], width: Int, height: Int, physicalSize: CGSize) {
            self.luminance = luminance
            self.width = width
            self.height = height
            self.physicalSize = physicalSize
        }

        var pixelsPerMillimeterX: Double { Double(width) / physicalSize.width }
        var pixelsPerMillimeterY: Double { Double(height) / physicalSize.height }

        /// 프리뷰 파일에서 밝기만 뽑아 온다. 검출은 프레임 사이 여백을 찾는 일이라 색은 쓰지
        /// 않는다. 축소 한도를 낮게 잡으면 안 된다 — 35mm 프레임 사이 여백은 2mm 뿐이라
        /// 1024px 로 줄이면 뭉개져서 컷을 놓친다(실측에서 12개 중 4개까지 떨어졌다).
        public init?(url: URL, physicalSize: CGSize, maxAnalysisDimension: Int = 2_048) {
            guard physicalSize.width > 0, physicalSize.height > 0,
                  maxAnalysisDimension >= 128,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(
                      source,
                      0,
                      [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: false,
                          kCGImageSourceThumbnailMaxPixelSize: maxAnalysisDimension,
                      ] as CFDictionary
                  ) else { return nil }
            self.init(image: image, physicalSize: physicalSize)
        }

        public init?(image: CGImage, physicalSize: CGSize) {
            let width = image.width
            let height = image.height
            guard width > 0, height > 0,
                  physicalSize.width > 0, physicalSize.height > 0 else { return nil }
            var gray = [UInt8](repeating: 0, count: width * height)
            // 선형 그레이로 그리면 감마가 풀려 어두운 쪽이 더 눌린다. 홀더와 필름을 가르는
            // 임계가 그만큼 흔들리므로, 스캔이 담고 있는 표시 감마 그대로 읽는다.
            guard let space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
                  let context = gray.withUnsafeMutableBytes({ buffer -> CGContext? in
                      CGContext(
                          data: buffer.baseAddress,
                          width: width,
                          height: height,
                          bitsPerComponent: 8,
                          bytesPerRow: width,
                          space: space,
                          bitmapInfo: CGImageAlphaInfo.none.rawValue
                      )
                  }) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            self.init(
                luminance: gray.map { Double($0) / 255 },
                width: width,
                height: height,
                physicalSize: physicalSize
            )
        }
    }

    /// 프레임 사이 여백. 35mm 는 퍼포레이션 이송이 정하므로 사실상 고정이고, 120 은 카메라
    /// 이송 기구에 달려 있어 표준이 없다. 그래서 120 은 피치 탐색 범위를 넓게 잡는다.
    static func gapRangeMM(for format: FilmFrameFormat) -> ClosedRange<Double> {
        format.is35mm ? 1.0...3.0 : 2.0...9.0
    }

    /// 프리뷰 파일에서 바로 검출한다. `physicalSize` 는 그 스캔이 담은 실제 영역(mm)이다.
    public static func detect(
        url: URL,
        physicalSize: CGSize,
        frameFormat: FilmFrameFormat,
        maxAnalysisDimension: Int = 2_048
    ) -> [FlatbedFrameDetection] {
        guard let preview = Preview(
            url: url,
            physicalSize: physicalSize,
            maxAnalysisDimension: maxAnalysisDimension
        ) else { return [] }
        return detect(preview: preview, frameFormat: frameFormat)
    }

    public static func detect(
        preview: Preview,
        frameFormat: FilmFrameFormat
    ) -> [FlatbedFrameDetection] {
        guard preview.width > 0,
              preview.height > 0,
              preview.luminance.count == preview.width * preview.height,
              preview.physicalSize.width > 0,
              preview.physicalSize.height > 0 else { return [] }

        guard let found = slotRanges(preview: preview, format: frameFormat) else { return [] }
        let slots = found.slots
        let levels = found.levels

        var detections: [FlatbedFrameDetection] = []
        for (row, slot) in slots.enumerated() {
            let bands = filmBands(
                preview: preview,
                slot: slot,
                format: frameFormat,
                levels: levels
            )
            var column = 0
            for band in bands {
                for rect in frames(
                    in: band,
                    slot: slot,
                    preview: preview,
                    format: frameFormat
                ) {
                    detections.append(FlatbedFrameDetection(
                        normalizedRect: rect,
                        straightenAngle: 0,
                        confidence: 1,
                        row: row,
                        column: column
                    ))
                    column += 1
                }
            }
        }
        return detections
    }

    // MARK: - 1. 밝기 수준

    /// 홀더와 필름의 밝기 수준. 두 값 사이의 상대 위치로 판정하므로 필름 종류나
    /// 노출이 달라도 같은 기준이 선다.
    ///
    struct TransmissionLevels: Equatable, Sendable {
        let holder: Double
        let film: Double

        /// 필름과 홀더를 가르는 값. 필름 쪽으로 1/4 지점에 둔다 — 밀도가 높은 컷은 필름
        /// 수준에서 홀더 쪽으로 크게 밀리므로, 한가운데에 두면 그런 컷이 통째로 넘어간다.
        var filmFloor: Double { holder + (film - holder) * 0.25 }

    }

    /// 1차원 프로파일을 두 무리로 가르는 값(판별분석). **픽셀 히스토그램에 쓰면 안 된다.**
    ///
    /// 실측(GT-X900, 정품 3슬롯 홀더, 컬러 네거티브)에서 프리뷰 픽셀의 중앙값은 0.000 이었다.
    /// 홀더가 화면의 절반을 넘고, 밀도가 높은 컷도 8-bit 에서 0 으로 잘려 나가기 때문이다.
    /// 그 히스토그램에 판별분석을 걸면 경계가 홀더와 필름 사이가 아니라 **필름 분포 한가운데**
    /// (0.12~0.50)에 서고, 필름 대부분이 불투명으로 판정된다. 실제로 100dpi 프리뷰에서 투과로
    /// 남은 픽셀이 0.76% 뿐이어서 슬롯을 하나도 찾지 못했다.
    ///
    /// 열 평균 프로파일에는 두 무리가 그대로 남는다 — 홀더 리브 열은 0.002, 필름 열은 0.12 로
    /// 25/100/150dpi 어디서나 같았다. 그래서 판별분석은 **프로파일에만** 쓴다.
    static func splitThreshold(of profile: [Double]) -> Double? {
        guard let low = profile.min(), let high = profile.max(), high - low > 1e-6 else {
            return nil
        }
        let binCount = 128
        var histogram = [Int](repeating: 0, count: binCount)
        for value in profile {
            let bin = Int((value - low) / (high - low) * Double(binCount - 1))
            histogram[min(binCount - 1, max(0, bin))] += 1
        }
        let total = profile.count
        let sum = histogram.enumerated().reduce(0.0) { $0 + Double($1.offset * $1.element) }
        var backgroundSum = 0.0
        var backgroundCount = 0
        var best = (variance: -1.0, bin: 0)
        for bin in 0..<binCount {
            backgroundCount += histogram[bin]
            if backgroundCount == 0 { continue }
            let foregroundCount = total - backgroundCount
            if foregroundCount == 0 { break }
            backgroundSum += Double(bin * histogram[bin])
            let backgroundMean = backgroundSum / Double(backgroundCount)
            let foregroundMean = (sum - backgroundSum) / Double(foregroundCount)
            let delta = backgroundMean - foregroundMean
            let variance = Double(backgroundCount) * Double(foregroundCount) * delta * delta
            if variance > best.variance { best = (variance, bin) }
        }
        // 고른 bin 까지가 어두운 무리다. bin 경계를 그대로 쓰면 그 bin 에 속한 값이 비교에서
        // 간발로 살아남는다.
        return low + (Double(best.bin) + 0.5) / Double(binCount) * (high - low)
    }

    // MARK: - 2~3. 슬롯

    /// 슬롯은 홀더가 필름을 보여주려고 뚫어 둔 세로 창이다. 열마다 밝기를 평균하면 창이 봉우리,
    /// 홀더 리브가 골로 나온다.
    static func slotRanges(
        preview: Preview,
        format: FilmFrameFormat
    ) -> (slots: [Range<Int>], levels: TransmissionLevels)? {
        var columnMean = [Double](repeating: 0, count: preview.width)
        for y in 0..<preview.height {
            let rowStart = y * preview.width
            for x in 0..<preview.width { columnMean[x] += preview.luminance[rowStart + x] }
        }
        for x in 0..<preview.width { columnMean[x] /= Double(preview.height) }

        // 열 안에서 밝기가 얼마나 흔들리는지. 필름에는 그림이 들어 있어 흔들리고, 홀더나
        // 빈 바탕은 균일하다. **어느 쪽이 필름인지는 밝기가 아니라 이 값이 정한다.**
        var columnDeviation = [Double](repeating: 0, count: preview.width)
        for x in 0..<preview.width {
            var sumSquares = 0.0
            for y in 0..<preview.height {
                let delta = preview.luminance[y * preview.width + x] - columnMean[x]
                sumSquares += delta * delta
            }
            columnDeviation[x] = (sumSquares / Double(preview.height)).squareRoot()
        }

        guard let threshold = splitThreshold(of: columnMean) else { return nil }
        let candidates = runs(of: columnMean) { $0 > threshold }
        // 슬롯이 보여주는 것은 필름 폭이 아니라 이미지 영역이다. 스캔 영역 밖으로 잘린 슬롯은
        // 폭이 규격에 못 미치므로 여기서 떨어진다. 홀더 종류는 보지 않는다.
        let expected = expectedSlotWidthMM(format)
        let pixelsPerMM = preview.pixelsPerMillimeterX
        let sized = candidates.filter { range in
            let widthMM = Double(range.count) / pixelsPerMM
            return widthMM >= expected * 0.75 && widthMM <= expected * 1.6
        }

        // **슬롯 안에는 그림이 있어야 한다.** 폭만 보면 규격에 맞는 균일한 띠가 그대로
        // 통과한다 — 필름을 흰 바탕 위에 둔 프리뷰에서는 바탕의 좌우 여백이 규격 폭과
        // 우연히 맞아떨어져 슬롯으로 뽑히고, 그 안에서 없는 격자를 만들어 낸다. 필름 열은
        // 열 안에서 밝기가 흔들리고(실측 0.09) 빈 바탕은 균일하므로(0.00) 그것으로 가른다.
        let deviationLevel = columnDeviation.reduce(0, +) / Double(max(1, columnDeviation.count))
        let accepted = sized.filter { range in
            let deviation = range.reduce(0) { $0 + columnDeviation[$1] } / Double(range.count)
            return deviation > deviationLevel * 0.25
        }
        guard !accepted.isEmpty else { return nil }

        // 두 무리의 밝기 수준은 이 단계에서 그대로 얻는다. 행 판정에 다시 판별분석을 걸면
        // 안 된다 — 슬롯 안은 거의 전부 필름이라 낮은 무리가 없어서, 경계가 필름 분포
        // 한가운데에 서고 구획이 하나도 남지 않는다(실측에서 임계 0.28~0.50).
        let holderSamples = columnMean.filter { $0 <= threshold }
        let filmSamples = accepted.flatMap { $0.map { columnMean[$0] } }
        guard !holderSamples.isEmpty, !filmSamples.isEmpty else { return nil }
        let levels = TransmissionLevels(
            holder: holderSamples.reduce(0, +) / Double(holderSamples.count),
            film: filmSamples.reduce(0, +) / Double(filmSamples.count)
        )
        return (accepted, levels)
    }

    /// 스트립을 세로로 놓고 스캔하면 슬롯 폭에는 프레임의 짧은 변이 보인다.
    static func expectedSlotWidthMM(_ format: FilmFrameFormat) -> Double {
        min(format.stripWidthMM, format.stripHeightMM)
    }

    // MARK: - 4. 구획

    /// 슬롯 안에서 필름이 실제로 놓인 세로 구간. 한 슬롯이 위아래로 나뉜 홀더도 있으므로
    /// 개수를 가정하지 않고 끊어진 구간을 그대로 돌려준다.
    static func filmBands(
        preview: Preview,
        slot: Range<Int>,
        format: FilmFrameFormat,
        levels: TransmissionLevels
    ) -> [Range<Int>] {
        var rowMean = [Double](repeating: 0, count: preview.height)
        for y in 0..<preview.height {
            let rowStart = y * preview.width
            var sum = 0.0
            for x in slot { sum += preview.luminance[rowStart + x] }
            rowMean[y] = sum / Double(slot.count)
        }
        // 과노광된 컷은 홀더만큼 어두워서 필름 바닥선 아래로 내려간다. 그대로 두면 한 스트립이
        // 여러 조각으로 끊어져 격자가 조각마다 따로 서고 컷이 통째로 누락된다. 컷 하나보다
        // 짧은 틈은 필름이 이어진 것으로 보고 메운다.
        let frameLengthMM = max(format.stripWidthMM, format.stripHeightMM)
        // 메워야 할 최악의 틈은 컷 하나가 통째로 불투명한 경우다. 그보다 조금 넉넉히 잡는다.
        let bridgeRows = Int(frameLengthMM * 1.2 * preview.pixelsPerMillimeterY)
        let merged = bridging(runs(of: rowMean) { $0 > levels.filmFloor }, maximumGap: bridgeRows)

        // 한 컷도 못 담는 구간은 잡음이다.
        let minimumMM = min(format.stripWidthMM, format.stripHeightMM) * 0.8
        let minimumRows = Int(minimumMM * preview.pixelsPerMillimeterY)
        return merged.filter { $0.count >= max(4, minimumRows) }
    }

    // MARK: - 5. 격자

    /// 구획을 프레임 피치로 나눈다. 경계 하나하나를 믿지 않고 반복 주기로 맞추므로, 경계가
    /// 안 보이는 컷이 섞여 있어도 자리를 지킨다.
    static func frames(
        in band: Range<Int>,
        slot: Range<Int>,
        preview: Preview,
        format: FilmFrameFormat
    ) -> [CGRect] {
        let pixelsPerMMY = preview.pixelsPerMillimeterY
        let frameLengthMM = max(format.stripWidthMM, format.stripHeightMM)
        let bandLengthMM = Double(band.count) / pixelsPerMMY
        guard bandLengthMM >= frameLengthMM * 0.8 else { return [] }

        let score = gapScore(band: band, slot: slot, preview: preview)
        let gapRange = gapRangeMM(for: format)
        var best: (score: Double, pitch: Double, phase: Double, count: Int)?

        var gapMM = gapRange.lowerBound
        while gapMM <= gapRange.upperBound + 1e-9 {
            let pitchMM = frameLengthMM + gapMM
            let pitch = pitchMM * pixelsPerMMY
            let gap = gapMM * pixelsPerMMY
            guard pitch > 1 else { gapMM += 0.25; continue }
            // 몇 컷이 들어가는지는 점수로 고르지 않는다. 구획 길이와 피치가 정하는 값이고,
            // 점수로 고르게 두면 잘 맞는 경계 몇 개만 집는 쪽이 이겨 컷이 통째로 누락된다.
            // 스트립이 구획을 꽉 채우지 않는 경우만 감안해 한 칸씩 아래위로 살핀다.
            let nominal = Int((Double(band.count) / pitch).rounded())
            guard nominal >= 1 else { gapMM += 0.25; continue }
            for count in max(1, nominal - 1)...(nominal + 1) {
                let span = pitch * Double(count)
                guard span <= Double(band.count) + pitch * 0.5 else { continue }
                // 구획은 이미 필름이 놓인 구간을 정확히 집어낸 결과다. 첫 컷은 그 시작에서
                // 출발하므로 위상까지 점수로 고르지 않는다. 열어 두면 격자가 구획 안쪽으로
                // 밀려서 첫 컷과 끝 컷이 잘린다. 남는 여유만큼만 살짝 훑는다.
                let slack = max(0, Double(band.count) - span)
                var phase = 0.0
                while phase <= slack {
                    var total = 0.0
                    var samples = 0
                    for index in 0...count {
                        // 격자 경계는 컷이 시작하는 자리이고 여백은 그 바로 앞에 있다. 경계에서
                        // 그대로 재면 컷 안쪽을 보게 되므로 여백 한가운데로 옮겨서 잰다.
                        let boundary = phase + pitch * Double(index)
                        let position = boundary - gap * 0.5
                        guard position >= 0, position < Double(score.count) else { continue }
                        total += score[Int(position)]
                        samples += 1
                    }
                    if samples > 1 {
                        // 경계 점수의 평균만 보면 컷을 적게 잡을수록 유리하다 — 잘 맞는 경계
                        // 두 개만 고르면 되기 때문이다. 구획을 얼마나 덮는지를 함께 봐서
                        // 물리적으로 들어갈 수 있는 만큼 채우게 한다.
                        let covered = frameLengthMM * pixelsPerMMY * Double(count)
                        let coverage = min(1, covered / Double(band.count))
                        // 구획 밖으로 나간 경계는 0점으로 친다. 유효한 것만 평균 내면 격자를
                        // 밖으로 밀어 표본을 줄이는 쪽이 이겨 첫 컷과 끝 컷이 잘린다.
                        let value = total / Double(count + 1) * coverage
                        if best == nil || value > best!.score {
                            best = (value, pitch, phase, count)
                        }
                    }
                    phase += 1
                }
            }
            gapMM += 0.25
        }

        guard let fit = best else { return [] }
        let frameLength = frameLengthMM * pixelsPerMMY
        var rects: [CGRect] = []
        for index in 0..<fit.count {
            let start = Double(band.lowerBound) + fit.phase + fit.pitch * Double(index)
            let clampedStart = max(Double(band.lowerBound), start)
            let clampedEnd = min(Double(band.upperBound + 1), start + frameLength)
            // 절반도 안 들어온 컷은 내보내지 않는다. 잘린 조각을 프레임으로 주면 본 스캔이
            // 엉뚱한 영역을 찍는다.
            guard clampedEnd - clampedStart >= frameLength * 0.6 else { continue }
            rects.append(CGRect(
                x: Double(slot.lowerBound) / Double(preview.width),
                y: clampedStart / Double(preview.height),
                width: Double(slot.count) / Double(preview.width),
                height: (clampedEnd - clampedStart) / Double(preview.height)
            ))
        }
        return rects
    }

    /// 프레임 사이 여백을 얼마나 닮았는지. 여백은 노광되지 않아 밝기가 한쪽으로 몰리고 가로로
    /// 균일하다. 밝기만 보면 하늘 같은 평평한 컷을 여백으로 착각하므로 균일함을 함께 본다.
    ///
    /// 네거티브는 여백이 필름 베이스라 밝고, 슬라이드는 최대 밀도라 어둡다. 어느 쪽인지 미리
    /// 정하지 않고 두 방향을 모두 재서 더 뚜렷한 쪽을 고른다.
    static func gapScore(band: Range<Int>, slot: Range<Int>, preview: Preview) -> [Double] {
        // 슬롯 가장자리는 홀더 그림자가 섞이므로 안쪽만 본다.
        let inset = max(1, slot.count / 12)
        let sampled = (slot.lowerBound + inset)..<(slot.upperBound - inset)
        guard sampled.count > 2 else { return [Double](repeating: 0, count: band.count) }

        var means = [Double](repeating: 0, count: band.count)
        var deviations = [Double](repeating: 0, count: band.count)
        for (offset, y) in band.enumerated() {
            let rowStart = y * preview.width
            var sum = 0.0
            var sumSquares = 0.0
            for x in sampled {
                let value = preview.luminance[rowStart + x]
                sum += value
                sumSquares += value * value
            }
            let count = Double(sampled.count)
            let mean = sum / count
            means[offset] = mean
            deviations[offset] = max(0, sumSquares / count - mean * mean).squareRoot()
        }

        // 편차의 폭이 편차 수준에 견줘 작으면 그건 구조가 아니라 잡음이다. 그대로 정규화하면
        // 의미 없는 흔들림이 만점과 0점으로 갈라져 격자를 엉뚱한 자리에 세운다.
        let deviationLow = deviations.min() ?? 0
        let deviationHigh = deviations.max() ?? 0
        let deviationLevel = deviations.isEmpty
            ? 0
            : deviations.reduce(0, +) / Double(deviations.count)
        let flat = (deviationHigh - deviationLow) > deviationLevel * 0.5
            ? inverted(normalized(deviations))
            : [Double](repeating: 1, count: deviations.count)
        let bright = normalized(means)
        let dark = inverted(bright)
        let brightScore = zip(bright, flat).map(*)
        let darkScore = zip(dark, flat).map(*)
        // 봉우리가 더 도드라지는 쪽이 실제 여백이다.
        return contrast(of: brightScore) >= contrast(of: darkScore) ? brightScore : darkScore
    }

    // MARK: - 보조

    static func runs(
        of profile: [Double],
        matching isIncluded: (Double) -> Bool
    ) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start: Int?
        for (index, value) in profile.enumerated() {
            if isIncluded(value), start == nil { start = index }
            if !isIncluded(value), let begin = start {
                result.append(begin..<index)
                start = nil
            }
        }
        if let begin = start { result.append(begin..<profile.count) }
        return result
    }

    /// 사이가 `maximumGap` 이하로 붙은 구간을 하나로 잇는다.
    static func bridging(_ ranges: [Range<Int>], maximumGap: Int) -> [Range<Int>] {
        guard maximumGap > 0, var current = ranges.first else { return ranges }
        var result: [Range<Int>] = []
        for range in ranges.dropFirst() {
            if range.lowerBound - current.upperBound <= maximumGap {
                current = current.lowerBound..<range.upperBound
            } else {
                result.append(current)
                current = range
            }
        }
        result.append(current)
        return result
    }

    /// 폭이 사실상 0인 신호는 정규화하지 않는다. 그대로 늘리면 부동소수 오차가 만점과
    /// 0점으로 갈라져 없는 구조를 만들어 낸다.
    static func normalized(_ values: [Double]) -> [Double] {
        guard let low = values.min(), let high = values.max(), high - low > 1e-9 else {
            return [Double](repeating: 0, count: values.count)
        }
        return values.map { ($0 - low) / (high - low) }
    }

    static func inverted(_ values: [Double]) -> [Double] { values.map { 1 - $0 } }

    /// 상위 구간이 얼마나 솟아 있는지. 여백 신호가 뚜렷할수록 커진다.
    static func contrast(of values: [Double]) -> Double {
        guard values.count > 4 else { return 0 }
        let sorted = values.sorted()
        let high = sorted[Int(Double(sorted.count) * 0.95)]
        let median = sorted[sorted.count / 2]
        return high - median
    }
}
