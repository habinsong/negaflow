import CoreGraphics
import Foundation

extension InfraredDefectRemoval {
    static func renderClusters(
        defectPixels: [Int],
        width: Int,
        height: Int,
        dilate: Int,
        tile: Int,
        padding: Int
    ) -> [Cluster] {
        guard !defectPixels.isEmpty else { return [] }
        let columnCount = max(1, (width + tile - 1) / tile)
        let rowCount = max(1, (height + tile - 1) / tile)

        final class TileMask {
            let x0: Int
            let y0: Int
            let width: Int
            let height: Int
            var bytes: [UInt8]
            var count = 0

            init(x0: Int, y0: Int, width: Int, height: Int) {
                self.x0 = x0
                self.y0 = y0
                self.width = width
                self.height = height
                bytes = [UInt8](repeating: 0, count: width * height * 4)
            }
        }
        var tiles: [Int: TileMask] = [:]

        func tileRect(_ column: Int, _ row: Int) -> (x0: Int, y0: Int, width: Int, height: Int) {
            let x0 = max(0, column * tile - padding)
            let y0 = max(0, row * tile - padding)
            let x1 = min(width, (column + 1) * tile + padding)
            let y1 = min(height, (row + 1) * tile + padding)
            return (x0, y0, x1 - x0, y1 - y0)
        }

        for pixel in defectPixels {
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
            for row in minimumRow...maximumRow {
                for column in minimumColumn...maximumColumn {
                    let key = row * columnCount + column
                    let mask: TileMask
                    if let existing = tiles[key] {
                        mask = existing
                    } else {
                        let rect = tileRect(column, row)
                        mask = TileMask(
                            x0: rect.x0,
                            y0: rect.y0,
                            width: rect.width,
                            height: rect.height
                        )
                        tiles[key] = mask
                    }
                    let localX0 = max(stampX0, mask.x0)
                    let localX1 = min(stampX1, mask.x0 + mask.width - 1)
                    let localY0 = max(stampY0, mask.y0)
                    let localY1 = min(stampY1, mask.y0 + mask.height - 1)
                    guard localX0 <= localX1, localY0 <= localY1 else { continue }
                    for y in localY0...localY1 {
                        let rowOffset = (y - mask.y0) * mask.width
                        for x in localX0...localX1 {
                            let offset = (rowOffset + x - mask.x0) * 4
                            if mask.bytes[offset] == 0 {
                                mask.bytes[offset] = 255
                                mask.bytes[offset + 1] = 255
                                mask.bytes[offset + 2] = 255
                                mask.bytes[offset + 3] = 255
                                mask.count += 1
                            }
                        }
                    }
                }
            }
        }

        return tiles.keys.sorted().compactMap { key in
            guard let mask = tiles[key], mask.count > 0 else { return nil }
            let region = CGRect(
                x: CGFloat(mask.x0),
                y: CGFloat(height - mask.y0 - mask.height),
                width: CGFloat(mask.width),
                height: CGFloat(mask.height)
            )
            return Cluster(
                roiYup: region,
                maskRGBA8: Data(mask.bytes),
                width: mask.width,
                height: mask.height
            )
        }
    }
}
