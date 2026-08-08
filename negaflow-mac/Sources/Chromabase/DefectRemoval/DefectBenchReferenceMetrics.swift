import Foundation

public struct DefectBenchReferenceMetrics: Codable, Sendable {
    public let referenceName: String
    public let baselinePSNR: Double?
    public let repairedPSNR: Double?
    public let psnrDelta: Double?
    public let baselineMeanAbsoluteError: Double
    public let repairedMeanAbsoluteError: Double
    public let improvedPixelFraction: Double
    public let regressedPixelFraction: Double
}

enum DefectBenchReferenceEvaluator {
    static func evaluate(
        before: [UInt8],
        after: [UInt8],
        reference: [UInt8],
        width: Int,
        height: Int,
        referenceName: String
    ) throws -> DefectBenchReferenceMetrics {
        let expectedCount = width * height * 4
        guard before.count == expectedCount,
              after.count == expectedCount,
              reference.count == expectedCount
        else {
            throw ChromabaseError.writeFailed("골든셋 이미지 버퍼 크기가 일치하지 않습니다: \(referenceName)")
        }

        var baselineSquaredError = 0.0
        var repairedSquaredError = 0.0
        var baselineAbsoluteError = 0.0
        var repairedAbsoluteError = 0.0
        var improvedPixels = 0
        var regressedPixels = 0

        for pixel in 0..<(width * height) {
            let offset = pixel * 4
            var baselinePixelError = 0.0
            var repairedPixelError = 0.0
            for channel in 0..<3 {
                let referenceValue = Double(reference[offset + channel]) / 255.0
                let beforeDelta = Double(before[offset + channel]) / 255.0 - referenceValue
                let afterDelta = Double(after[offset + channel]) / 255.0 - referenceValue
                baselineSquaredError += beforeDelta * beforeDelta
                repairedSquaredError += afterDelta * afterDelta
                baselinePixelError += abs(beforeDelta)
                repairedPixelError += abs(afterDelta)
            }
            baselineAbsoluteError += baselinePixelError
            repairedAbsoluteError += repairedPixelError
            if repairedPixelError < baselinePixelError {
                improvedPixels += 1
            } else if repairedPixelError > baselinePixelError {
                regressedPixels += 1
            }
        }

        let channelCount = Double(width * height * 3)
        let pixelCount = Double(width * height)
        let baselineMSE = baselineSquaredError / channelCount
        let repairedMSE = repairedSquaredError / channelCount
        let baselinePSNR = psnr(for: baselineMSE)
        let repairedPSNR = psnr(for: repairedMSE)
        let psnrDelta: Double?
        if let baselinePSNR, let repairedPSNR {
            psnrDelta = repairedPSNR - baselinePSNR
        } else {
            psnrDelta = nil
        }

        return DefectBenchReferenceMetrics(
            referenceName: referenceName,
            baselinePSNR: baselinePSNR,
            repairedPSNR: repairedPSNR,
            psnrDelta: psnrDelta,
            baselineMeanAbsoluteError: baselineAbsoluteError / channelCount,
            repairedMeanAbsoluteError: repairedAbsoluteError / channelCount,
            improvedPixelFraction: Double(improvedPixels) / pixelCount,
            regressedPixelFraction: Double(regressedPixels) / pixelCount
        )
    }

    private static func psnr(for meanSquaredError: Double) -> Double? {
        guard meanSquaredError > 0 else { return nil }
        return 10 * log10(1 / meanSquaredError)
    }
}
