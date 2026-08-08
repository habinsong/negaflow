import CoreGraphics
import Foundation
import ImageIO

public enum FilmFrameFormat: String, CaseIterable, Codable, Sendable {
    case fullFrame35mm
    case square35mm
    case halfFrame35mm
    case medium645
    case medium66
    case medium67
    case medium68
    case medium69
    case medium612
    case medium617

    /// 필름 스트립을 가로로 놓았을 때 프레임이 진행되는 축의 공칭 길이입니다.
    public var stripWidthMM: Double {
        switch self {
        case .fullFrame35mm: return 36
        case .square35mm: return 24
        case .halfFrame35mm: return 18
        case .medium645: return 41.5
        case .medium66: return 56
        case .medium67: return 69
        case .medium68: return 76
        case .medium69: return 84
        case .medium612: return 112
        case .medium617: return 168
        }
    }

    /// 필름 스트립 폭 방향의 공칭 이미지 길이입니다.
    public var stripHeightMM: Double {
        switch self {
        case .fullFrame35mm, .square35mm, .halfFrame35mm:
            return 24
        case .medium645, .medium66, .medium68, .medium69, .medium612, .medium617:
            return 56
        case .medium67:
            return 55
        }
    }

    public var stripFrameAspect: Double {
        stripWidthMM / stripHeightMM
    }

    public var frameAspectCandidates: [Double] {
        let aspect = stripFrameAspect
        let rotated = 1 / aspect
        return abs(aspect - rotated) < 0.000_001 ? [aspect] : [aspect, rotated]
    }

    public var is35mm: Bool {
        switch self {
        case .fullFrame35mm, .square35mm, .halfFrame35mm:
            return true
        case .medium645, .medium66, .medium67, .medium68, .medium69, .medium612,
             .medium617:
            return false
        }
    }

    /// 규격명과 치수는 번역하지 않는 기술 표기입니다.
    public var displayName: String {
        switch self {
        case .fullFrame35mm: return "35 mm · 36 × 24"
        case .square35mm: return "35 mm · 24 × 24"
        case .halfFrame35mm: return "35 mm · 24 × 18"
        case .medium645: return "120 · 6 × 4.5"
        case .medium66: return "120 · 6 × 6"
        case .medium67: return "120 · 6 × 7"
        case .medium68: return "120 · 6 × 8"
        case .medium69: return "120 · 6 × 9"
        case .medium612: return "120 · 6 × 12"
        case .medium617: return "120 · 6 × 17"
        }
    }
}

public enum FilmFrameOrientation: String, CaseIterable, Codable, Hashable, Sendable {
    case landscape
    case portrait

    public func aspect(for format: FilmFrameFormat) -> Double {
        let aspect = format.stripFrameAspect
        let landscapeAspect = max(aspect, 1 / aspect)
        return self == .landscape ? landscapeAspect : 1 / landscapeAspect
    }
}

public struct FlatbedFrameDetection: Sendable, Equatable {
    /// Source-image normalized coordinates with a top-left origin.
    public let normalizedRect: CGRect
    /// Correction angle ready to assign to `ImageTransform.straightenAngle`.
    public let straightenAngle: Double
    public let confidence: Double
    public let row: Int
    public let column: Int

    public init(
        normalizedRect: CGRect,
        straightenAngle: Double,
        confidence: Double,
        row: Int,
        column: Int
    ) {
        self.normalizedRect = normalizedRect
        self.straightenAngle = straightenAngle
        self.confidence = confidence
        self.row = row
        self.column = column
    }
}

public enum FlatbedFrameDetectorError: Error, Equatable {
    case imageDecodeFailed
}

