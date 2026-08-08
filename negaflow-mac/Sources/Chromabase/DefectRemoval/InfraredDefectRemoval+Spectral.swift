import Foundation

extension InfraredDefectRemoval {
    /// RGB 장면 구조가 IR 평면에 남긴 저주파 누설만 제거한다.
    ///
    /// red 값의 로그 구간마다 IR의 절사 평균을 구해 비모수 보정 곡선을 만든다. 먼지처럼
    /// 드문 어두운 표본은 구간 하위 10% 절사에서 빠지고, 곡선의 절대 밝기는 중앙값으로
    /// 보존된다. 특정 스캐너 백엔드나 외부 IR 구현의 회귀식·상수에 의존하지 않는다.
    static func removeSceneLeakage(
        ir: inout [Float],
        red: [Float],
        excluded: [Bool],
        n: Int
    ) {
        let targetSamples = 131_072
        let stride = max(1, n / targetSamples)
        var xSamples: [Float] = []
        var ySamples: [Float] = []
        xSamples.reserveCapacity(targetSamples)
        ySamples.reserveCapacity(targetSamples)
        var index = 0
        while index < n {
            if !excluded[index], red[index].isFinite, ir[index].isFinite {
                xSamples.append(log(max(red[index], 1e-4)))
                ySamples.append(ir[index])
            }
            index += stride
        }
        guard xSamples.count > 1_024 else { return }

        let xLow = percentileOf(xSamples, q: 0.01)
        let xHigh = percentileOf(xSamples, q: 0.99)
        let xSpan = xHigh - xLow
        guard xSpan.isFinite, xSpan > 1e-4 else { return }

        let binCount = 64
        var buckets = [[Float]](repeating: [], count: binCount)
        for sample in xSamples.indices {
            let coordinate = min(
                Float(binCount - 1),
                max(0, (xSamples[sample] - xLow) / xSpan * Float(binCount - 1))
            )
            buckets[Int(coordinate.rounded(.down))].append(ySamples[sample])
        }

        var control = [Float?](repeating: nil, count: binCount)
        var occupied = 0
        for bin in buckets.indices where buckets[bin].count >= 24 {
            let sorted = buckets[bin].sorted()
            let lower = sorted.count / 10
            let upper = max(lower + 1, sorted.count - sorted.count / 10)
            var sum: Double = 0
            for value in sorted[lower..<upper] {
                sum += Double(value)
            }
            control[bin] = Float(sum / Double(upper - lower))
            occupied += 1
        }
        guard occupied >= 8 else { return }

        var curve = [Float](repeating: 0, count: binCount)
        let populated = control.indices.filter { control[$0] != nil }
        guard let first = populated.first, let last = populated.last else { return }
        for bin in 0...first { curve[bin] = control[first]! }
        for pair in zip(populated, populated.dropFirst()) {
            let left = pair.0
            let right = pair.1
            let leftValue = control[left]!
            let rightValue = control[right]!
            let distance = Float(right - left)
            for bin in left...right {
                let amount = Float(bin - left) / distance
                curve[bin] = leftValue + (rightValue - leftValue) * amount
            }
        }
        for bin in last..<binCount { curve[bin] = control[last]! }

        // 구간 표본의 작은 요동이 픽셀별 보정 무늬가 되지 않도록 짧은 대칭 커널로 두 번 평활한다.
        for _ in 0..<2 {
            var smoothed = curve
            for bin in 1..<(binCount - 1) {
                smoothed[bin] = (curve[bin - 1] + 2 * curve[bin] + curve[bin + 1]) * 0.25
            }
            curve = smoothed
        }

        let reference = percentileOf(curve, q: 0.5)
        for pixel in 0..<n {
            let redValue = red[pixel].isFinite ? red[pixel] : 1e-4
            let x = log(max(redValue, 1e-4))
            let coordinate = min(
                Float(binCount - 1),
                max(0, (x - xLow) / xSpan * Float(binCount - 1))
            )
            let left = Int(coordinate.rounded(.down))
            let right = min(binCount - 1, left + 1)
            let amount = coordinate - Float(left)
            let predicted = curve[left] + (curve[right] - curve[left]) * amount
            ir[pixel] -= predicted - reference
        }
    }

    static func markBorderConnectedDark(
        _ plane: [Float],
        width: Int,
        height: Int,
        threshold: Float,
        rim: Int,
        excluded: inout [Bool]
    ) {
        let count = width * height
        var dark = [Bool](repeating: false, count: count)
        for index in 0..<count where plane[index] < threshold { dark[index] = true }
        var margin = [Bool](repeating: false, count: count)
        var stack: [Int] = []
        func push(_ index: Int) {
            if dark[index], !margin[index] {
                margin[index] = true
                stack.append(index)
            }
        }
        for x in 0..<width { push(x); push((height - 1) * width + x) }
        for y in 0..<height { push(y * width); push(y * width + width - 1) }
        while let index = stack.popLast() {
            let x = index % width
            let y = index / width
            if x > 0 { push(index - 1) }
            if x < width - 1 { push(index + 1) }
            if y > 0 { push(index - width) }
            if y < height - 1 { push(index + width) }
        }
        dark = []
        stack = []
        guard rim > 0 else {
            for index in 0..<count where margin[index] { excluded[index] = true }
            return
        }
        // Bool 도메인 팽창 — 0/1 Float 평면 + morphMax(8·N bytes 임시)와 결과 동일.
        let dilated = DefectMorphology.dilateMask(
            margin, width: width, height: height, radius: rim
        )
        for index in 0..<count where dilated[index] { excluded[index] = true }
    }

    static func percentile(_ values: [Float], excluded: [Bool], q: Double) -> Float {
        let stride = max(1, values.count / 100_000)
        var samples: [Float] = []
        samples.reserveCapacity(values.count / stride + 1)
        var index = 0
        while index < values.count {
            if !excluded[index] { samples.append(values[index]) }
            index += stride
        }
        return percentileOf(samples, q: q)
    }

    static func percentileOf(_ samples: [Float], q: Double) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * q)))
        return sorted[index]
    }

}
