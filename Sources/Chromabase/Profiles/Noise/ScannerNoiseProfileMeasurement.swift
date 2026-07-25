import Foundation

public struct ScannerNoiseCalibrationFrame: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let linearRGB: [SIMD3<Float>]

    public init(width: Int, height: Int, linearRGB: [SIMD3<Float>]) {
        self.width = width
        self.height = height
        self.linearRGB = linearRGB
    }
}

public enum ScannerNoiseProfileMeasurementError: Error, Equatable {
    case insufficientFrames
    case invalidDimensions
    case nonFiniteSample
    case insufficientSignalRange
}

public enum ScannerNoiseProfileMeasurement {
    public static func measure(
        frames: [ScannerNoiseCalibrationFrame],
        binCount: Int = 16
    ) throws -> ScannerNoiseModel {
        guard frames.count >= 3 else {
            throw ScannerNoiseProfileMeasurementError.insufficientFrames
        }
        guard let first = frames.first,
              first.width > 0,
              first.height > 0,
              first.linearRGB.count == first.width * first.height,
              binCount >= 4,
              frames.allSatisfy({
                  $0.width == first.width
                      && $0.height == first.height
                      && $0.linearRGB.count == first.linearRGB.count
              })
        else {
            throw ScannerNoiseProfileMeasurementError.invalidDimensions
        }

        var channels = Array(repeating: ChannelAccumulator(binCount: binCount), count: 3)
        for pixel in first.linearRGB.indices {
            var mean = SIMD3<Double>(repeating: 0)
            for frame in frames {
                let sample = frame.linearRGB[pixel]
                guard sample.x.isFinite, sample.y.isFinite, sample.z.isFinite else {
                    throw ScannerNoiseProfileMeasurementError.nonFiniteSample
                }
                mean += SIMD3(Double(sample.x), Double(sample.y), Double(sample.z))
            }
            mean /= Double(frames.count)

            var squared = SIMD3<Double>(repeating: 0)
            for frame in frames {
                let sample = frame.linearRGB[pixel]
                let delta = SIMD3(Double(sample.x), Double(sample.y), Double(sample.z)) - mean
                squared += delta * delta
            }
            let variance = squared / Double(frames.count - 1)
            for channel in 0..<3 {
                guard mean[channel].isFinite,
                      variance[channel].isFinite,
                      (0...1).contains(mean[channel])
                else {
                    throw ScannerNoiseProfileMeasurementError.nonFiniteSample
                }
                channels[channel].add(signal: mean[channel], variance: variance[channel])
            }
        }

        return try ScannerNoiseModel(
            red: channels[0].fit(),
            green: channels[1].fit(),
            blue: channels[2].fit()
        )
    }
}

private struct ChannelAccumulator {
    private struct Bin {
        var signalSum = 0.0
        var varianceSum = 0.0
        var count = 0
    }

    private var bins: [Bin]

    init(binCount: Int) {
        bins = Array(repeating: Bin(), count: binCount)
    }

    mutating func add(signal: Double, variance: Double) {
        let index = min(bins.count - 1, max(0, Int(signal * Double(bins.count))))
        bins[index].signalSum += signal
        bins[index].varianceSum += variance
        bins[index].count += 1
    }

    func fit() throws -> ScannerNoiseChannelModel {
        let observations = bins.compactMap { bin -> (signal: Double, variance: Double, weight: Double)? in
            guard bin.count > 0 else { return nil }
            let weight = Double(bin.count)
            return (bin.signalSum / weight, bin.varianceSum / weight, weight)
        }
        guard observations.count >= 3,
              let minimum = observations.map(\.signal).min(),
              let maximum = observations.map(\.signal).max(),
              maximum > minimum
        else {
            throw ScannerNoiseProfileMeasurementError.insufficientSignalRange
        }

        let totalWeight = observations.reduce(0.0) { $0 + $1.weight }
        let meanSignal = observations.reduce(0.0) { $0 + $1.signal * $1.weight } / totalWeight
        let meanVariance = observations.reduce(0.0) { $0 + $1.variance * $1.weight } / totalWeight
        let covariance = observations.reduce(0.0) {
            $0 + ($1.signal - meanSignal) * ($1.variance - meanVariance) * $1.weight
        }
        let signalVariance = observations.reduce(0.0) {
            $0 + pow($1.signal - meanSignal, 2) * $1.weight
        }
        guard signalVariance > 0 else {
            throw ScannerNoiseProfileMeasurementError.insufficientSignalRange
        }
        let slope = max(0, covariance / signalVariance)
        let intercept = max(0, meanVariance - slope * meanSignal)
        let residual = observations.reduce(0.0) {
            let estimate = slope * $1.signal + intercept
            return $0 + pow($1.variance - estimate, 2) * $1.weight
        }
        let total = observations.reduce(0.0) {
            $0 + pow($1.variance - meanVariance, 2) * $1.weight
        }
        let rSquared = total > 0 ? min(1, max(0, 1 - residual / total)) : 1
        return ScannerNoiseChannelModel(
            shotSlope: slope,
            readIntercept: intercept,
            rSquared: rSquared,
            observedSignalMinimum: minimum,
            observedSignalMaximum: maximum,
            observationCount: Int(totalWeight)
        )
    }
}
