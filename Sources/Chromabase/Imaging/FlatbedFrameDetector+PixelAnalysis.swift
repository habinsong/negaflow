import CoreGraphics
import Foundation

extension Detector {
    func equalizedHorizontalGradientRowMeans() -> [Double] {
        guard image.width > 1 else { return [] }
        var result = [Double](repeating: 0, count: image.height)
        let lookupTables = image.channelEqualizationLookupTables()
        for y in 0..<image.height {
            var sum = 0
            for x in 0..<(image.width - 1) {
                sum += image.equalizedChannelMaximumDifference(
                    x0: x,
                    y0: y,
                    x1: x + 1,
                    y1: y,
                    lookupTables: lookupTables
                )
            }
            result[y] = Double(sum) / Double((image.width - 1) * 255)
        }
        return result
    }

    func verticalGradientRowQuantiles(quantile: Double) -> [Double] {
        guard image.height > 1 else { return [] }
        var result = [Double](repeating: 0, count: image.height)
        var histogram = [Int](repeating: 0, count: 256)
        for y in 0..<(image.height - 1) {
            histogram.withUnsafeMutableBufferPointer { buffer in
                buffer.initialize(repeating: 0)
            }
            for x in 0..<image.width {
                let difference = image.channelMaximumDifference(
                    x0: x,
                    y0: y,
                    x1: x,
                    y1: y + 1
                )
                histogram[difference] += 1
            }
            result[y] = Double(histogramQuantile(
                histogram,
                sampleCount: image.width,
                quantile: quantile
            )) / 255.0
        }
        result[image.height - 1] = result[max(0, image.height - 2)]
        return result
    }

    func horizontalGradientColumnQuantiles(
        yRange: Range<Int>,
        quantile: Double
    ) -> [Double] {
        guard image.width > 1, !yRange.isEmpty else { return [] }
        var result = [Double](repeating: 0, count: image.width - 1)
        var histogram = [Int](repeating: 0, count: 256)
        for x in 0..<(image.width - 1) {
            histogram.withUnsafeMutableBufferPointer { buffer in
                buffer.initialize(repeating: 0)
            }
            for y in yRange {
                let difference = image.channelMaximumDifference(
                    x0: x,
                    y0: y,
                    x1: x + 1,
                    y1: y
                )
                histogram[difference] += 1
            }
            result[x] = Double(histogramQuantile(
                histogram,
                sampleCount: yRange.count,
                quantile: quantile
            )) / 255.0
        }
        return result
    }

    func traceHorizontalEdge(
        around expectedY: Int,
        searchRadius: Int
    ) -> [(Double, Double)] {
        let sampleStep = max(8, image.width / 64)
        let xRadius = max(1, sampleStep / 8)
        var samples: [(Double, Double)] = []
        for x in stride(from: sampleStep / 2, to: image.width, by: sampleStep) {
            let lowerY = max(0, expectedY - searchRadius)
            let upperY = min(image.height - 1, expectedY + searchRadius + 1)
            guard lowerY < upperY else { continue }
            var bestY = lowerY
            var bestScore = -1
            for y in lowerY..<upperY {
                var score = 0
                let lowerX = max(0, x - xRadius)
                let upperX = min(image.width, x + xRadius + 1)
                for sampleX in lowerX..<upperX {
                    score += image.channelMaximumDifference(
                        x0: sampleX,
                        y0: y,
                        x1: sampleX,
                        y1: y + 1
                    )
                }
                if score > bestScore {
                    bestScore = score
                    bestY = y
                }
            }
            samples.append((Double(x), Double(bestY)))
        }
        return samples
    }

