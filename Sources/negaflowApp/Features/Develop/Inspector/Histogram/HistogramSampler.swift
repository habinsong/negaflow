import SwiftUI
import AppKit
import Chromabase

enum HistogramSampler {
    static func compute(_ image: NSImage) -> HistogramBins? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        let directImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        let bitmapImage = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.cgImage
        guard let cg = directImage ?? bitmapImage else { return nil }
        let targetW = 256, scale = Double(targetW) / Double(cg.width)
        let targetH = max(1, Int(Double(cg.height) * scale))
        var px = [UInt8](repeating: 0, count: targetW * targetH * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &px, width: targetW, height: targetH, bitsPerComponent: 8,
            bytesPerRow: targetW * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        let nbins = 64
        var luma = [Int](repeating: 0, count: nbins), r = luma, g = luma, b = luma
        var shadowClips = (red: 0, green: 0, blue: 0)
        var highlightClips = (red: 0, green: 0, blue: 0)
        var totalPixels = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            let alpha = Int(px[i+3])
            guard alpha > 0 else { continue }

            totalPixels += 1
            let red = unpremultiply(px[i], alpha: alpha)
            let green = unpremultiply(px[i+1], alpha: alpha)
            let blue = unpremultiply(px[i+2], alpha: alpha)
            let luminance = Int((0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)).rounded())
            luma[luminance * nbins / 256] += 1
            r[red * nbins / 256] += 1
            g[green * nbins / 256] += 1
            b[blue * nbins / 256] += 1

            if red == 0 { shadowClips.red += 1 }
            if green == 0 { shadowClips.green += 1 }
            if blue == 0 { shadowClips.blue += 1 }
            if red == 255 { highlightClips.red += 1 }
            if green == 255 { highlightClips.green += 1 }
            if blue == 255 { highlightClips.blue += 1 }
        }
        return HistogramBins(
            luma: luma,
            r: r,
            g: g,
            b: b,
            totalPixels: totalPixels,
            shadowClipCounts: shadowClips,
            highlightClipCounts: highlightClips
        )
    }

    private static func unpremultiply(_ component: UInt8, alpha: Int) -> Int {
        min(255, (Int(component) * 255 + alpha / 2) / alpha)
    }
}
