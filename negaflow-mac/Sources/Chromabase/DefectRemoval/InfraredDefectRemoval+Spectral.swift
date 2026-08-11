import Foundation

extension InfraredDefectRemoval {
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
