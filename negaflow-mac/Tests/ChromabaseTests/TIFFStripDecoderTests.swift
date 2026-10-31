import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Chromabase

/// 병렬 LZW 디코더는 Image I/O 디코드 + `renderReadyImage` 와 같은 비트를 내야 하고, 맡지 못하는
/// 파일은 nil 로 돌려 원래 경로에 넘겨야 한다.
final class TIFFStripDecoderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TIFFStripDecoderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testImageIOWrittenSixteenBitRGBAMatchesImageIODecode() throws {
        let url = try writeWithImageIO(width: 613, height: 301, bitsPerComponent: 16, alpha: true)
        try assertMatchesImageIO(url)
    }

    /// Image I/O 는 8bit RGB 를 32bit(빈 네 번째 바이트)로 펼친다. 이 디코더는 그 형식을 맡지 않고
    /// 원래 경로가 그대로 처리한다.
    func testEightBitRGBIsLeftToImageIO() throws {
        let url = try writeWithImageIO(width: 517, height: 233, bitsPerComponent: 8, alpha: false)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertNil(TIFFStripDecoder.decode(url, source: source))
        XCTAssertNotNil(ImageLoader.createFullyDecodedImage(source, url: url))
    }

    func testLittleEndianHorizontalPredictorMatchesImageIODecode() throws {
        let rgb = try writeHandmade(width: 97, height: 41, bits: 16, channels: 3, extraSamples: nil,
                                    littleEndian: true, predictor: 2, rowsPerStrip: 5)
        try assertMatchesImageIO(rgb)
        let rgba = try writeHandmade(width: 97, height: 41, bits: 8, channels: 4, extraSamples: 1,
                                     littleEndian: true, predictor: 2, rowsPerStrip: 5)
        try assertMatchesImageIO(rgba)
    }

    func testBigEndianAssociatedAlphaWithPredictorMatchesImageIODecode() throws {
        let url = try writeHandmade(width: 64, height: 29, bits: 16, channels: 4, extraSamples: 1,
                                    littleEndian: false, predictor: 2, rowsPerStrip: 3)
        try assertMatchesImageIO(url)
    }

    func testUnassociatedAlphaIsLeftToImageIO() throws {
        let url = try writeHandmade(width: 32, height: 8, bits: 16, channels: 4, extraSamples: 2,
                                    littleEndian: true, predictor: 1, rowsPerStrip: 4)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertNil(TIFFStripDecoder.decode(url, source: source))
    }

    func testTruncatedStripIsLeftToImageIO() throws {
        let url = try writeHandmade(width: 40, height: 12, bits: 16, channels: 3, extraSamples: nil,
                                    littleEndian: true, predictor: 1, rowsPerStrip: 4, truncateLastStrip: true)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertNil(TIFFStripDecoder.decode(url, source: source))
    }

    // MARK: - Comparison

    private func assertMatchesImageIO(_ url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), file: file, line: line)
        let fast = try XCTUnwrap(TIFFStripDecoder.decode(url, source: source), "decoder declined", file: file, line: line)
        let reference = try XCTUnwrap(CGImageSourceCreateImageAtIndex(
            try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil)), 0,
            [kCGImageSourceShouldCache: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary))
        let ready = ImageLoader.renderReadyImage(reference)
        XCTAssertEqual(fast.bitmapInfo, ready.bitmapInfo, file: file, line: line)
        XCTAssertEqual(fast.bitsPerPixel, ready.bitsPerPixel, file: file, line: line)
        XCTAssertEqual(fast.colorSpace, ready.colorSpace, file: file, line: line)
        XCTAssertEqual(pixels(fast), pixels(ready), file: file, line: line)
        // 공개 경로도 같은 결과를 낸다.
        let viaLoader = try XCTUnwrap(ImageLoader.createFullyDecodedImage(source, url: url))
        XCTAssertEqual(pixels(viaLoader), pixels(ready), file: file, line: line)
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data, let base = CFDataGetBytePtr(data) else { return [] }
        let row = image.width * image.bitsPerPixel / 8
        var out: [UInt8] = []
        out.reserveCapacity(row * image.height)
        for y in 0..<image.height {
            out.append(contentsOf: UnsafeBufferPointer(start: base + y * image.bytesPerRow, count: row))
        }
        return out
    }

    // MARK: - Fixtures

    /// 결정적 의사 난수 화소(LZW 가 짧은 코드와 긴 코드를 모두 내도록 평탄면과 잡음을 섞는다).
    private func sample(_ x: Int, _ y: Int, _ c: Int, max: Int) -> Int {
        if (x / 7 + y / 5) % 3 == 0 { return (c * 9_973) % max }
        var v = UInt64(x &* 73_856_093 ^ y &* 19_349_663 ^ c &* 83_492_791)
        v = (v ^ (v >> 13)) &* 0x5bd1e995
        return Int(v % UInt64(max))
    }

    private func writeWithImageIO(width: Int, height: Int, bitsPerComponent: Int, alpha: Bool) throws -> URL {
        let channels = alpha ? 4 : 3
        let bytesPerSample = bitsPerComponent / 8
        let maximum = 1 << bitsPerComponent
        var bytes = [UInt8](repeating: 0, count: width * height * channels * bytesPerSample)
        for y in 0..<height {
            for x in 0..<width {
                for c in 0..<channels {
                    let value = c == 3 ? maximum - 1 : sample(x, y, c, max: maximum)
                    let at = ((y * width + x) * channels + c) * bytesPerSample
                    if bytesPerSample == 2 {
                        bytes[at] = UInt8(value & 0xFF); bytes[at + 1] = UInt8(value >> 8)
                    } else {
                        bytes[at] = UInt8(value)
                    }
                }
            }
        }
        let alphaInfo: CGImageAlphaInfo = alpha ? .premultipliedLast : .none
        let info = alphaInfo.rawValue | (bytesPerSample == 2 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerComponent * channels, bytesPerRow: width * channels * bytesPerSample,
            space: CGColorSpace(name: CGColorSpace.linearSRGB)!, bitmapInfo: CGBitmapInfo(rawValue: info),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let url = directory.appendingPathComponent("imageio-\(bitsPerComponent)-\(channels).tiff")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5],
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// 리터럴만 내는 LZW(9비트에 머물도록 자주 초기화). 규격에 맞는 스트림이고 어느 디코더든 받는다.
    private func lzwLiterals(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var buffer: UInt32 = 0, count = 0
        func emit(_ code: Int) {
            buffer = buffer << 9 | UInt32(code); count += 9
            while count >= 8 { out.append(UInt8((buffer >> UInt32(count - 8)) & 0xFF)); count -= 8 }
        }
        for (index, byte) in bytes.enumerated() {
            if index % 200 == 0 { emit(256) }
            emit(Int(byte))
        }
        emit(257)
        if count > 0 { out.append(UInt8((buffer << UInt32(8 - count)) & 0xFF)) }
        return out
    }

    private func writeHandmade(width: Int, height: Int, bits: Int, channels: Int, extraSamples: Int?,
                               littleEndian: Bool, predictor: Int, rowsPerStrip: Int,
                               truncateLastStrip: Bool = false) throws -> URL {
        let bytesPerSample = bits / 8
        let maximum = 1 << bits
        // 화소 → (예측기) → 파일 바이트 순서
        var strips: [[UInt8]] = []
        var row0 = 0
        while row0 < height {
            let rows = min(rowsPerStrip, height - row0)
            var raw: [UInt8] = []
            for y in row0..<(row0 + rows) {
                var line = (0..<(width * channels)).map { index -> Int in
                    let c = index % channels
                    return c == 3 ? maximum - 1 : sample(index / channels, y, c, max: maximum)
                }
                if predictor == 2 {
                    for index in stride(from: line.count - 1, through: channels, by: -1) {
                        line[index] = (line[index] - line[index - channels] + maximum) % maximum
                    }
                }
                for value in line {
                    if bytesPerSample == 2 {
                        let low = UInt8(value & 0xFF), high = UInt8(value >> 8)
                        raw += littleEndian ? [low, high] : [high, low]
                    } else {
                        raw.append(UInt8(value))
                    }
                }
            }
            strips.append(lzwLiterals(raw))
            row0 += rows
        }
        if truncateLastStrip, let last = strips.indices.last { strips[last] = Array(strips[last].prefix(strips[last].count / 2)) }

        var file: [UInt8] = []
        func u16(_ v: Int) -> [UInt8] { littleEndian ? [UInt8(v & 0xFF), UInt8(v >> 8)] : [UInt8(v >> 8), UInt8(v & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] {
            let b = [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
            return littleEndian ? b.reversed() : b
        }
        file += littleEndian ? [0x49, 0x49] : [0x4D, 0x4D]
        file += u16(42) + u32(8)
        var entries: [(tag: Int, type: Int, values: [Int])] = [
            (256, 4, [width]), (257, 4, [height]), (258, 3, Array(repeating: bits, count: channels)),
            (259, 3, [5]), (262, 3, [2]), (273, 4, []), (277, 3, [channels]), (278, 4, [rowsPerStrip]),
            (279, 4, strips.map(\.count)), (284, 3, [1]), (317, 3, [predictor]),
        ]
        if let extraSamples { entries.append((338, 3, [extraSamples])) }
        entries.sort { $0.tag < $1.tag }
        let ifdSize = 2 + entries.count * 12 + 4
        var extra: [UInt8] = []
        let extraBase = 8 + ifdSize
        // 스트립 위치는 IFD·바깥 값 뒤에 놓인다. 먼저 바깥 값 크기를 계산한다.
        func outsideSize(_ e: (tag: Int, type: Int, values: [Int])) -> Int {
            let size = (e.type == 3 ? 2 : 4) * (e.tag == 273 ? strips.count : e.values.count)
            return size > 4 ? size : 0
        }
        let outsideTotal = entries.reduce(0) { $0 + outsideSize($1) }
        var stripStart = extraBase + outsideTotal
        let stripOffsets = strips.map { strip -> Int in defer { stripStart += strip.count }; return stripStart }
        var ifd = u16(entries.count)
        for var entry in entries {
            if entry.tag == 273 { entry.values = stripOffsets }
            let encoded = entry.values.flatMap { entry.type == 3 ? u16($0) : u32($0) }
            ifd += u16(entry.tag) + u16(entry.type) + u32(entry.values.count)
            if encoded.count <= 4 {
                ifd += encoded + Array(repeating: 0, count: 4 - encoded.count)
            } else {
                ifd += u32(extraBase + extra.count)
                extra += encoded
            }
        }
        ifd += u32(0)
        file += ifd + extra
        for strip in strips { file += strip }
        let url = directory.appendingPathComponent("handmade-\(bits)-\(channels)-\(littleEndian)-\(predictor)-\(extraSamples ?? 0).tiff")
        try Data(file).write(to: url)
        return url
    }
}
