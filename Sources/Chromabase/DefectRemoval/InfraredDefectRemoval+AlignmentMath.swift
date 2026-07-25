import Foundation

extension InfraredDefectRemoval {
    static func blockMean(
        _ source: [Float], width: Int, height: Int, factor: Int
    ) -> ([Float], Int, Int) {
        guard factor > 1 else { return (source, width, height) }
        let downWidth = max(1, width / factor)
        let downHeight = max(1, height / factor)
        var output = [Float](repeating: 0, count: downWidth * downHeight)
        let inverse = 1.0 / Float(factor * factor)
        for blockY in 0..<downHeight {
            let y0 = blockY * factor
            for blockX in 0..<downWidth {
                let x0 = blockX * factor
                var sum: Float = 0
                for y in y0..<min(height, y0 + factor) {
                    for x in x0..<min(width, x0 + factor) { sum += source[y * width + x] }
                }
                output[blockY * downWidth + blockX] = sum * inverse
            }
        }
        return (output, downWidth, downHeight)
    }

    static func highPass(_ source: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        let lowPass = DefectMorphology.boxMean(source, width: width, height: height, radius: radius)
        return zip(source, lowPass).map { pair in pair.0 - pair.1 }
    }

    static func rms(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sum = values.reduce(0.0) { $0 + Double($1) * Double($1) }
        return Float((sum / Double(values.count)).squareRoot())
    }

    static func ncc(
        _ first: [Float], _ second: [Float], width: Int, height: Int, dx: Int, dy: Int
    ) -> Double {
        correlation(first, second, width: width, height: height, dx: dx, dy: dy, stride: 1)
    }

    static func sampledNCC(
        _ first: [Float], _ second: [Float], width: Int, height: Int,
        dx: Int, dy: Int, stride: Int
    ) -> Double {
        correlation(first, second, width: width, height: height, dx: dx, dy: dy, stride: stride)
    }

    private static func correlation(
        _ first: [Float], _ second: [Float], width: Int, height: Int,
        dx: Int, dy: Int, stride: Int
    ) -> Double {
        let inset = (stride == 1 ? 4 : 8) + max(abs(dx), abs(dy))
        guard width > 2 * inset, height > 2 * inset else { return -1 }
        var firstSum = 0.0, secondSum = 0.0
        var firstSquareSum = 0.0, secondSquareSum = 0.0, productSum = 0.0
        var count = 0.0
        var y = inset
        while y < height - inset {
            let firstRow = (y + dy) * width
            let secondRow = y * width
            var x = inset
            while x < width - inset {
                let firstValue = Double(first[firstRow + x + dx])
                let secondValue = Double(second[secondRow + x])
                firstSum += firstValue
                secondSum += secondValue
                firstSquareSum += firstValue * firstValue
                secondSquareSum += secondValue * secondValue
                productSum += firstValue * secondValue
                count += 1
                x += stride
            }
            y += stride
        }
        guard count > (stride == 1 ? 16 : 64) else { return -1 }
        let covariance = productSum / count - (firstSum / count) * (secondSum / count)
        let firstVariance = firstSquareSum / count - (firstSum / count) * (firstSum / count)
        let secondVariance = secondSquareSum / count - (secondSum / count) * (secondSum / count)
        guard firstVariance > 1e-12, secondVariance > 1e-12 else { return -1 }
        return covariance / (firstVariance * secondVariance).squareRoot()
    }
}
