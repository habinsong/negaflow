import CoreGraphics
import Foundation
import ImageIO

public enum FilmFrameFormat: String, CaseIterable, Codable, Sendable {
    case fullFrame35mm
    case square35mm
    case halfFrame35mm
    case medium645
    case medium66
    case medium69
    case medium612

    /// 필름 스트립을 가로로 놓았을 때 프레임이 진행되는 축의 공칭 길이입니다.
    public var stripWidthMM: Double {
        switch self {
        case .fullFrame35mm: return 36
        case .square35mm: return 24
        case .halfFrame35mm: return 18
        case .medium645: return 41.5
        case .medium66: return 56
        case .medium69: return 84
        case .medium612: return 112
        }
    }

    /// 필름 스트립 폭 방향의 공칭 이미지 길이입니다.
    public var stripHeightMM: Double {
        switch self {
        case .fullFrame35mm, .square35mm, .halfFrame35mm:
            return 24
        case .medium645, .medium66, .medium69, .medium612:
            return 56
        }
    }

    public var stripFrameAspect: Double {
        stripWidthMM / stripHeightMM
    }

    public var is35mm: Bool {
        switch self {
        case .fullFrame35mm, .square35mm, .halfFrame35mm:
            return true
        case .medium645, .medium66, .medium69, .medium612:
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
        case .medium69: return "120 · 6 × 9"
        case .medium612: return "120 · 6 × 12"
        }
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
              pixels.width >= 256,
              pixels.height >= 48 else { return [] }
        return Detector(image: pixels, frameFormat: frameFormat).run()
    }
}

struct Detector {
    let image: AnalysisImage
    let frameFormat: FilmFrameFormat

    init(image: AnalysisImage, frameFormat: FilmFrameFormat) {
        self.image = image
        self.frameFormat = frameFormat
    }

    func run() -> [FlatbedFrameDetection] {
        let rowEnergy = equalizedHorizontalGradientRowMeans()
        let stripRanges = inferredStripRanges(rowEnergy: rowEnergy)
        guard !stripRanges.isEmpty, stripRanges.count <= 12 else { return [] }

        let horizontalEdgeScores = movingAverage(
            verticalGradientRowQuantiles(quantile: 0.75),
            radius: 1
        )
        var strips: [DetectedStrip] = []
        strips.reserveCapacity(stripRanges.count)

        for range in stripRanges {
            guard let aperture = apertureRange(
                in: range,
                edgeScores: horizontalEdgeScores,
                usesInnerEdges: stripRanges.count > 1
            ), let strip = detectStrip(
                aperture: aperture,
                partition: range,
                horizontalEdgeScores: horizontalEdgeScores
            ) else { return [] }
            strips.append(strip)
        }

        guard let inferredColumnCount = strips.first?.columnCount,
              inferredColumnCount > 0,
              strips.allSatisfy({ $0.columnCount == inferredColumnCount }) else { return [] }

        var result: [FlatbedFrameDetection] = []
        result.reserveCapacity(strips.count * inferredColumnCount)
        for (row, strip) in strips.enumerated() {
            for column in 0..<strip.columnCount {
                let minX = strip.boundaries[column]
                let maxX = strip.boundaries[column + 1]
                guard maxX > minX else { return [] }
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
                    column: column
                ))
            }
        }
        return result
    }
}