    func traceVerticalEdge(
        around expectedX: Int,
        yRange: Range<Int>,
        searchRadius: Int
    ) -> [(Double, Double)] {
        let sampleStep = max(6, yRange.count / 32)
        let yRadius = max(1, sampleStep / 8)
        var samples: [(Double, Double)] = []
        for y in stride(from: yRange.lowerBound + sampleStep / 2, to: yRange.upperBound, by: sampleStep) {
            let lowerX = max(0, expectedX - searchRadius)
            let upperX = min(image.width - 1, expectedX + searchRadius + 1)
            guard lowerX < upperX else { continue }
            var bestX = lowerX
            var bestScore = -1
            for x in lowerX..<upperX {
                var score = 0
                let lowerY = max(yRange.lowerBound, y - yRadius)
                let upperY = min(yRange.upperBound, y + yRadius + 1)
                for sampleY in lowerY..<upperY {
                    score += image.channelMaximumDifference(
                        x0: x,
                        y0: sampleY,
                        x1: x + 1,
                        y1: sampleY
                    )
                }
                if score > bestScore {
                    bestScore = score
                    bestX = x
                }
            }
            samples.append((Double(bestX), Double(y)))
        }
        return samples
    }
}

struct AnalysisImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(image: CGImage, maxDimension: Int) {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        let scale = min(1, Double(maxDimension) / Double(max(sourceWidth, sourceHeight)))
        let targetWidth = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let targetHeight = max(1, Int((Double(sourceHeight) * scale).rounded()))
        var storage = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
        let rendered = storage.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: baseAddress,
                      width: targetWidth,
                      height: targetHeight,
                      bitsPerComponent: 8,
                      bytesPerRow: targetWidth * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                          | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
            )
            return true
        }
        guard rendered else { return nil }
        width = targetWidth
        height = targetHeight
        pixels = storage
    }

    private init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func rotatedCounterClockwise() -> AnalysisImage {
        let targetWidth = height
        let targetHeight = width
        var storage = [UInt8](repeating: 0, count: pixels.count)
        for y in 0..<height {
            for x in 0..<width {
                let source = (y * width + x) * 4
                let targetX = y
                let targetY = width - 1 - x
                let target = (targetY * targetWidth + targetX) * 4
                storage[target..<(target + 4)] = pixels[source..<(source + 4)]
            }
        }
        return AnalysisImage(width: targetWidth, height: targetHeight, pixels: storage)
    }

    func cropped(to rect: CGRect) -> AnalysisImage? {
        let minimumX = max(0, Int(rect.minX.rounded(.down)))
        let minimumY = max(0, Int(rect.minY.rounded(.down)))
        let maximumX = min(width, Int(rect.maxX.rounded(.up)))
        let maximumY = min(height, Int(rect.maxY.rounded(.up)))
        guard maximumX > minimumX, maximumY > minimumY else { return nil }

        let targetWidth = maximumX - minimumX
        let targetHeight = maximumY - minimumY
        var storage = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
        for targetY in 0..<targetHeight {
            let sourceStart = ((minimumY + targetY) * width + minimumX) * 4
            let sourceEnd = sourceStart + targetWidth * 4
            let targetStart = targetY * targetWidth * 4
            storage[targetStart..<(targetStart + targetWidth * 4)] =
                pixels[sourceStart..<sourceEnd]
        }
        return AnalysisImage(width: targetWidth, height: targetHeight, pixels: storage)
    }

    func rotated(byDegrees degrees: Double) -> AnalysisImage {
        guard degrees.isFinite, abs(degrees) > 0.000_001 else { return self }
        let radians = degrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        let centerX = Double(width - 1) / 2
        let centerY = Double(height - 1) / 2
        let background = borderBackgroundChannels() ?? [255, 255, 255]
        var storage = [UInt8](repeating: 0, count: pixels.count)

        for y in 0..<height {
            let centeredY = Double(y) - centerY
            for x in 0..<width {
                let centeredX = Double(x) - centerX
                let sourceX = cosine * centeredX + sine * centeredY + centerX
                let sourceY = -sine * centeredX + cosine * centeredY + centerY
                let target = (y * width + x) * 4
                let roundedX = Int(sourceX.rounded())
                let roundedY = Int(sourceY.rounded())
                if roundedX >= 0, roundedX < width, roundedY >= 0, roundedY < height {
                    let source = (roundedY * width + roundedX) * 4
                    storage[target..<(target + 4)] = pixels[source..<(source + 4)]
                } else {
                    storage[target] = background[0]
                    storage[target + 1] = background[1]
                    storage[target + 2] = background[2]
                    storage[target + 3] = 255
                }
            }
        }
        return AnalysisImage(width: width, height: height, pixels: storage)
    }

    func resized(maxDimension: Int) -> AnalysisImage {
        guard maxDimension > 0, max(width, height) > maxDimension else { return self }
        let scale = Double(maxDimension) / Double(max(width, height))
        let targetWidth = max(1, Int((Double(width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(height) * scale).rounded()))
        var storage = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
        for targetY in 0..<targetHeight {
            let sourceY = min(
                height - 1,
                Int((Double(targetY) / Double(targetHeight) * Double(height)).rounded(.down))
            )
            for targetX in 0..<targetWidth {
                let sourceX = min(
                    width - 1,
                    Int((Double(targetX) / Double(targetWidth) * Double(width)).rounded(.down))
                )
                let source = (sourceY * width + sourceX) * 4
                let target = (targetY * targetWidth + targetX) * 4
                storage[target..<(target + 4)] = pixels[source..<(source + 4)]
            }
        }
        return AnalysisImage(width: targetWidth, height: targetHeight, pixels: storage)
    }

    func foregroundBounds() -> CGRect? {
        guard let background = borderBackgroundChannels() else { return nil }
        let borderStride = max(1, min(width, height) / 128)
        var borderDistances: [Double] = []
        for x in stride(from: 0, to: width, by: borderStride) {
            borderDistances.append(backgroundDistance(x: x, y: 0, background: background))
            borderDistances.append(
                backgroundDistance(x: x, y: height - 1, background: background)
            )
        }
        for y in stride(from: borderStride, to: height - 1, by: borderStride) {
            borderDistances.append(backgroundDistance(x: 0, y: y, background: background))
            borderDistances.append(
                backgroundDistance(x: width - 1, y: y, background: background)
            )
        }
        let threshold = max(12, median(borderDistances) * 3 + 6)
        let blockSize = max(2, max(width, height) / 512)
        var minimumX = width
        var minimumY = height
        var maximumX = 0
        var maximumY = 0
        var activeBlockCount = 0

        for blockY in stride(from: 0, to: height, by: blockSize) {
            let blockMaximumY = min(height, blockY + blockSize)
            for blockX in stride(from: 0, to: width, by: blockSize) {
                let blockMaximumX = min(width, blockX + blockSize)
                let sampleCount = (blockMaximumX - blockX) * (blockMaximumY - blockY)
                var different = 0
                for y in blockY..<blockMaximumY {
                    for x in blockX..<blockMaximumX
                    where backgroundDistance(x: x, y: y, background: background) >= threshold {
                        different += 1
                    }
                }
                guard different * 4 >= sampleCount else { continue }
                activeBlockCount += 1
                minimumX = min(minimumX, blockX)
                minimumY = min(minimumY, blockY)
                maximumX = max(maximumX, blockMaximumX)
                maximumY = max(maximumY, blockMaximumY)
            }
        }

        let minimumActiveBlocks = max(4, width * height / max(blockSize * blockSize * 2_000, 1))
        guard activeBlockCount >= minimumActiveBlocks,
              maximumX > minimumX,
              maximumY > minimumY else { return nil }
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }

    func estimatedDeskewAngle() -> Double? {
        guard let background = borderBackgroundChannels() else { return nil }
        let borderStride = max(1, min(width, height) / 128)
        var borderDistances: [Double] = []
        for x in stride(from: 0, to: width, by: borderStride) {
            borderDistances.append(backgroundDistance(x: x, y: 0, background: background))
            borderDistances.append(
                backgroundDistance(x: x, y: height - 1, background: background)
            )
        }
        for y in stride(from: borderStride, to: height - 1, by: borderStride) {
            borderDistances.append(backgroundDistance(x: 0, y: y, background: background))
            borderDistances.append(
                backgroundDistance(x: width - 1, y: y, background: background)
            )
        }
        let threshold = max(12, median(borderDistances) * 3 + 6)
        let sampleStep = max(4, width / 96)
        var topSamples: [(Double, Double)] = []
        var bottomSamples: [(Double, Double)] = []

        for x in stride(from: sampleStep / 2, to: width, by: sampleStep) {
            if let top = (0..<height).first(where: {
                backgroundDistance(x: x, y: $0, background: background) >= threshold
            }) {
                topSamples.append((Double(x), Double(top)))
            }
            if let bottom = stride(from: height - 1, through: 0, by: -1).first(where: {
                backgroundDistance(x: x, y: $0, background: background) >= threshold
            }) {
                bottomSamples.append((Double(x), Double(bottom)))
            }
        }

        let slopes = [topSamples, bottomSamples].compactMap { samples -> Double? in
            guard samples.count >= 12,
                  let minimumX = samples.map(\.0).min(),
                  let maximumX = samples.map(\.0).max(),
                  maximumX - minimumX >= Double(width) * 0.55 else { return nil }
            return robustSlope(samples)
        }
        guard !slopes.isEmpty else { return nil }
        let slope = median(slopes)
        let correction = -atan(slope) * 180 / .pi
        return correction.isFinite && abs(correction) >= 0.25 && abs(correction) <= 5.5
            ? correction
            : nil
    }

    func backgroundSeparatedFrameRects(matching aspects: [Double]) -> [CGRect] {
        guard !aspects.isEmpty, width >= 32, height >= 32 else { return [] }
        let borderStride = max(1, min(width, height) / 128)
        var borderChannels = [[UInt8](), [UInt8](), [UInt8]()]
        for x in stride(from: 0, to: width, by: borderStride) {
            appendPixelChannels(x: x, y: 0, to: &borderChannels)
            appendPixelChannels(x: x, y: height - 1, to: &borderChannels)
        }
        for y in stride(from: borderStride, to: height - 1, by: borderStride) {
            appendPixelChannels(x: 0, y: y, to: &borderChannels)
            appendPixelChannels(x: width - 1, y: y, to: &borderChannels)
        }
        let background = borderChannels.map {
            UInt8(min(max(Int(median($0.map(Double.init)).rounded()), 0), 255))
        }
        guard background.count == 3 else { return [] }

        var borderDistances: [Double] = []
        borderDistances.reserveCapacity(borderChannels[0].count)
        for index in borderChannels[0].indices {
            borderDistances.append(Double(max(
                abs(Int(borderChannels[0][index]) - Int(background[0])),
                abs(Int(borderChannels[1][index]) - Int(background[1])),
                abs(Int(borderChannels[2][index]) - Int(background[2]))
            )))
        }
        let threshold = max(12, median(borderDistances) * 3 + 6)
        let blockSize = max(2, max(width, height) / 768)
        let gridWidth = (width + blockSize - 1) / blockSize
        let gridHeight = (height + blockSize - 1) / blockSize
        var active = [Bool](repeating: false, count: gridWidth * gridHeight)

        for gridY in 0..<gridHeight {
            let minY = gridY * blockSize
            let maxY = min(height, minY + blockSize)
            for gridX in 0..<gridWidth {
                let minX = gridX * blockSize
                let maxX = min(width, minX + blockSize)
                var different = 0
                let sampleCount = (maxX - minX) * (maxY - minY)
                for y in minY..<maxY {
                    for x in minX..<maxX {
                        let offset = (y * width + x) * 4
                        let distance = max(
                            abs(Int(pixels[offset]) - Int(background[0])),
                            abs(Int(pixels[offset + 1]) - Int(background[1])),
                            abs(Int(pixels[offset + 2]) - Int(background[2]))
                        )
                        if Double(distance) >= threshold {
                            different += 1
                        }
                    }
                }
                active[gridY * gridWidth + gridX] = different * 4 >= sampleCount
            }
        }

        var visited = [Bool](repeating: false, count: active.count)
        var rects: [CGRect] = []
        let minimumPixelArea = max(256, width * height / 500)
        for start in active.indices where active[start] && !visited[start] {
            var queue = [start]
            visited[start] = true
            var cursor = 0
            var minimumX = start % gridWidth
            var maximumX = minimumX
            var minimumY = start / gridWidth
            var maximumY = minimumY
            var cellCount = 0

            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                cellCount += 1
                let x = index % gridWidth
                let y = index / gridWidth
                minimumX = min(minimumX, x)
                maximumX = max(maximumX, x)
                minimumY = min(minimumY, y)
                maximumY = max(maximumY, y)
                if x > 0 {
                    appendActiveNeighbor(index - 1, active: active, visited: &visited, queue: &queue)
                }
                if x + 1 < gridWidth {
                    appendActiveNeighbor(index + 1, active: active, visited: &visited, queue: &queue)
                }
                if y > 0 {
                    appendActiveNeighbor(
                        index - gridWidth,
                        active: active,
                        visited: &visited,
                        queue: &queue
                    )
                }
                if y + 1 < gridHeight {
                    appendActiveNeighbor(
                        index + gridWidth,
                        active: active,
                        visited: &visited,
                        queue: &queue
                    )
                }
            }

            let minX = minimumX * blockSize
            let minY = minimumY * blockSize
            let maxX = min(width, (maximumX + 1) * blockSize)
            let maxY = min(height, (maximumY + 1) * blockSize)
            let componentWidth = maxX - minX
            let componentHeight = maxY - minY
            let pixelArea = componentWidth * componentHeight
            let boundingCellArea = (maximumX - minimumX + 1) * (maximumY - minimumY + 1)
            let occupancy = Double(cellCount) / Double(max(boundingCellArea, 1))
            guard componentWidth >= 16,
                  componentHeight >= 16,
                  pixelArea >= minimumPixelArea,
                  occupancy >= 0.45,
                  minX >= blockSize,
                  minY >= blockSize,
                  maxX <= width - blockSize,
                  maxY <= height - blockSize else { continue }
            let aspect = Double(componentWidth) / Double(componentHeight)
            guard let matchedAspect = aspects.min(by: {
                abs(aspect / $0 - 1) < abs(aspect / $1 - 1)
            }),
                  abs(aspect / matchedAspect - 1) <= 0.25 else { continue }
            var fittedMinX = minX
            var fittedMinY = minY
            var fittedMaxX = maxX
            var fittedMaxY = maxY
            if aspect < matchedAspect {
                let fittedWidth = Int(
                    (Double(componentHeight) * matchedAspect).rounded()
                )
                let extra = max(0, fittedWidth - componentWidth)
                fittedMinX -= extra / 2
                fittedMaxX += extra - extra / 2
            } else {
                let fittedHeight = Int(
                    (Double(componentWidth) / matchedAspect).rounded()
                )
                let extra = max(0, fittedHeight - componentHeight)
                fittedMinY -= extra / 2
                fittedMaxY += extra - extra / 2
            }
            if fittedMinX < 0 {
                fittedMaxX -= fittedMinX
                fittedMinX = 0
            }
            if fittedMaxX > width {
                fittedMinX -= fittedMaxX - width
                fittedMaxX = width
            }
            if fittedMinY < 0 {
                fittedMaxY -= fittedMinY
                fittedMinY = 0
            }
            if fittedMaxY > height {
                fittedMinY -= fittedMaxY - height
                fittedMaxY = height
            }
            fittedMinX = max(0, fittedMinX)
            fittedMinY = max(0, fittedMinY)
            rects.append(CGRect(
                x: Double(fittedMinX) / Double(width),
                y: Double(fittedMinY) / Double(height),
                width: Double(fittedMaxX - fittedMinX) / Double(width),
                height: Double(fittedMaxY - fittedMinY) / Double(height)
            ))
        }
        return rects
    }

    private func borderBackgroundChannels() -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        let borderStride = max(1, min(width, height) / 128)
        var borderChannels = [[UInt8](), [UInt8](), [UInt8]()]
        for x in stride(from: 0, to: width, by: borderStride) {
            appendPixelChannels(x: x, y: 0, to: &borderChannels)
            appendPixelChannels(x: x, y: height - 1, to: &borderChannels)
        }
        for y in stride(from: borderStride, to: height - 1, by: borderStride) {
            appendPixelChannels(x: 0, y: y, to: &borderChannels)
            appendPixelChannels(x: width - 1, y: y, to: &borderChannels)
        }
        guard !borderChannels[0].isEmpty else { return nil }
        return borderChannels.map {
            UInt8(min(max(Int(median($0.map(Double.init)).rounded()), 0), 255))
        }
    }

    private func backgroundDistance(
        x: Int,
        y: Int,
        background: [UInt8]
    ) -> Double {
        let offset = (y * width + x) * 4
        return Double(max(
            abs(Int(pixels[offset]) - Int(background[0])),
            abs(Int(pixels[offset + 1]) - Int(background[1])),
            abs(Int(pixels[offset + 2]) - Int(background[2]))
        ))
    }

    private func appendPixelChannels(
        x: Int,
        y: Int,
        to channels: inout [[UInt8]]
    ) {
        let offset = (y * width + x) * 4
        channels[0].append(pixels[offset])
        channels[1].append(pixels[offset + 1])
        channels[2].append(pixels[offset + 2])
    }

    private func appendActiveNeighbor(
        _ index: Int,
        active: [Bool],
        visited: inout [Bool],
        queue: inout [Int]
    ) {
        guard active[index], !visited[index] else { return }
        visited[index] = true
        queue.append(index)
    }

    func channelMaximumDifference(x0: Int, y0: Int, x1: Int, y1: Int) -> Int {
        let first = (y0 * width + x0) * 4
        let second = (y1 * width + x1) * 4
        return max(
            abs(Int(pixels[first]) - Int(pixels[second])),
            abs(Int(pixels[first + 1]) - Int(pixels[second + 1])),
            abs(Int(pixels[first + 2]) - Int(pixels[second + 2]))
        )
    }

    func channelEqualizationLookupTables() -> [[UInt8]] {
        var histograms = Array(
            repeating: [Int](repeating: 0, count: 256),
            count: 3
        )
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            histograms[0][Int(pixels[offset])] += 1
            histograms[1][Int(pixels[offset + 1])] += 1
            histograms[2][Int(pixels[offset + 2])] += 1
        }
        let sampleCount = width * height
        return histograms.map { histogram in
            guard let firstValue = histogram.firstIndex(where: { $0 > 0 }) else {
                return Array(0...255).map(UInt8.init)
            }
            let cdfMinimum = histogram[...firstValue].reduce(0, +)
            let denominator = sampleCount - cdfMinimum
            guard denominator > 0 else { return Array(repeating: 0, count: 256) }
            var cumulative = 0
            return histogram.map { count in
                cumulative += count
                let normalized = Double(max(0, cumulative - cdfMinimum))
                    / Double(denominator)
                return UInt8(min(max(Int((normalized * 255).rounded()), 0), 255))
            }
        }
    }

    func equalizedChannelMaximumDifference(
        x0: Int,
        y0: Int,
        x1: Int,
        y1: Int,
        lookupTables: [[UInt8]]
    ) -> Int {
        let first = (y0 * width + x0) * 4
        let second = (y1 * width + x1) * 4
        return max(
            abs(
                Int(lookupTables[0][Int(pixels[first])])
                    - Int(lookupTables[0][Int(pixels[second])])
            ),
            abs(
                Int(lookupTables[1][Int(pixels[first + 1])])
                    - Int(lookupTables[1][Int(pixels[second + 1])])
            ),
            abs(
                Int(lookupTables[2][Int(pixels[first + 2])])
                    - Int(lookupTables[2][Int(pixels[second + 2])])
            )
        )
    }
}

func histogramQuantile(
    _ histogram: [Int],
    sampleCount: Int,
    quantile: Double
) -> Int {
    guard sampleCount > 0 else { return 0 }
    let target = Int((Double(sampleCount - 1) * min(max(quantile, 0), 1)).rounded(.down))
    var cumulative = 0
    for (value, count) in histogram.enumerated() {
        cumulative += count
        if cumulative > target { return value }
    }
    return histogram.count - 1
}
