import XCTest
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

extension ImportedImageLoadTests {
    func writeSyntheticPNG(width: Int, height: Int) throws -> URL {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i]     = UInt8(30 + (200 * x / width))
                bytes[i + 1] = UInt8(40 + (150 * y / height))
                bytes[i + 2] = 90
                bytes[i + 3] = 255
            }
        }
        let ctx = CGContext(data: &bytes, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = try XCTUnwrap(ctx.makeImage())
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import_\(UUID().uuidString).png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    func writeSynthetic16BitTIFF(width: Int, height: Int) throws -> URL {
        var samples = [UInt16](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 3
                samples[i]     = UInt16((x * 65535 / width)).bigEndian
                samples[i + 1] = UInt16((y * 65535 / height)).bigEndian
                samples[i + 2] = UInt16(20000).bigEndian
            }
        }
        let data = Data(bytes: samples, count: samples.count * MemoryLayout<UInt16>.size)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 48,
            bytesPerRow: width * 3 * MemoryLayout<UInt16>.size,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import_\(UUID().uuidString).tiff")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    func writeJPEGWithOrientation(width: Int, height: Int, orientation: Int) throws -> URL {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i] = UInt8(20 + 200 * x / width); bytes[i + 1] = 100; bytes[i + 2] = 140; bytes[i + 3] = 255
            }
        }
        let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = try XCTUnwrap(ctx.makeImage())
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("orient_\(UUID().uuidString).jpg")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let props: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    func writeGrayscalePNG(width: Int, height: Int) throws -> URL {
        var bytes = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height { for x in 0..<width { bytes[y * width + x] = UInt8(40 + 180 * x / width) } }
        let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let image = try XCTUnwrap(ctx.makeImage())
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gray_\(UUID().uuidString).png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    func writeUniform16BitTIFF(value: Double, colorSpace: CGColorSpace) throws -> URL {
        let width = 8, height = 8
        let sample = UInt16(min(max(value, 0), 1) * 65535).bigEndian
        var samples = [UInt16](repeating: sample, count: width * height * 3)
        let data = Data(bytes: &samples, count: samples.count * MemoryLayout<UInt16>.size)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 48,
            bytesPerRow: width * 3 * MemoryLayout<UInt16>.size,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import_uniform_\(UUID().uuidString).tiff")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    func renderMidPixelLuma(_ image: CIImage) -> Double {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var px = [Float](repeating: 0, count: 4)
        ctx.render(image, toBitmap: &px, rowBytes: 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1),
                   format: .RGBAf, colorSpace: linear)
        return Double(px[0]) * 0.2126 + Double(px[1]) * 0.7152 + Double(px[2]) * 0.0722
    }

    func varianceOfLuma(_ image: CIImage, width: Int, height: Int) -> (range: Double, mean: Double) {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var buf = [Float](repeating: 0, count: width * height * 4)
        ctx.render(image, toBitmap: &buf, rowBytes: width * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height),
                   format: .RGBAf, colorSpace: linear)
        var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude, sum = 0.0
        var count = 0
        for i in stride(from: 0, to: buf.count, by: 4) {
            let luma = Double(buf[i]) * 0.2126 + Double(buf[i + 1]) * 0.7152 + Double(buf[i + 2]) * 0.0722
            lo = min(lo, luma); hi = max(hi, luma); sum += luma; count += 1
        }
        return (hi - lo, sum / Double(max(count, 1)))
    }
}
