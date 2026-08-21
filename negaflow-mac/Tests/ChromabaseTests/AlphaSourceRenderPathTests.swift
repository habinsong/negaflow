import XCTest
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@testable import Chromabase

// MARK: - 알파 채널이 있는 원본의 렌더 경로
//
// Core Image 가 Image I/O 백킹 CGImage 를 소비할 때, 알파 채널이 있는 이미지는 픽셀을 반복해서
// 다시 읽는 경로로 떨어진다. 5088×3401 16bit RGBA TIFF 실측: 풀해상도 렌더가 LZW 9.5초 /
// 비압축 1.1초 — 같은 크기의 알파 없는 TIFF 는 35ms 였고, 현상 end-to-end 는 19.1초 대 0.86초였다.
// 디코드 결과를 메모리 비트맵으로 한 번 옮기면 그 경로가 끊긴다(현상 19.1초 → 1.2초, 산출물
// 바이트는 동일). 여기서는 그 정규화가 **값을 바꾸지 않는지**를 합성 픽스처로 고정한다.
final class AlphaSourceRenderPathTests: XCTestCase {
    func testAlphaSourceLoadsToTheSamePixelsAsTheAlphaFreeTwin() throws {
        let withAlpha = try writeGradient16BitTIFF(includesAlpha: true)
        let withoutAlpha = try writeGradient16BitTIFF(includesAlpha: false)
        defer {
            try? FileManager.default.removeItem(at: withAlpha)
            try? FileManager.default.removeItem(at: withoutAlpha)
        }

        let a = try XCTUnwrap(ImageLoader.loadImported(withAlpha))
        let b = try XCTUnwrap(ImageLoader.loadImported(withoutAlpha))

        let samplesA = renderSamples(a)
        let samplesB = renderSamples(b)
        XCTAssertEqual(samplesA.count, samplesB.count)
        for (index, value) in samplesA.enumerated() {
            XCTAssertEqual(
                value, samplesB[index], accuracy: 1.0 / 255.0,
                "알파 유무만 다른 같은 픽셀이 다른 값으로 읽히면 안 된다(index \(index))."
            )
        }
    }

    func testRenderReadyImageReplacesAlphaBackedImagesAndLeavesOthersUntouched() throws {
        let alphaURL = try writeGradient16BitTIFF(includesAlpha: true)
        let plainURL = try writeGradient16BitTIFF(includesAlpha: false)
        defer {
            try? FileManager.default.removeItem(at: alphaURL)
            try? FileManager.default.removeItem(at: plainURL)
        }

        let decodedAlpha = try decodeFully(alphaURL)
        let normalized = ImageLoader.renderReadyImage(decodedAlpha)
        XCTAssertFalse(
            normalized === decodedAlpha,
            "알파가 있는 디코드 결과는 메모리 비트맵으로 옮겨져야 한다."
        )
        XCTAssertEqual(normalized.width, decodedAlpha.width)
        XCTAssertEqual(normalized.height, decodedAlpha.height)
        XCTAssertEqual(
            normalized.bitsPerComponent, decodedAlpha.bitsPerComponent,
            "정규화가 비트 깊이를 낮추면 16bit 정밀도가 사라진다."
        )

        let decodedPlain = try decodeFully(plainURL)
        XCTAssertTrue(
            ImageLoader.renderReadyImage(decodedPlain) === decodedPlain,
            "알파가 없으면 원본 디코드 결과를 그대로 쓴다 — 기존 입력에 비용을 붙이지 않는다."
        )
    }

    func testNormalizedAlphaImageKeepsEveryChannelValue() throws {
        let alphaURL = try writeGradient16BitTIFF(includesAlpha: true)
        defer { try? FileManager.default.removeItem(at: alphaURL) }
        let decoded = try decodeFully(alphaURL)
        let normalized = ImageLoader.renderReadyImage(decoded)

        let before = renderSamples(CIImage(cgImage: decoded))
        let after = renderSamples(CIImage(cgImage: normalized))
        XCTAssertEqual(before.count, after.count)
        for (index, value) in before.enumerated() {
            XCTAssertEqual(
                value, after[index], accuracy: 1.0 / 65535.0,
                "정규화는 채널 값을 그대로 옮겨야 한다(index \(index))."
            )
        }
    }