/// Geometry-only detector for repeated film frames on a flatbed overview.
///
/// It intentionally avoids color, density, and polarity assumptions. Frame counts are inferred
/// from detected strip geometry and the selected film aperture aspect, then checked against periodic
/// full-height boundaries. Ambiguous inputs fail closed with no proposed regions.
public enum FlatbedFrameDetector {
    public static func detect(
        url: URL,
        frameFormat: FilmFrameFormat = .fullFrame35mm,
        maxAnalysisDimension: Int = 2_048
    ) throws -> [FlatbedFrameDetection] {
        guard maxAnalysisDimension >= 256,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: false,
                      kCGImageSourceThumbnailMaxPixelSize: maxAnalysisDimension,
                  ] as CFDictionary
              ) else {
            throw FlatbedFrameDetectorError.imageDecodeFailed
        }
        return detect(
            image: image,
            frameFormat: frameFormat,
            maxAnalysisDimension: maxAnalysisDimension
        )
    }

    public static func detect(
        image: CGImage,
        frameFormat: FilmFrameFormat = .fullFrame35mm,
        maxAnalysisDimension: Int = 2_048
    ) -> [FlatbedFrameDetection] {
        guard maxAnalysisDimension >= 256,
              let pixels = AnalysisImage(image: image, maxDimension: maxAnalysisDimension),
              max(pixels.width, pixels.height) >= 256,
              min(pixels.width, pixels.height) >= 48 else { return [] }
        return detect(image: pixels, frameFormat: frameFormat)
    }

    private static func detect(
        image: AnalysisImage,
        frameFormat: FilmFrameFormat
    ) -> [FlatbedFrameDetection] {
        let aligned = detectAligned(image: image, frameFormat: frameFormat)
        if !aligned.isEmpty { return aligned }

        guard let foreground = image.foregroundBounds() else { return [] }
        let padding = max(4, min(image.width, image.height) / 100)
        let cropRect = foreground.insetBy(dx: -Double(padding), dy: -Double(padding))
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            .integral
        let meaningfullyInset = cropRect.width < Double(image.width) * 0.98
            || cropRect.height < Double(image.height) * 0.98
        guard meaningfullyInset,
              let cropped = image.cropped(to: cropRect),
              cropped.width >= 48,
              cropped.height >= 48 else { return [] }
        let fallbackImage = cropped.resized(maxDimension: 1_024)

        let estimatedAngle = fallbackImage.estimatedDeskewAngle()
        if estimatedAngle == nil {
            let croppedAligned = detectAligned(image: fallbackImage, frameFormat: frameFormat)
            if !croppedAligned.isEmpty {
                return normalizedTopology(
                    mapFromCrop(
                        croppedAligned,
                        cropRect: cropRect,
                        sourceWidth: image.width,
                        sourceHeight: image.height
                    )
                )
            }
        }

        var deskewAngles: [Double] = []
        if let estimatedAngle {
            deskewAngles.append(estimatedAngle)
        }
        for angle in [-1.0, 1.0, -2.0, 2.0, -3.0, 3.0, -4.0, 4.0, -5.0, 5.0]
        where !deskewAngles.contains(where: { abs($0 - angle) < 0.35 }) {
            deskewAngles.append(angle)
        }

        for angle in deskewAngles {
            let deskewed = fallbackImage.rotated(byDegrees: angle)
            let detections = detectAligned(image: deskewed, frameFormat: frameFormat)
            guard !detections.isEmpty else { continue }
            let mappedToCrop = mapFromRotatedCanvas(
                detections,
                angle: angle,
                width: fallbackImage.width,
                height: fallbackImage.height
            )
            return normalizedTopology(
                mapFromCrop(
                    mappedToCrop,
                    cropRect: cropRect,
                    sourceWidth: image.width,
                    sourceHeight: image.height
                )
            )
        }
        return []
    }

    private static func detectAligned(
        image: AnalysisImage,
        frameFormat: FilmFrameFormat
    ) -> [FlatbedFrameDetection] {
        var candidates: [[FlatbedFrameDetection]] = []
        let separatedRects = image.backgroundSeparatedFrameRects(
            matching: frameFormat.frameAspectCandidates
        )
        let componentDetections = separatedRects.enumerated().map { index, rect in
            FlatbedFrameDetection(
                normalizedRect: rect,
                straightenAngle: 0,
                confidence: 0.75,
                row: 0,
                column: index
            )
        }
        if componentsAreSelfSufficient(separatedRects, image: image) {
            return normalizedTopology(
                componentDetections
            )
        }
        if let firstAspect = frameFormat.frameAspectCandidates.first {
            let preparationDetector = Detector(image: image, frameAspect: firstAspect)
            if let analysis = preparationDetector.prepare() {
                for frameAspect in frameFormat.frameAspectCandidates {
                    let detections = Detector(
                        image: image,
                        frameAspect: frameAspect
                    ).run(analysis: analysis)
                    if !detections.isEmpty {
                        candidates.append(contentsOf: groupedRows(detections))
                    }
                }
            }
        }
        if !candidates.isEmpty {
            return preferredDetections(
                components: componentDetections,
                patterned: mergedCandidates(candidates)
            )
        }

        let rotated = image.rotatedCounterClockwise()
        if let firstAspect = frameFormat.frameAspectCandidates.first {
            let preparationDetector = Detector(image: rotated, frameAspect: firstAspect)
            if let analysis = preparationDetector.prepare() {
                for frameAspect in frameFormat.frameAspectCandidates {
                    let detections = Detector(
                        image: rotated,
                        frameAspect: frameAspect
                    ).run(analysis: analysis)
                    if !detections.isEmpty {
                        let maximumRow = detections.map(\.row).max() ?? 0
                        let mapped = detections.map { detection in
                            let rect = detection.normalizedRect
                            return FlatbedFrameDetection(
                                normalizedRect: CGRect(
                                    x: 1 - rect.maxY,
                                    y: rect.minX,
                                    width: rect.height,
                                    height: rect.width
                                ),
                                straightenAngle: detection.straightenAngle,
                                confidence: detection.confidence,
                                row: maximumRow - detection.row,
                                column: detection.column
                            )
                        }
                        candidates.append(contentsOf: groupedRows(mapped))
                    }
                }
            }
        }
        return preferredDetections(
            components: componentDetections,
            patterned: mergedCandidates(candidates)
        )
    }

    private static func componentsAreSelfSufficient(
        _ rects: [CGRect],
        image: AnalysisImage
    ) -> Bool {
        guard !rects.isEmpty else { return false }
        let orientations = Set(rects.map { rect in
            let pixelAspect = rect.width * Double(image.width)
                / (rect.height * Double(image.height))
            return pixelAspect >= 1
        })
        if orientations.count > 1 { return true }
        guard let foreground = image.foregroundBounds() else { return false }
        let foregroundArea = foreground.width * foreground.height
        guard foregroundArea > 0 else { return false }
        let componentArea = rects.reduce(0.0) { result, rect in
            result + rect.width * Double(image.width) * rect.height * Double(image.height)
        }
        return componentArea / foregroundArea >= 0.90
    }

    private static func preferredDetections(
        components: [FlatbedFrameDetection],
        patterned: [FlatbedFrameDetection]
    ) -> [FlatbedFrameDetection] {
        if patterned.isEmpty { return normalizedTopology(components) }
        if components.count >= patterned.count {
            return normalizedTopology(components)
        }
        return patterned
    }

    private static func mergedCandidates(
        _ candidates: [[FlatbedFrameDetection]]
    ) -> [FlatbedFrameDetection] {
        var merged: [FlatbedFrameDetection] = []
        var acceptedBounds: [CGRect] = []
        let orderedCandidates = candidates.enumerated().sorted { first, second in
            let firstPreference = candidatePreference(first.element)
            let secondPreference = candidatePreference(second.element)
            if firstPreference != secondPreference {
                return firstPreference > secondPreference
            }
            return first.offset < second.offset
        }
        for candidate in orderedCandidates {
            guard let bounds = candidateBounds(candidate.element),
                  !acceptedBounds.contains(where: { overlapRatio($0, bounds) >= 0.25 })
            else { continue }
            acceptedBounds.append(bounds)
            merged.append(contentsOf: candidate.element)
        }
        return normalizedTopology(merged)
    }

    private static func mapFromRotatedCanvas(
        _ detections: [FlatbedFrameDetection],
        angle: Double,
        width: Int,
        height: Int
    ) -> [FlatbedFrameDetection] {
        let radians = angle * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        let centerX = Double(width - 1) / 2
        let centerY = Double(height - 1) / 2

        return detections.map { detection in
            let rect = detection.normalizedRect
            let minimumX = Double(width) * Double(rect.minX)
            let maximumX = Double(width) * Double(rect.maxX)
            let minimumY = Double(height) * Double(rect.minY)
            let maximumY = Double(height) * Double(rect.maxY)
            let corners = [
                (minimumX, minimumY),
                (maximumX, minimumY),
                (minimumX, maximumY),
                (maximumX, maximumY),
            ].map { point in
                let centeredX = point.0 - centerX
                let centeredY = point.1 - centerY
                return (
                    cosine * centeredX + sine * centeredY + centerX,
                    -sine * centeredX + cosine * centeredY + centerY
                )
            }
            let mappedMinimumX = max(0, corners.map(\.0).min() ?? 0)
            let mappedMaximumX = min(Double(width), corners.map(\.0).max() ?? Double(width))
            let mappedMinimumY = max(0, corners.map(\.1).min() ?? 0)
            let mappedMaximumY = min(Double(height), corners.map(\.1).max() ?? Double(height))
            return FlatbedFrameDetection(
                normalizedRect: CGRect(
                    x: mappedMinimumX / Double(width),
                    y: mappedMinimumY / Double(height),
                    width: max(0, mappedMaximumX - mappedMinimumX) / Double(width),
                    height: max(0, mappedMaximumY - mappedMinimumY) / Double(height)
                ),
                straightenAngle: min(max(detection.straightenAngle + angle, -5), 5),
                confidence: detection.confidence * 0.95,
                row: detection.row,
                column: detection.column
            )
        }
    }

    private static func mapFromCrop(
        _ detections: [FlatbedFrameDetection],
        cropRect: CGRect,
        sourceWidth: Int,
        sourceHeight: Int
    ) -> [FlatbedFrameDetection] {
        detections.map { detection in
            let rect = detection.normalizedRect
            return FlatbedFrameDetection(
                normalizedRect: CGRect(
                    x: (cropRect.minX + rect.minX * cropRect.width) / Double(sourceWidth),
                    y: (cropRect.minY + rect.minY * cropRect.height) / Double(sourceHeight),
                    width: rect.width * cropRect.width / Double(sourceWidth),
                    height: rect.height * cropRect.height / Double(sourceHeight)
                ),
                straightenAngle: detection.straightenAngle,
                confidence: detection.confidence,
                row: detection.row,
                column: detection.column
            )
        }
    }

    private static func candidatePreference(
        _ detections: [FlatbedFrameDetection]
    ) -> (Double, Int) {
        let confidence = detections.map(\.confidence).reduce(0, +)
            / Double(max(detections.count, 1))
        return (confidence, detections.count)
    }

    private static func groupedRows(
        _ detections: [FlatbedFrameDetection]
    ) -> [[FlatbedFrameDetection]] {
        Dictionary(grouping: detections, by: \.row)
            .sorted { $0.key < $1.key }
            .map(\.value)
    }

    private static func candidateBounds(
        _ detections: [FlatbedFrameDetection]
    ) -> CGRect? {
        guard let first = detections.first else { return nil }
        return detections.dropFirst().reduce(first.normalizedRect) {
            $0.union($1.normalizedRect)
        }
    }

    private static func overlapRatio(_ first: CGRect, _ second: CGRect) -> Double {
        let intersection = first.intersection(second)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return 0
        }
        let intersectionArea = Double(intersection.width * intersection.height)
        let smallerArea = min(
            Double(first.width * first.height),
            Double(second.width * second.height)
        )
        return smallerArea > 0 ? intersectionArea / smallerArea : 0
    }

    private static func normalizedTopology(
        _ detections: [FlatbedFrameDetection]
    ) -> [FlatbedFrameDetection] {
        let sorted = detections.sorted {
            if abs($0.normalizedRect.midY - $1.normalizedRect.midY) > 0.001 {
                return $0.normalizedRect.midY < $1.normalizedRect.midY
            }
            return $0.normalizedRect.minX < $1.normalizedRect.minX
        }
        var rows: [[FlatbedFrameDetection]] = []
        for detection in sorted {
            if let index = rows.indices.last(where: { rowIndex in
                guard let reference = rows[rowIndex].first else { return false }
                let minimumHeight = min(
                    reference.normalizedRect.height,
                    detection.normalizedRect.height
                )
                let overlapHeight = min(
                    reference.normalizedRect.maxY,
                    detection.normalizedRect.maxY
                ) - max(
                    reference.normalizedRect.minY,
                    detection.normalizedRect.minY
                )
                return minimumHeight > 0
                    && overlapHeight / minimumHeight >= 0.5
            }) {
                rows[index].append(detection)
            } else {
                rows.append([detection])
            }
        }

        return rows.enumerated().flatMap { row, detections in
            detections.sorted { $0.normalizedRect.minX < $1.normalizedRect.minX }
                .enumerated()
                .map { column, detection in
                    FlatbedFrameDetection(
                        normalizedRect: detection.normalizedRect,
                        straightenAngle: detection.straightenAngle,
                        confidence: detection.confidence,
                        row: row,
                        column: column
                    )
                }
        }
    }
}

