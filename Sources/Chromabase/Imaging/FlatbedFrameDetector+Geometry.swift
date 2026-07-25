import Foundation

extension Detector {
    func inferredStripRanges(rowEnergy: [Double]) -> [Range<Int>] {
        guard rowEnergy.count == image.height else { return [] }
        let smoothingRadius = max(2, Int((Double(image.height) * 0.005).rounded()))
        let smoothed = movingAverage(rowEnergy, radius: smoothingRadius)
        let centerStart = min(smoothingRadius, smoothed.count)
        let centerEnd = max(centerStart, smoothed.count - smoothingRadius)
        let baseline = median(Array(smoothed[centerStart..<centerEnd]))
        guard baseline > 0 else { return [] }

        var lowEnergyRuns: [Range<Int>] = []
        var runStart: Int?
        for index in smoothed.indices {
            let lowEnergy = smoothed[index] < baseline * 0.45
            if lowEnergy, runStart == nil {
                runStart = index
            } else if !lowEnergy, let start = runStart {
                lowEnergyRuns.append(start..<index)
                runStart = nil
            }
        }
        if let runStart {
            lowEnergyRuns.append(runStart..<image.height)
        }

        let minimumInteriorGapLength = max(4, image.height / 40)
        let minimumEdgeGapLength = max(3, image.height / 100)
        let acceptedRuns = lowEnergyRuns.filter { run in
            let touchesEdge = run.lowerBound <= smoothingRadius
                || run.upperBound >= image.height - smoothingRadius
            return run.count >= (touchesEdge ? minimumEdgeGapLength : minimumInteriorGapLength)
        }
        let leadingGap = acceptedRuns.first { $0.lowerBound <= smoothingRadius }
        let trailingGap = acceptedRuns.last { $0.upperBound >= image.height - smoothingRadius }
        var interiorGaps = acceptedRuns.filter {
            $0.lowerBound > smoothingRadius
                && $0.upperBound < image.height - smoothingRadius
        }
        if let longestGap = interiorGaps.map(\.count).max() {
            interiorGaps.removeAll { Double($0.count) < Double(longestGap) * 0.75 }
        }
        guard !interiorGaps.isEmpty else { return [0..<image.height] }

        let lowerLimit = leadingGap?.upperBound ?? 0
        let upperLimit = trailingGap?.lowerBound ?? image.height
        let minimumStripHeight = max(32, image.height / 12)
        guard upperLimit - lowerLimit >= minimumStripHeight else { return [] }

        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(interiorGaps.count + 1)
        var lower = lowerLimit
        for gap in interiorGaps {
            guard gap.lowerBound - lower >= minimumStripHeight else { return [] }
            ranges.append(lower..<gap.lowerBound)
            lower = gap.upperBound
        }
        guard upperLimit - lower >= minimumStripHeight else { return [] }
        ranges.append(lower..<upperLimit)
        return ranges
    }

