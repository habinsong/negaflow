import XCTest
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@testable import Chromabase

// MARK: - 가져온 이미지(RAW/DNG/TIFF/PNG/JPG) 로드→현상 경로 검증
//
// 앱의 "이미지 가져오기"는 sourceKind=.importedFile 프레임을 만들고, 현상/익스포트 파이프라인이
// engine.loadImage(= ImageLoader.load, RAW 데모사이크 + 파일 색공간 보존)로 원본을 읽는다.
// 스캐너 TIFF 전용 loadScannerTIFF(16bit linear 강제)와 다른 경로다. 실제 이미지를 쓰지 않고
// 합성 픽스처로 로드 가능성 + 현상 결과의 유효성을 수치로 확인한다.
final class ImportedImageLoadTests: XCTestCase {
    func testImportedPNGLoadsAndDevelops() throws {
        let url = try writeSyntheticPNG(width: 64, height: 48)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(ImageLoader.kind(of: url), .standardImage)
        let loaded = try XCTUnwrap(ImageLoader.load(url, allowRaw: true),
                                   "가져온 PNG는 ImageLoader.load 로 로드되어야 한다.")
        XCTAssertEqual(loaded.extent.width, 64, accuracy: 1)
        XCTAssertEqual(loaded.extent.height, 48, accuracy: 1)

        // engine.loadImage 는 앱의 .importedFile 로더 분기가 호출하는 경로다.
        let viaEngine = try XCTUnwrap(ChromabaseEngine().loadImage(url))
        var params = DevelopParameters()
        params.filmType = .colorNegative
        let developed = ChromabaseEngine().developScanner(
            image: viaEngine,
            base: FilmBase(rgb: SIMD3(0.85, 0.55, 0.38), source: .border),
            params: params
        )
        let stats = varianceOfLuma(developed, width: 64, height: 48)
        XCTAssertGreaterThan(stats.range, 0.01,
                             "가져온 이미지를 현상하면 균일 상수가 아닌 계조 있는 결과가 나와야 한다.")
    }

    func testImported16BitTIFFLoads() throws {
        let url = try writeSynthetic16BitTIFF(width: 32, height: 24)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(ImageLoader.kind(of: url), .standardImage)
        let loaded = try XCTUnwrap(ImageLoader.load(url, allowRaw: true),
                                   "가져온 16bit TIFF는 ImageLoader.load 로 로드되어야 한다.")
        XCTAssertEqual(loaded.extent.width, 32, accuracy: 1)
        XCTAssertEqual(loaded.extent.height, 24, accuracy: 1)
    }

    // MARK: - 제조사 RAW 확장자 분류
    func testManufacturerRawExtensionsClassifiedAsRaw() {
        let rawByVendor = [
            "crw", "cr2", "cr3",   // Canon
            "nef", "nrw",          // Nikon
            "arw", "srf", "sr2",   // Sony
            "raf",                 // Fujifilm
            "rw2", "raw",          // Panasonic
            "orf",                 // Olympus
            "pef",                 // Pentax
            "srw",                 // Samsung
            "3fr", "fff",          // Hasselblad
            "rwl",                 // Leica
            "iiq",                 // Phase One
            "x3f",                 // Sigma
            "dng",                 // Apple/Google/Adobe/Leica
        ]
        for ext in rawByVendor {
            let url = URL(fileURLWithPath: "/tmp/photo.\(ext)")
            XCTAssertEqual(ImageLoader.kind(of: url), .rawDng, "\(ext) 는 RAW로 분류돼야 한다.")
            XCTAssertTrue(ImageLoader.importExtensions.contains(ext), "\(ext) 는 가져오기 지원에 포함돼야 한다.")
        }
        // 대문자 확장자도 동일하게 분류.
        XCTAssertEqual(ImageLoader.kind(of: URL(fileURLWithPath: "/tmp/IMG.CR3")), .rawDng)
        XCTAssertEqual(ImageLoader.kind(of: URL(fileURLWithPath: "/tmp/IMG.NEF")), .rawDng)
    }

    // MARK: - 색상 프로필 / 스캐너 raw 해석
    //
    // VueScan raw TIFF(16bit, 프로필 없음)는 linear(gamma 1.0). loadImported 는 이를 linear 로 해석해야
    // 한다. 반대로 임베디드 프로필(SilverFast HDRi의 SFprofT 등, 일반 sRGB)은 그 프로필로 색관리해야 한다.
    func testNoProfile16BitTIFFInterpretedAsLinear() throws {
        // 프로필 없는 16bit TIFF(값 0.5) → linear 해석 시 linear 작업공간에서 그대로 0.5.
        let url = try writeUniform16BitTIFF(value: 0.5, colorSpace: CGColorSpaceCreateDeviceRGB())
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try XCTUnwrap(ImageLoader.loadImported(url))
        let v = renderMidPixelLuma(image)
        XCTAssertEqual(v, 0.5, accuracy: 0.03,
                       "프로필 없는 16bit(VueScan raw 등)는 linear 로 해석해 값이 보존돼야 한다. got=\(v)")
    }

    func testEmbeddedSRGBProfileIsHonored() throws {
        // 임베디드 sRGB 프로필(값 0.5) → linear 작업공간 렌더 시 sRGB→linear 변환으로 ~0.214.
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let url = try writeUniform16BitTIFF(value: 0.5, colorSpace: srgb)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try XCTUnwrap(ImageLoader.loadImported(url))
        let v = renderMidPixelLuma(image)
        XCTAssertLessThan(v, 0.35,
                          "임베디드 sRGB 프로필은 존중돼(linear로 강제하지 않아) 0.5가 linear ~0.214로 변환돼야 한다. got=\(v)")
    }

    // MARK: - 합성 픽스처 (실제 이미지 미사용)
    private func writeSyntheticPNG(width: Int, height: Int) throws -> URL {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i]     = UInt8(30 + (200 * x / width))       // 수평 그라데이션
                bytes[i + 1] = UInt8(40 + (150 * y / height))      // 수직 그라데이션
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

    private func writeSynthetic16BitTIFF(width: Int, height: Int) throws -> URL {
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

    /// 단색 16bit RGB TIFF를 지정 색공간으로 저장한다(색공간이 sRGB면 ICC 프로필이 임베드된다).
    private func writeUniform16BitTIFF(value: Double, colorSpace: CGColorSpace) throws -> URL {
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

    /// 이미지를 linear 작업공간에서 1픽셀로 렌더해 luma(=단색이므로 채널값)를 얻는다.
    private func renderMidPixelLuma(_ image: CIImage) -> Double {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var px = [Float](repeating: 0, count: 4)
        ctx.render(image, toBitmap: &px, rowBytes: 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1),
                   format: .RGBAf, colorSpace: linear)
        return Double(px[0]) * 0.2126 + Double(px[1]) * 0.7152 + Double(px[2]) * 0.0722
    }

    private func varianceOfLuma(_ image: CIImage, width: Int, height: Int) -> (range: Double, mean: Double) {
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
