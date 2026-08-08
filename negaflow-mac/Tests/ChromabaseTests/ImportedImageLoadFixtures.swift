import XCTest
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

// 가져오기/스캔 경로 테스트가 공유하는 합성 픽스처. 실제 스캔 파일은 쓰지 않는다.
extension XCTestCase {
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

    /// 합성 컬러 네거티브(선형 16bit). 스캐너 소프트웨어의 raw 출력 형태를 흉내낸다 —
    /// 가장자리는 미노광 베이스(Dmin), 안쪽은 밀도 0~1.6의 장면. `colorSpace` 가 nil 이면
    /// 프로필 없는 파일(= 무태그 raw)로 저장한다.
    func writeSyntheticLinearNegativeTIFF(
        width: Int = 96,
        height: Int = 72,
        colorSpace: CGColorSpace? = nil,
        bitsPerComponent: Int = 16
    ) throws -> URL {
        let base = SIMD3<Double>(0.250, 0.140, 0.075)
        let border = 8
        func transmittance(_ x: Int, _ y: Int) -> SIMD3<Double> {
            guard x >= border, y >= border, x < width - border, y < height - border else {
                return base
            }
            let across = Double(x - border) / Double(max(width - 2 * border - 1, 1))
            let down = Double(y - border) / Double(max(height - 2 * border - 1, 1))
            let density = 1.6 * across * (0.55 + 0.45 * down)
            return SIMD3(
                base.x * pow(10, -density),
                base.y * pow(10, -density * 1.08),
                base.z * pow(10, -density * 1.16)
            )
        }

        let space = colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import_negative_\(UUID().uuidString).tiff")
        let image: CGImage
        if bitsPerComponent == 16 {
            var samples = [UInt16](repeating: 0, count: width * height * 3)
            for y in 0..<height {
                for x in 0..<width {
                    let t = transmittance(x, y)
                    let i = (y * width + x) * 3
                    samples[i] = UInt16(min(max(t.x, 0), 1) * 65535).bigEndian
                    samples[i + 1] = UInt16(min(max(t.y, 0), 1) * 65535).bigEndian
                    samples[i + 2] = UInt16(min(max(t.z, 0), 1) * 65535).bigEndian
                }
            }
            let data = Data(bytes: &samples, count: samples.count * MemoryLayout<UInt16>.size)
            let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
            image = try XCTUnwrap(CGImage(
                width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 48,
                bytesPerRow: width * 3 * MemoryLayout<UInt16>.size,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        } else {
            var samples = [UInt8](repeating: 0, count: width * height * 3)
            for y in 0..<height {
                for x in 0..<width {
                    let t = transmittance(x, y)
                    let i = (y * width + x) * 3
                    samples[i] = UInt8(min(max(t.x, 0), 1) * 255)
                    samples[i + 1] = UInt8(min(max(t.y, 0), 1) * 255)
                    samples[i + 2] = UInt8(min(max(t.z, 0), 1) * 255)
                }
            }
            let data = Data(bytes: &samples, count: samples.count)
            let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
            image = try XCTUnwrap(CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                bytesPerRow: width * 3,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        }
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    /// 프로필 없는 16bit PNG. PNG 규격은 태그가 없으면 sRGB 이므로 linear raw 규칙 대상이 아니다.
    func writeUniform16BitPNG(value: Double) throws -> URL {
        let width = 8, height = 8
        let sample = UInt16(min(max(value, 0), 1) * 65535).bigEndian
        var samples = [UInt16](repeating: sample, count: width * height * 3)
        let data = Data(bytes: &samples, count: samples.count * MemoryLayout<UInt16>.size)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 48,
            bytesPerRow: width * 3 * MemoryLayout<UInt16>.size,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import_uniform_\(UUID().uuidString).png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
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