struct Detector {
    let image: AnalysisImage
    let frameAspect: Double

    init(image: AnalysisImage, frameAspect: Double) {
        self.image = image
        self.frameAspect = frameAspect
    }

    func prepare() -> DetectorImageAnalysis? {
        let rowEnergy = equalizedHorizontalGradientRowMeans()
        let stripRanges = inferredStripRanges(rowEnergy: rowEnergy)
        guard !stripRanges.isEmpty, stripRanges.count <= 12 else { return nil }

        let horizontalEdgeScores = movingAverage(
            verticalGradientRowQuantiles(quantile: 0.75),
            radius: 1
        )
        var stripAnalyses: [DetectorStripAnalysis] = []
        stripAnalyses.reserveCapacity(stripRanges.count)
        for range in stripRanges {
            guard let aperture = apertureRange(
                in: range,
                edgeScores: horizontalEdgeScores,
                usesInnerEdges: stripRanges.count > 1
            ) else { continue }
            stripAnalyses.append(DetectorStripAnalysis(
                partition: range,
                aperture: aperture,
                verticalEdgeScores: horizontalGradientColumnQuantiles(
                    yRange: aperture,
                    quantile: 0.75
                )
            ))
        }
        guard !stripAnalyses.isEmpty else { return nil }
        return DetectorImageAnalysis(
            horizontalEdgeScores: horizontalEdgeScores,
            strips: stripAnalyses
        )
    }