    func apertureRange(
        in partition: Range<Int>,
        edgeScores: [Double],
        usesInnerEdges: Bool
    ) -> Range<Int>? {
        guard partition.count >= 32 else { return nil }
        let height = partition.count
        let topRange: Range<Int>
        let bottomRange: Range<Int>
        let topTarget: Double
        let bottomTarget: Double
        let topSigma: Double
        let bottomSigma: Double
        if usesInnerEdges {
            topRange = boundedRange(
                partition.lowerBound + Int(Double(height) * 0.08),
                partition.lowerBound + Int(Double(height) * 0.32),
                limit: edgeScores.count
            )
            bottomRange = boundedRange(
                partition.lowerBound + Int(Double(height) * 0.68),
                partition.lowerBound + Int(Double(height) * 0.92),
                limit: edgeScores.count
            )
            topTarget = Double(partition.lowerBound) + Double(height) * 0.165
            bottomTarget = Double(partition.lowerBound) + Double(height) * 0.86
            topSigma = max(2, Double(height) * 0.03)
            bottomSigma = topSigma
        } else {
            let edgeWindow = max(3, Int(Double(height) * 0.08))
            topRange = boundedRange(
                partition.lowerBound,
                partition.lowerBound + edgeWindow,
                limit: edgeScores.count
            )
            bottomRange = boundedRange(
                partition.upperBound - edgeWindow,
                partition.upperBound,
                limit: edgeScores.count
            )
            topTarget = Double(partition.lowerBound) + Double(height) * 0.02
            bottomTarget = Double(partition.lowerBound) + Double(height) * 0.98
            topSigma = max(2, Double(height) * 0.015)
            bottomSigma = topSigma
        }
        let top = weightedMaximumIndex(
            in: topRange,
            values: edgeScores,
            target: topTarget,
            sigma: topSigma
        )
        let bottom = weightedMaximumIndex(
            in: bottomRange,
            values: edgeScores,
            target: bottomTarget,
            sigma: bottomSigma
        )
        guard let top,
              let bottom,
              bottom - top >= Int(Double(height) * (usesInnerEdges ? 0.60 : 0.70)),
              !usesInnerEdges || bottom - top <= Int(Double(height) * 0.78) else {
            return nil
        }
        guard edgePeakIsDistinct(top, in: topRange, values: edgeScores),
              edgePeakIsDistinct(bottom, in: bottomRange, values: edgeScores) else {
            return nil
        }
        return max(partition.lowerBound, top + 1)..<min(partition.upperBound, bottom + 1)
    }

    func detectStrip(
        aperture: Range<Int>,
        partition: Range<Int>,
        horizontalEdgeScores: [Double]
    ) -> DetectedStrip? {
        let nominalFrameAspect = frameFormat.stripFrameAspect
        let rawCount = Double(image.width) / (Double(aperture.count) * nominalFrameAspect)
        let columnCount = Int(rawCount.rounded())
        guard columnCount >= 1, columnCount <= 48 else { return nil }
        let pitch = Double(image.width) / Double(columnCount)
        let inferredAspect = pitch / Double(aperture.count)
        let minimumAspect = nominalFrameAspect * 0.82
        let maximumAspect = nominalFrameAspect * 1.18
        guard (minimumAspect...maximumAspect).contains(inferredAspect) else { return nil }

        let edgeScores = horizontalGradientColumnQuantiles(
            yRange: aperture,
            quantile: 0.75
        )
        guard edgeScores.count == image.width - 1 else { return nil }
        let scoreFloor = max(median(edgeScores), 1.0 / 255.0)
        let strongThreshold = scoreFloor * 5
        if columnCount > 1 {
            guard (edgeScores.max() ?? 0) >= strongThreshold else { return nil }
        }
        var boundaries = [Int](repeating: 0, count: columnCount + 1)
        boundaries[0] = 0
        boundaries[columnCount] = image.width
        var strongInternalCount = 0
        var measuredInternal: [(index: Int, x: Int)] = []

        if columnCount > 1 {
            for boundaryIndex in 1..<columnCount {
                let target = Double(boundaryIndex) * pitch
                let searchHalfWidth = max(4, Int((pitch * 0.12).rounded()))
                let lower = max(0, Int(target.rounded()) - searchHalfWidth)
                let upper = min(edgeScores.count, Int(target.rounded()) + searchHalfWidth + 1)
                guard lower < upper else { return nil }
                let sigma = max(2, pitch * 0.08)
                var bestIndex = lower
                var bestWeightedScore = -Double.infinity
                for x in lower..<upper {
                    let distance = (Double(x) - target) / sigma
                    let weighted = edgeScores[x] * exp(-0.5 * distance * distance)
                    if weighted > bestWeightedScore {
                        bestWeightedScore = weighted
                        bestIndex = x
                    }
                }
                if edgeScores[bestIndex] >= strongThreshold {
                    strongInternalCount += 1
                    measuredInternal.append((boundaryIndex, bestIndex))
                    boundaries[boundaryIndex] = bestIndex
                } else {
                    boundaries[boundaryIndex] = Int(target.rounded())
                }
            }
        }

        let requiredStrongCount = columnCount <= 2 ? columnCount - 1 : columnCount - 2
        guard strongInternalCount >= max(0, requiredStrongCount) else { return nil }
        interpolateWeakBoundaries(
            &boundaries,
            measured: measuredInternal,
            pitch: pitch
        )
        guard validBoundarySpacing(boundaries, pitch: pitch) else { return nil }

        let horizontalAngle = apertureStraightenAngle(
            aperture: aperture,
            partition: partition,
            edgeScores: horizontalEdgeScores
        )
        let verticalAngle = boundaryStraightenAngle(
            boundaries: boundaries,
            aperture: aperture,
            pitch: pitch
        )
        let straightenAngle: Double
        if let horizontalAngle {
            straightenAngle = horizontalAngle
        } else if let verticalAngle {
            straightenAngle = verticalAngle
        } else {
            straightenAngle = 0
        }
        let evidenceRatio = columnCount > 1
            ? Double(strongInternalCount) / Double(columnCount - 1)
            : 0.5
        let confidence = min(max(0.55 + evidenceRatio * 0.4, 0), 1)
        return DetectedStrip(
            aperture: aperture,
            boundaries: boundaries,
            columnCount: columnCount,
            straightenAngle: min(max(straightenAngle, -5), 5),
            confidence: confidence
        )
    }

