import CoreGraphics
import Foundation

extension InfraredDefectRemoval {

    /// 감쇠 창(16bit)과 완전 폐색 코어 마스크를 같은 타일에 담는다.
    ///
    /// 타일은 **유의미한 감쇠가 있는 자리**에서만 만들고, 값은 창 전체를 그대로 옮긴다.
    /// 결함의 옅은 자락은 문턱 아래라도 창 안에 들어오므로(padding 이 3σ 보다 넓다) 함께
    /// 되돌려진다 — 자락을 버리는 것이 "심만 지워지고 자국이 남는" 원인이었다.
    static func renderCorrectionClusters(
        attenuation: [Float],
        corePixels: [Int],
        threshold: Float,
        width: Int,
        height: Int,
        dilate: Int,
        tile: Int,
        padding: Int
    ) -> [Cluster] {
        let columnCount = max(1, (width + tile - 1) / tile)
        let rowCount = max(1, (height + tile - 1) / tile)
        var touched = Set<Int>()
        for y in 0..<height {
            let row = y * width
            let tileRow = min(rowCount - 1, y / tile)
            for x in 0..<width where attenuation[row + x] >= threshold {
                touched.insert(tileRow * columnCount + min(columnCount - 1, x / tile))
            }
        }
        guard !touched.isEmpty else { return [] }

        func window(_ key: Int) -> (x0: Int, y0: Int, width: Int, height: Int) {
            let column = key % columnCount
            let row = key / columnCount
            let x0 = max(0, column * tile - padding)
            let y0 = max(0, row * tile - padding)
            let x1 = min(width, (column + 1) * tile + padding)
            let y1 = min(height, (row + 1) * tile + padding)
            return (x0, y0, x1 - x0, y1 - y0)
        }

        var masks: [Int: [UInt8]] = [:]
        for key in touched {
            let rect = window(key)
            masks[key] = [UInt8](repeating: 0, count: rect.width * rect.height * 4)
        }
        // 코어는 복원 문맥까지 덮도록 팽창해 찍는다(기존 마스크 경로와 같은 규칙).
        for pixel in corePixels {
            let pixelX = pixel % width
            let pixelY = pixel / width
            let stampX0 = max(0, pixelX - dilate)
            let stampX1 = min(width - 1, pixelX + dilate)
            let stampY0 = max(0, pixelY - dilate)
            let stampY1 = min(height - 1, pixelY + dilate)
            let minimumColumn = max(0, (stampX0 - padding) / tile)
            let maximumColumn = min(columnCount - 1, (stampX1 + padding) / tile)
            let minimumRow = max(0, (stampY0 - padding) / tile)
            let maximumRow = min(rowCount - 1, (stampY1 + padding) / tile)
            guard minimumColumn <= maximumColumn, minimumRow <= maximumRow else { continue }
            for row in minimumRow...maximumRow {
              for column in minimumColumn...maximumColumn {
                let key = row * columnCount + column
                guard touched.contains(key) else { continue }
                let rect = window(key)
                let localX0 = max(stampX0, rect.x0)
                let localX1 = min(stampX1, rect.x0 + rect.width - 1)
                let localY0 = max(stampY0, rect.y0)
                let localY1 = min(stampY1, rect.y0 + rect.height - 1)
                guard localX0 <= localX1, localY0 <= localY1 else { continue }
                masks[key]?.withUnsafeMutableBufferPointer { buffer in
                    for y in localY0...localY1 {
                        let rowOffset = (y - rect.y0) * rect.width
                        for x in localX0...localX1 {
                            let offset = (rowOffset + x - rect.x0) * 4
                            buffer[offset] = 255
                            buffer[offset + 1] = 255
                            buffer[offset + 2] = 255
                            buffer[offset + 3] = 255
                        }
                    }
                }
              }
            }
        }

        return touched.sorted().compactMap { key in
            let rect = window(key)
            guard rect.width > 0, rect.height > 0, let mask = masks[key] else { return nil }
            var payload = [UInt16](repeating: 0, count: rect.width * rect.height)
            for y in 0..<rect.height {
                let source = (rect.y0 + y) * width + rect.x0
                let target = y * rect.width
                for x in 0..<rect.width {
                    let value = min(max(attenuation[source + x], 0), 1)
                    payload[target + x] = UInt16((value * 65535).rounded())
                }
            }
            let region = CGRect(
                x: CGFloat(rect.x0),
                y: CGFloat(height - rect.y0 - rect.height),
                width: CGFloat(rect.width),
                height: CGFloat(rect.height)
            )
            return Cluster(
                roiYup: region,
                maskRGBA8: Data(mask),
                attenuationR16: payload.withUnsafeBufferPointer { Data(buffer: $0) },
                width: rect.width,
                height: rect.height
            )
        }
    }
}