    func run(analysis: DetectorImageAnalysis) -> [FlatbedFrameDetection] {
        let strips = analysis.strips.compactMap { stripAnalysis in
            detectStrip(
                aperture: stripAnalysis.aperture,
                partition: stripAnalysis.partition,
                horizontalEdgeScores: analysis.horizontalEdgeScores,
                verticalEdgeScores: stripAnalysis.verticalEdgeScores
            )
        }

        guard !strips.isEmpty else { return [] }

        var result: [FlatbedFrameDetection] = []
        result.reserveCapacity(strips.reduce(0) { $0 + $1.columnCount })
        for (row, strip) in strips.enumerated() {
            var outputColumn = 0
            for column in 0..<strip.columnCount {
                let minX = strip.boundaries[column]
                let maxX = strip.boundaries[column + 1]
                guard maxX > minX else { continue }
                let xRange = minX..<maxX
                guard frameHasVisualEvidence(
                    xRange: xRange,
                    aperture: strip.aperture
                ) else { continue }
                let rect = CGRect(
                    x: Double(minX) / Double(image.width),
                    y: Double(strip.aperture.lowerBound) / Double(image.height),
                    width: Double(maxX - minX) / Double(image.width),
                    height: Double(strip.aperture.count) / Double(image.height)
                )
                result.append(FlatbedFrameDetection(
                    normalizedRect: rect,
                    straightenAngle: strip.straightenAngle,
                    confidence: strip.confidence,
                    row: row,
                    column: outputColumn
                ))
                outputColumn += 1
            }
        }
        return result
    }

