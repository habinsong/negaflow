import Foundation

extension InfraredDefectRemoval {
    public enum AlignmentStatus: String, Sendable, Equatable {
        case notRequested
        case aligned
        case insufficientTexture
        case weakCorrelation
        case searchLimitReached
    }

    public struct AlignmentDiagnostics: Sendable, Equatable {
        public let status: AlignmentStatus
        public let offsetX: Int
        public let offsetY: Int
        public let peakCorrelation: Double?
        public let runnerUpCorrelation: Double?
        public let searchRadius: Int
        public let downsampleFactor: Int

        var isAccepted: Bool {
            status == .notRequested || status == .aligned
        }
    }

    static func estimateAlignment(
        infrared: [Float],
        red: [Float],
        width: Int,
        height: Int,
        searchRadius: Int
    ) -> AlignmentDiagnostics {
        guard searchRadius > 0 else {
            return diagnostics(status: .notRequested, searchRadius: searchRadius)
        }
        let factor = max(1, min(width, height) / 384)
        let (irDown, downWidth, downHeight) = blockMean(
            infrared, width: width, height: height, factor: factor
        )
        let (redDown, _, _) = blockMean(red, width: width, height: height, factor: factor)
        guard downWidth > 24, downHeight > 24 else {
            return diagnostics(
                status: .insufficientTexture,
                searchRadius: searchRadius,
                downsampleFactor: factor
            )
        }

        let infraredHighPass = highPass(irDown, width: downWidth, height: downHeight, radius: 4)
        let redHighPass = highPass(redDown, width: downWidth, height: downHeight, radius: 4)
        guard rms(infraredHighPass) > 0.003 else {
            return diagnostics(
                status: .insufficientTexture,
                searchRadius: searchRadius,
                downsampleFactor: factor
            )
        }

        let radius = max(1, min(searchRadius / factor, min(downWidth, downHeight) / 4))
        var best = (x: 0, y: 0)
        var bestScore = -1.0
        var runnerUpScore = -1.0
        for y in -radius...radius {
            for x in -radius...radius {
                let score = ncc(
                    infraredHighPass,
                    redHighPass,
                    width: downWidth,
                    height: downHeight,
                    dx: x,
                    dy: y
                )
                if score > bestScore {
                    runnerUpScore = bestScore
                    bestScore = score
                    best = (x, y)
                } else if score > runnerUpScore {
                    runnerUpScore = score
                }
            }
        }
        guard bestScore > 0.2 else {
            return diagnostics(
                status: .weakCorrelation,
                peak: bestScore,
                runnerUp: runnerUpScore,
                searchRadius: searchRadius,
                downsampleFactor: factor
            )
        }

        var fine = (x: best.x * factor, y: best.y * factor)
        var fineScore = -1.0
        var fineRunnerUp = -1.0
        let minimumY = max(-searchRadius, fine.y - factor)
        let maximumY = min(searchRadius, fine.y + factor)
        let minimumX = max(-searchRadius, fine.x - factor)
        let maximumX = min(searchRadius, fine.x + factor)
        for y in minimumY...maximumY {
            for x in minimumX...maximumX {
                let score = sampledNCC(
                    infrared,
                    red,
                    width: width,
                    height: height,
                    dx: x,
                    dy: y,
                    stride: max(2, factor)
                )
                if score > fineScore {
                    fineRunnerUp = fineScore
                    fineScore = score
                    fine = (x, y)
                } else if score > fineRunnerUp {
                    fineRunnerUp = score
                }
            }
        }

        let reachedLimit = abs(fine.x) == searchRadius || abs(fine.y) == searchRadius
        return diagnostics(
            status: reachedLimit ? .searchLimitReached : .aligned,
            offsetX: fine.x,
            offsetY: fine.y,
            peak: fineScore,
            runnerUp: fineRunnerUp,
            searchRadius: searchRadius,
            downsampleFactor: factor
        )
    }

    /// 평면을 (dx, dy)만큼 당겨 raw 격자에 맞춘다: out(x,y) = src(x+dx, y+dy).
    static func shiftPlane(
        _ source: [Float],
        width: Int,
        height: Int,
        dx: Int,
        dy: Int,
        outOfBounds excluded: inout [Bool]
    ) -> [Float] {
        guard dx != 0 || dy != 0 else { return source }
        var output = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let sourceY = y + dy
            guard sourceY >= 0, sourceY < height else {
                for x in 0..<width { excluded[y * width + x] = true }
                continue
            }
            for x in 0..<width {
                let sourceX = x + dx
                if sourceX >= 0, sourceX < width {
                    output[y * width + x] = source[sourceY * width + sourceX]
                } else {
                    excluded[y * width + x] = true
                }
            }
        }
        return output
    }

    private static func diagnostics(
        status: AlignmentStatus,
        offsetX: Int = 0,
        offsetY: Int = 0,
        peak: Double? = nil,
        runnerUp: Double? = nil,
        searchRadius: Int,
        downsampleFactor: Int = 1
    ) -> AlignmentDiagnostics {
        AlignmentDiagnostics(
            status: status,
            offsetX: offsetX,
            offsetY: offsetY,
            peakCorrelation: peak,
            runnerUpCorrelation: runnerUp,
            searchRadius: searchRadius,
            downsampleFactor: downsampleFactor
        )
    }

}