    func interpolateWeakBoundaries(
        _ boundaries: inout [Int],
        measured: [(index: Int, x: Int)],
        pitch: Double
    ) {
        let measuredByIndex = Dictionary(uniqueKeysWithValues: measured.map { ($0.index, $0.x) })
        guard boundaries.count > 2 else { return }
        for index in 1..<(boundaries.count - 1) where measuredByIndex[index] == nil {
            let left = stride(from: index - 1, through: 0, by: -1)
                .first(where: { $0 == 0 || measuredByIndex[$0] != nil })
            let right = stride(from: index + 1, to: boundaries.count, by: 1)
                .first(where: { $0 == boundaries.count - 1 || measuredByIndex[$0] != nil })
            if let left, let right, right > left {
                let fraction = Double(index - left) / Double(right - left)
                boundaries[index] = Int(
                    (Double(boundaries[left])
                        + Double(boundaries[right] - boundaries[left]) * fraction).rounded()
                )
            } else {
                boundaries[index] = Int((Double(index) * pitch).rounded())
            }
        }
    }

    func validBoundarySpacing(_ boundaries: [Int], pitch: Double) -> Bool {
        guard boundaries.count >= 2,
              boundaries.first == 0,
              boundaries.last == image.width else { return false }
        for (left, right) in zip(boundaries, boundaries.dropFirst()) {
            let spacing = Double(right - left)
            guard spacing >= pitch * 0.68, spacing <= pitch * 1.32 else { return false }
        }
        return true
    }

    func apertureStraightenAngle(
        aperture: Range<Int>,
        partition: Range<Int>,
        edgeScores: [Double]
    ) -> Double? {
        let partitionHeight = partition.count
        guard aperture.lowerBound > partition.lowerBound + Int(Double(partitionHeight) * 0.05),
              aperture.upperBound < partition.upperBound - Int(Double(partitionHeight) * 0.05) else {
            return nil
        }
        let searchRadius = max(2, aperture.count / 35)
        let topSamples = traceHorizontalEdge(
            around: aperture.lowerBound,
            searchRadius: searchRadius
        )
        let bottomSamples = traceHorizontalEdge(
            around: aperture.upperBound - 1,
            searchRadius: searchRadius
        )
        let slopes = [robustSlope(topSamples), robustSlope(bottomSamples)].compactMap { $0 }
        guard !slopes.isEmpty else { return nil }
        let slope = slopes.reduce(0, +) / Double(slopes.count)
        let correction = -atan(slope) * 180 / .pi
        return correction.isFinite && abs(correction) <= 5 ? correction : nil
    }

