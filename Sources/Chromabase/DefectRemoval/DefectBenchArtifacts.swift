import CoreImage
import Foundation
import ImageIO

// DefectBenchRunner 의 아티팩트 생성(렌더/diff/mask overlay/100% crop/PNG 쓰기).
enum DefectBenchArtifacts {
    /// sRGB RGBA8 로 렌더(행 0 = 이미지 상단). 검출 라벨맵(y-down)과 같은 좌표계다.
    static func renderRGBA8(_ image: CIImage, extent: CGRect) -> [UInt8] {
        let w = Int(extent.width.rounded()), h = Int(extent.height.rounded())
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        DefectContext.render.render(image, toBitmap: &bytes, rowBytes: w * 4,
                                 bounds: extent, format: .RGBA8,
                                 colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return bytes
    }

    /// diff 히트맵(|Δ| 최대 채널 ×6 증폭 그레이) + 변경 픽셀 통계(임계 2/255).
    static func diffHeatmap(before: [UInt8], after: [UInt8], width: Int, height: Int)
        -> (heatmap: [UInt8], changedCount: Int, changedDeltaSum: Double) {
        var out = [UInt8](repeating: 255, count: width * height * 4)
        var changed = 0
        var deltaSum = 0.0
        for i in 0..<(width * height) {
            let o = i * 4
            let d = max(abs(Int(before[o]) - Int(after[o])),
                        max(abs(Int(before[o + 1]) - Int(after[o + 1])),
                            abs(Int(before[o + 2]) - Int(after[o + 2]))))
            let v = UInt8(min(255, d * 6))
            out[o] = v; out[o + 1] = v; out[o + 2] = v; out[o + 3] = 255
            if d > 2 {
                changed += 1
                deltaSum += Double(d) / 255.0
            }
        }
        return (out, changed, deltaSum)
    }

    /// 검출 마스크를 빨강 반투명으로 얹은 오버레이(검출 확인용).
    static func maskOverlay(on before: [UInt8], field: DefectLabelField, width: Int, height: Int) -> [UInt8] {
        var out = before
        guard !field.isEmpty, field.width == width, field.height == height else { return out }
        for i in 0..<(width * height) where field.labels[i] >= 0 {
            let o = i * 4
            out[o] = UInt8(min(255, Int(out[o]) / 3 + 170))
            out[o + 1] = UInt8(Int(out[o + 1]) / 3)
            out[o + 2] = UInt8(Int(out[o + 2]) / 3)
        }
        return out
    }

    /// 큰 컴포넌트 순으로 100% crop(before|after|diff 3연 스트립)을 쓴다. 반환 = 파일 이름들.
    static func writeCrops(field: DefectLabelField, before: [UInt8], after: [UInt8], diff: [UInt8],
                           width: Int, height: Int, name: String, outputDir: URL,
                           cropCount: Int, cropSize: Int) -> [String] {
        guard !field.isEmpty, cropCount > 0 else { return [] }
        let top = field.components.sorted { $0.pixelCount > $1.pixelCount }.prefix(cropCount)
        var files: [String] = []
        for (i, comp) in top.enumerated() {
            let cx = (comp.minX + comp.maxX) / 2
            let cy = (comp.minY + comp.maxY) / 2
            let size = min(cropSize, min(width, height))
            let x0 = max(0, min(width - size, cx - size / 2))
            let y0 = max(0, min(height - size, cy - size / 2))
            let strip = stripCrop(before: before, after: after, diff: diff, width: width,
                                  x0: x0, y0: y0, size: size)
            let file = String(format: "%@-crop%02d-%@-x%d-y%d.png",
                              name, i + 1, comp.classification.rawValue, x0, y0)
            let url = outputDir.appendingPathComponent(file)
            if (try? writePNG(strip, width: size * 3 + 4, height: size, to: url)) != nil {
                files.append(file)
            }
        }
        return files
    }

    /// before|after|diff 를 2px 흰 구분선으로 이어 붙인 스트립.
    private static func stripCrop(before: [UInt8], after: [UInt8], diff: [UInt8], width: Int,
                                  x0: Int, y0: Int, size: Int) -> [UInt8] {
        let outW = size * 3 + 4
        var out = [UInt8](repeating: 255, count: outW * size * 4)
        for (panel, src) in [(0, before), (1, after), (2, diff)] {
            let dstX = panel * (size + 2)
            for y in 0..<size {
                for x in 0..<size {
                    let so = ((y0 + y) * width + x0 + x) * 4
                    let do_ = (y * outW + dstX + x) * 4
                    out[do_] = src[so]; out[do_ + 1] = src[so + 1]
                    out[do_ + 2] = src[so + 2]; out[do_ + 3] = 255
                }
            }
        }
        return out
    }

    static func writePNG(_ rgba: [UInt8], width: Int, height: Int, to url: URL) throws {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = rgba
        let cg: CGImage? = bytes.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
        guard let cg,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw ChromabaseError.writeFailed("PNG 생성 실패: \(url.path)") }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ChromabaseError.writeFailed("PNG 쓰기 실패: \(url.path)")
        }
    }
}