    func testSavedScannerRawDropsAlphaSoTheSlowPathNeverComesBack() throws {
        // Core Image 그래프(회전·크롭·합성)를 지나면 RGBA16 출력이 premultipliedLast 로 나온다.
        // 그대로 저장하면 4채널 raw 가 되고, 그 파일을 읽는 모든 경로가 느린 쪽에 걸린 채
        // 다시 구울 때마다 4채널이 유지됐다(실기: 같은 폴더 15장 중 6장이 그 상태였다).
        let sourceURL = try writeGradient16BitTIFF(includesAlpha: false)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let decoded = try decodeFully(sourceURL)
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let context = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        let source = CIImage(cgImage: decoded, options: [.colorSpace: linear])
        let transformed = source
            .oriented(.right)
            .cropped(to: source.extent.insetBy(dx: 2, dy: 2))
        let rendered = try XCTUnwrap(context.createCGImage(
            transformed, from: transformed.extent, format: .RGBA16, colorSpace: linear
        ))
        XCTAssertEqual(
            rendered.alphaInfo, .premultipliedLast,
            "이 전제가 깨지면(알파가 안 붙으면) 아래 검증의 의미가 사라진다."
        )

        let savedURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alpha_path_saved_\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: savedURL) }
        XCTAssertTrue(ImageLoader.saveScannerTIFF(rendered, to: savedURL))

        let reloaded = try decodeFully(savedURL)
        XCTAssertFalse(
            [CGImageAlphaInfo.premultipliedLast, .premultipliedFirst, .last, .first]
                .contains(reloaded.alphaInfo),
            "저장된 raw 는 알파를 갖지 않아야 한다(alphaInfo=\(reloaded.alphaInfo.rawValue))."
        )
        XCTAssertEqual(reloaded.width, rendered.width)
        XCTAssertEqual(reloaded.height, rendered.height)
        XCTAssertEqual(reloaded.bitsPerComponent, 16, "raw 저장은 16bit 정밀도를 유지한다.")

        let before = renderSamples(CIImage(cgImage: rendered))
        let after = renderSamples(CIImage(cgImage: reloaded))
        XCTAssertEqual(before.count, after.count)
        for (index, value) in before.enumerated() {
            XCTAssertEqual(
                value, after[index], accuracy: 1.0 / 255.0,
                "알파를 벗기면서 픽셀 값이 바뀌면 안 된다(index \(index))."
            )
        }
    }

    // MARK: - 픽스처

    /// 대각 그라디언트 16bit TIFF. `includesAlpha` 면 불투명 알파 채널을 붙여 저장한다
    /// (스캐너/편집 소프트웨어가 내놓는 RGBA16 raw 의 형태).
    private func writeGradient16BitTIFF(includesAlpha: Bool) throws -> URL {
        let width = 32, height = 24
        let componentCount = includesAlpha ? 4 : 3
        var samples = [UInt16](repeating: 0, count: width * height * componentCount)
        for y in 0..<height {
            for x in 0..<width {
                let across = Double(x) / Double(width - 1)
                let down = Double(y) / Double(height - 1)
                let index = (y * width + x) * componentCount
                samples[index] = UInt16(min(max(across, 0), 1) * 65535).bigEndian
                samples[index + 1] = UInt16(min(max(down, 0), 1) * 65535).bigEndian
                samples[index + 2] = UInt16(min(max((across + down) * 0.5, 0), 1) * 65535).bigEndian
                if includesAlpha { samples[index + 3] = UInt16(65535).bigEndian }
            }
        }
        let data = Data(bytes: &samples, count: samples.count * MemoryLayout<UInt16>.size)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let alphaInfo: CGImageAlphaInfo = includesAlpha ? .premultipliedLast : .none
        let image = try XCTUnwrap(CGImage(
            width: width, height: height,
            bitsPerComponent: 16, bitsPerPixel: 16 * componentCount,
            bytesPerRow: width * componentCount * MemoryLayout<UInt16>.size,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alpha_path_\(UUID().uuidString).tiff")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.tiff.identifier as CFString, 1, nil
        ))
        // 실기에서 느렸던 파일과 같은 형태로 저장한다(LZW 압축 + 알파).
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5],
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// 로더와 같은 옵션으로 디코드한다(지연 디코드 대신 즉시 캐시).
    private func decodeFully(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary))
    }

    /// 격자 표본의 RGB 값(sRGB 8bit 도메인, 0...1). 두 경로가 같은 픽셀을 읽는지 비교한다.
    private func renderSamples(_ image: CIImage) -> [Double] {
        let context = CIContext(options: [.cacheIntermediates: false])
        let extent = image.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            context.render(
                image, toBitmap: raw.baseAddress!, rowBytes: width * 4,
                bounds: extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            )
        }
        var samples: [Double] = []
        for y in stride(from: 0, to: height, by: 5) {
            for x in stride(from: 0, to: width, by: 5) {
                let offset = (y * width + x) * 4
                samples.append(Double(buffer[offset]) / 255.0)
                samples.append(Double(buffer[offset + 1]) / 255.0)
                samples.append(Double(buffer[offset + 2]) / 255.0)
            }
        }
        return samples
    }
}
