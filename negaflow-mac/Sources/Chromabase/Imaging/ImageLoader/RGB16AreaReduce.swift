import Foundation

/// 16bit 인터리브 화상을 면적(상자) 평균으로 목표 크기까지 줄인다.
///
/// LibRaw 는 축소 요청을 받지 못해 늘 원본 화소를 다 돌려준다. 예전에는 그것을 원본 크기 그대로
/// 화소당 8바이트 RGBA16 으로 넓히고(24MP 192MB, 96MP 768MB) Core Image 가 그 위에서 줄였다.
/// 여기서는 LibRaw 버퍼를 읽어 곧바로 목표 크기로 줄이므로 원본 크기 RGBA16 이 만들어지지 않는다.
/// 같은 문제를 Windows 는 `libraw_preview_reduce` 로 푼다.
///
/// 출력 화소는 원본에서 그 칸에 걸친 화소들의 평균이다(가장자리 화소는 걸친 비율만큼만 센다).
/// 상수 화상은 상수로 남고, 정수배 축소는 정확한 k×k 평균이다.
enum RGB16AreaReduce {
    /// - Parameters:
    ///   - channels: 입력 채널 수. 3(LibRaw RGB16) 또는 4(RGBA16, 알파는 무시한다).
    /// - Returns: `targetWidth × targetHeight` RGBA16(알파는 최댓값). 입력이 올바르지 않으면 nil.
    static func reduce(
        _ source: UnsafePointer<UInt16>,
        width: Int, height: Int, channels: Int,
        targetWidth: Int, targetHeight: Int
    ) -> [UInt16]? {
        guard isValid(width: width, height: height, channels: channels,
                      targetWidth: targetWidth, targetHeight: targetHeight) else { return nil }
        var output = [UInt16](repeating: 0, count: targetWidth * targetHeight * 4)
        output.withUnsafeMutableBufferPointer { buffer in
            run(source, width: width, height: height, channels: channels,
                targetWidth: targetWidth, targetHeight: targetHeight, into: buffer.baseAddress!)
        }
        return output
    }

    /// `reduce` 와 같은 화소를 `Data` 에 바로 쓴다. 배열을 거쳐 한 번 더 복사하지 않는다
    /// (3600px 마스터 72MB, 24MP 원본 크기 194MB).
    static func reduceToData(
        _ source: UnsafePointer<UInt16>,
        width: Int, height: Int, channels: Int,
        targetWidth: Int, targetHeight: Int
    ) -> Data? {
        guard isValid(width: width, height: height, channels: channels,
                      targetWidth: targetWidth, targetHeight: targetHeight) else { return nil }
        var output = Data(count: targetWidth * targetHeight * 8)
        output.withUnsafeMutableBytes { raw in
            run(source, width: width, height: height, channels: channels,
                targetWidth: targetWidth, targetHeight: targetHeight,
                into: raw.baseAddress!.assumingMemoryBound(to: UInt16.self))
        }
        return output
    }

    private static func isValid(width: Int, height: Int, channels: Int, targetWidth: Int, targetHeight: Int) -> Bool {
        (channels == 3 || channels == 4)
            && width > 0 && height > 0 && targetWidth > 0 && targetHeight > 0
            && targetWidth <= width && targetHeight <= height
            && targetWidth <= Int.max / targetHeight / 4
    }

    private static func run(
        _ source: UnsafePointer<UInt16>, width: Int, height: Int, channels: Int,
        targetWidth: Int, targetHeight: Int, into output: UnsafeMutablePointer<UInt16>
    ) {
        let job = Job(
            source: source, width: width, height: height, channels: channels,
            targetWidth: targetWidth, targetHeight: targetHeight, output: output
        )
        let bands = max(1, min(targetHeight, ProcessInfo.processInfo.activeProcessorCount * 4))
        DispatchQueue.concurrentPerform(iterations: bands) { band in
            job.run(rows: (band * targetHeight / bands)..<((band + 1) * targetHeight / bands))
        }
    }