    func boundaryStraightenAngle(
        boundaries: [Int],
        aperture: Range<Int>,
        pitch: Double
    ) -> Double? {
        guard boundaries.count > 2 else { return nil }
        let searchRadius = max(3, Int((pitch * 0.035).rounded()))
        var corrections: [Double] = []
        for x in boundaries.dropFirst().dropLast() {
            let samples = traceVerticalEdge(
                around: x,
                yRange: aperture,
                searchRadius: searchRadius
            )
            if let slope = robustSlope(samples.map { ($0.1, $0.0) }) {
                let correction = atan(slope) * 180 / .pi
                if correction.isFinite, abs(correction) <= 5 {
                    corrections.append(correction)
                }
            }
        }
        guard corrections.count >= max(1, (boundaries.count - 2) / 2) else { return nil }
        return median(corrections)
    }
}

struct DetectedStrip {
    let aperture: Range<Int>
    let boundaries: [Int]
    let columnCount: Int
    let straightenAngle: Double
    let confidence: Double
}

func movingAverage(_ values: [Double], radius: Int) -> [Double] {
    guard !values.isEmpty, radius > 0 else { return values }
    var prefix = [Double](repeating: 0, count: values.count + 1)
    for index in values.indices {
        prefix[index + 1] = prefix[index] + values[index]
    }
    return values.indices.map { index in
        let lower = max(0, index - radius)
        let upper = min(values.count, index + radius + 1)
        return (prefix[upper] - prefix[lower]) / Double(upper - lower)
    }
}

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

func weightedMaximumIndex(
    in range: Range<Int>,
    values: [Double],
    target: Double,
    sigma: Double
) -> Int? {
    guard !range.isEmpty,
          range.lowerBound >= 0,
          range.upperBound <= values.count,
          sigma > 0 else { return nil }
    return range.max { left, right in
        func weightedScore(_ index: Int) -> Double {
            let distance = (Double(index) - target) / sigma
            return values[index] * exp(-0.5 * distance * distance)
        }
        return weightedScore(left) < weightedScore(right)
    }
}

private func edgePeakIsDistinct(
    _ index: Int,
    in range: Range<Int>,
    values: [Double]
) -> Bool {
    guard range.contains(index), range.upperBound <= values.count else { return false }
    let baseline = max(median(Array(values[range])), 1.0 / 255.0)
    let threshold = max(2.0 / 255.0, baseline * 2)
    return values[index] >= threshold
}

func boundedRange(_ lower: Int, _ upper: Int, limit: Int) -> Range<Int> {
    let boundedLower = min(max(0, lower), limit)
    let boundedUpper = min(max(boundedLower, upper), limit)
    return boundedLower..<boundedUpper
}

func robustSlope(_ samples: [(Double, Double)]) -> Double? {
    guard samples.count >= 8, let initial = leastSquaresSlope(samples) else { return nil }
    let centerX = samples.map(\.0).reduce(0, +) / Double(samples.count)
    let centerY = samples.map(\.1).reduce(0, +) / Double(samples.count)
    let residuals = samples.map { abs($0.1 - (centerY + initial * ($0.0 - centerX))) }
    let cutoff = max(1, median(residuals) * 2.5)
    let filtered = zip(samples, residuals).compactMap { sample, residual in
        residual <= cutoff ? sample : nil
    }
    return filtered.count >= 8 ? leastSquaresSlope(filtered) : initial
}

func leastSquaresSlope(_ samples: [(Double, Double)]) -> Double? {
    guard samples.count >= 2 else { return nil }
    let meanX = samples.map(\.0).reduce(0, +) / Double(samples.count)
    let meanY = samples.map(\.1).reduce(0, +) / Double(samples.count)
    var numerator = 0.0
    var denominator = 0.0
    for (x, y) in samples {
        let deltaX = x - meanX
        numerator += deltaX * (y - meanY)
        denominator += deltaX * deltaX
    }
    guard denominator > 1e-9 else { return nil }
    return numerator / denominator
}