    private func frameHasVisualEvidence(
        xRange: Range<Int>,
        aperture: Range<Int>
    ) -> Bool {
        let xStride = max(1, xRange.count / 32)
        let yStride = max(1, aperture.count / 24)
        var minimum = [Int](repeating: 255, count: 3)
        var maximum = [Int](repeating: 0, count: 3)
        var interiorSum = [Double](repeating: 0, count: 3)
        var interiorCount = 0
        for y in stride(from: aperture.lowerBound, to: aperture.upperBound, by: yStride) {
            for x in stride(from: xRange.lowerBound, to: xRange.upperBound, by: xStride) {
                let offset = (y * image.width + x) * 4
                for channel in 0..<3 {
                    let value = Int(image.pixels[offset + channel])
                    minimum[channel] = min(minimum[channel], value)
                    maximum[channel] = max(maximum[channel], value)
                    interiorSum[channel] += Double(value)
                }
                interiorCount += 1
            }
        }
        guard interiorCount > 0 else { return false }
        let dynamicRange = zip(minimum, maximum).map { $1 - $0 }.max() ?? 0
        if dynamicRange >= 8 { return true }

        let exteriorRows = [
            max(0, aperture.lowerBound - max(2, aperture.count / 16)),
            min(image.height - 1, aperture.upperBound + max(1, aperture.count / 16)),
        ].filter { !aperture.contains($0) }
        guard !exteriorRows.isEmpty else { return true }
        var exteriorSum = [Double](repeating: 0, count: 3)
        var exteriorCount = 0
        for y in exteriorRows {
            for x in stride(from: xRange.lowerBound, to: xRange.upperBound, by: xStride) {
                let offset = (y * image.width + x) * 4
                for channel in 0..<3 {
                    exteriorSum[channel] += Double(image.pixels[offset + channel])
                }
                exteriorCount += 1
            }
        }
        guard exteriorCount > 0 else { return true }
        let meanDifference = (0..<3).map { channel in
            abs(
                interiorSum[channel] / Double(interiorCount)
                    - exteriorSum[channel] / Double(exteriorCount)
            )
        }.max() ?? 0
        return meanDifference >= 6
    }
}

struct DetectorImageAnalysis {
    let horizontalEdgeScores: [Double]
    let strips: [DetectorStripAnalysis]
}

struct DetectorStripAnalysis {
    let partition: Range<Int>
    let aperture: Range<Int>
    let verticalEdgeScores: [Double]
}