    /// 병렬 작업이 공유하는 읽기 전용 입력과, 서로 겹치지 않는 출력 행에만 쓰는 출력 포인터.
    private final class Job: @unchecked Sendable {
        let source: UnsafePointer<UInt16>
        let width: Int, height: Int, channels: Int
        let targetWidth: Int, targetHeight: Int
        let output: UnsafeMutablePointer<UInt16>
        /// 출력 열마다 걸치는 원본 열 범위 `[start, end)` 와 가장자리 가중치. 안쪽 열은 1 이다.
        private var start: [Int], end: [Int]
        private var firstWeight: [Float], lastWeight: [Float], columnSpan: [Float]
        private let rowScale: Double

        init(source: UnsafePointer<UInt16>, width: Int, height: Int, channels: Int,
             targetWidth: Int, targetHeight: Int, output: UnsafeMutablePointer<UInt16>) {
            self.source = source; self.width = width; self.height = height; self.channels = channels
            self.targetWidth = targetWidth; self.targetHeight = targetHeight; self.output = output
            rowScale = Double(height) / Double(targetHeight)
            let columnScale = Double(width) / Double(targetWidth)
            start = [Int](repeating: 0, count: targetWidth)
            end = start
            firstWeight = [Float](repeating: 1, count: targetWidth)
            lastWeight = firstWeight
            columnSpan = firstWeight
            for ox in 0..<targetWidth {
                let left = Double(ox) * columnScale
                let right = min(Double(width), Double(ox + 1) * columnScale)
                let s = Int(left)
                let e = max(s + 1, min(width, Int(right.rounded(.up))))
                start[ox] = s; end[ox] = e
                columnSpan[ox] = Float(right - left)
                if e - s == 1 {
                    firstWeight[ox] = Float(right - left)
                    lastWeight[ox] = firstWeight[ox]
                } else {
                    firstWeight[ox] = Float(Double(s + 1) - left)
                    lastWeight[ox] = Float(right - Double(e - 1))
                }
            }
        }

        func run(rows: Range<Int>) {
            var accumulated = [Float](repeating: 0, count: targetWidth * 3)
            // 행마다 배열의 쓰기 가능 여부를 다시 검사하지 않는다. 작업별로 전용 버퍼를 쓴다.
            accumulated.withUnsafeMutableBufferPointer { buffer in
                let acc = buffer.baseAddress!
                for row in rows {
                    let top = Double(row) * rowScale
                    let bottom = min(Double(height), Double(row + 1) * rowScale)
                    for index in 0..<(targetWidth * 3) { acc[index] = 0 }
                    var sy = Int(top)
                    while Double(sy) < bottom, sy < height {
                        let weightY = Float(min(Double(sy + 1), bottom) - max(Double(sy), top))
                        accumulate(line: source + sy * width * channels, weightY: weightY, into: acc)
                        sy += 1
                    }
                    let rowSpan = Float(bottom - top)
                    let out = output + row * targetWidth * 4
                    for ox in 0..<targetWidth {
                        let norm = 1 / (columnSpan[ox] * rowSpan)
                        for c in 0..<3 {
                            out[ox * 4 + c] = UInt16(min(65535, max(0, acc[ox * 3 + c] * norm + 0.5)))
                        }
                        out[ox * 4 + 3] = .max
                    }
                }
            }
        }

        private func accumulate(line: UnsafePointer<UInt16>, weightY: Float, into acc: UnsafeMutablePointer<Float>) {
            for ox in 0..<targetWidth {
                let s = start[ox], e = end[ox]
                var r: Float = 0, g: Float = 0, b: Float = 0
                for sx in s..<e {
                    let w: Float = sx == s ? firstWeight[ox] : (sx == e - 1 ? lastWeight[ox] : 1)
                    let p = line + sx * channels
                    r += w * Float(p[0]); g += w * Float(p[1]); b += w * Float(p[2])
                }
                acc[ox * 3] += weightY * r
                acc[ox * 3 + 1] += weightY * g
                acc[ox * 3 + 2] += weightY * b
            }
        }
    }
}
