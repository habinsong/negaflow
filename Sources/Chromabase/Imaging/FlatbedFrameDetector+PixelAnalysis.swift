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
