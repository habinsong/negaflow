import CoreGraphics
import CoreImage
import ImageIO
import XCTest
import simd
@testable import Chromabase

/// DNG 기록기 시험. 파일을 **기록기와 별개로 짠 최소 TIFF 해석기**로 읽어 태그와 화소를 확인한다.
/// 합성 화상만 쓴다.
final class DNGLinearWriterTests: XCTestCase {
    private let linearSRGB = CGColorSpace(name: CGColorSpace.linearSRGB)!

    // MARK: 시험용 TIFF 해석기(리틀엔디언, 타입별 값 읽기)

    private struct Entry {
        var tag: UInt16
        var type: UInt16
        var count: Int
        var bytes: [UInt8]

        var longs: [UInt32] { stride(0, bytes.count, 4).map { UInt32(le: bytes, at: $0) } }
        var shorts: [UInt16] { stride(0, bytes.count, 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 } }
        var string: String { String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self) }
        var rationals: [Double] {
            stride(0, bytes.count, 8).map { Double(UInt32(le: bytes, at: $0)) / Double(UInt32(le: bytes, at: $0 + 4)) }
        }
        var signedRationals: [Double] {
            stride(0, bytes.count, 8).map {
                Double(Int32(bitPattern: UInt32(le: bytes, at: $0)))
                    / Double(Int32(bitPattern: UInt32(le: bytes, at: $0 + 4)))
            }
        }
        var floats: [Float] { stride(0, bytes.count, 4).map { Float(bitPattern: UInt32(le: bytes, at: $0)) } }

        private func stride(_ from: Int, _ to: Int, _ by: Int) -> [Int] { Swift.stride(from: from, to: to, by: by).map { $0 } }
    }

    private struct Parsed {
        var bytes: [UInt8]
        var ifd0: [UInt16: Entry]
        var exif: [UInt16: Entry]
    }

    private static let typeSize: [UInt16: Int] = [1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 10: 8, 11: 4]

    private func parse(_ url: URL) throws -> Parsed {
        let bytes = [UInt8](try Data(contentsOf: url))
        XCTAssertEqual(Array(bytes[0..<4]), [0x49, 0x49, 42, 0], "리틀엔디언 TIFF 머리말")
        func directory(at offset: Int) -> [UInt16: Entry] {
            let count = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
            var result: [UInt16: Entry] = [:]
            var previousTag = -1
            for index in 0..<count {
                let base = offset + 2 + index * 12
                let tag = UInt16(bytes[base]) | UInt16(bytes[base + 1]) << 8
                XCTAssertGreaterThan(Int(tag), previousTag, "IFD 항목은 태그 오름차순이어야 한다")
                previousTag = Int(tag)
                let type = UInt16(bytes[base + 2]) | UInt16(bytes[base + 3]) << 8
                let n = Int(UInt32(le: bytes, at: base + 4))
                let size = n * Self.typeSize[type]!
                let valueStart = size <= 4 ? base + 8 : Int(UInt32(le: bytes, at: base + 8))
                if size > 4 { XCTAssertEqual(valueStart % 2, 0, "바깥 값은 짝수 오프셋") }
                result[tag] = Entry(tag: tag, type: type, count: n, bytes: Array(bytes[valueStart..<valueStart + size]))
            }
            XCTAssertEqual(UInt32(le: bytes, at: offset + 2 + count * 12), 0, "다음 IFD 없음")
            return result
        }
        let ifd0 = directory(at: Int(UInt32(le: bytes, at: 4)))
        var exif: [UInt16: Entry] = [:]
        if let pointer = ifd0[34665] { exif = directory(at: Int(pointer.longs[0])) }
        return Parsed(bytes: bytes, ifd0: ifd0, exif: exif)
    }

    /// 파일의 줄 데이터(RGB16)를 줄 묶음 오프셋대로 이어 읽는다.
    private func pixels(_ parsed: Parsed) -> [UInt16] {
        let offsets = parsed.ifd0[273]!.longs
        let counts = parsed.ifd0[279]!.longs
        var result: [UInt16] = []
        for (offset, count) in zip(offsets, counts) {
            var i = Int(offset)
            while i < Int(offset) + Int(count) {
                result.append(UInt16(parsed.bytes[i]) | UInt16(parsed.bytes[i + 1]) << 8)
                i += 2
            }
        }
        return result
    }

    // MARK: 합성 입력

    private let width = 53
    private let height = 31

    /// 좌표마다 다른 선형 sRGB 값. 위·아래·좌·우가 뒤집히면 값이 달라지도록 비대칭이다.
    private func value(x: Int, y: Int) -> SIMD3<Float> {
        SIMD3(Float(x) / Float(width - 1), Float(y) / Float(height - 1), Float((x * 7 + y * 3) % 17) / 16)
    }

    private func makeImage() -> CIImage {
        var data = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = value(x: x, y: y)
                let o = (y * width + x) * 4
                data[o] = v.x; data[o + 1] = v.y; data[o + 2] = v.z
            }
        }
        return CIImage(
            bitmapData: Data(bytes: data, count: data.count * 4), bytesPerRow: width * 16,
            size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: linearSRGB)
    }

    private func makeContext() -> CIContext {
        CIContext(options: [.workingColorSpace: linearSRGB, .outputColorSpace: linearSRGB])
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dng-\(UUID().uuidString).dng")
    }

    // MARK: 구조

    func testWritesRequiredDNGTagsAndOneSampleLayout() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try DNGLinearWriter.write(
            makeImage(), to: url, using: makeContext(), metadata: nil,
            options: ExportOptions(), stripBytes: 1_000)
        let file = try parse(url)
        let t = file.ifd0

        XCTAssertEqual(t[256]?.longs, [UInt32(width)])
        XCTAssertEqual(t[257]?.longs, [UInt32(height)])
        XCTAssertEqual(t[258]?.shorts, [16, 16, 16])
        XCTAssertEqual(t[259]?.shorts, [1], "무압축")
        XCTAssertEqual(t[262]?.shorts, [34892], "LinearRaw")
        XCTAssertEqual(t[277]?.shorts, [3])
        XCTAssertEqual(t[274]?.shorts, [1], "Orientation 은 DNG 필수 태그")
        XCTAssertEqual(t[284]?.shorts, [1])
        XCTAssertEqual(t[254]?.longs, [0], "NewSubfileType 0 = 전체 해상도 주 이미지")
        XCTAssertEqual(t[50706]?.bytes, [1, 4, 0, 0])
        XCTAssertEqual(t[50707]?.bytes, [1, 1, 0, 0])
        XCTAssertTrue(t[50708]?.string.hasPrefix("Negaflow") ?? false, "UniqueCameraModel 은 필수이며 제조사 이름을 담는다")
        XCTAssertEqual(t[50717]?.shorts, [65535, 65535, 65535])
        XCTAssertEqual(t[50728]?.rationals, [1, 1, 1], "AsShotNeutral (1,1,1)")
        XCTAssertEqual(t[50778]?.shorts, [21], "CalibrationIlluminant1 = D65")
        XCTAssertEqual(t[50879]?.shorts, [1], "ColorimetricReference = 출력 기준")
        XCTAssertEqual(t[50940]?.floats, [0, 0, 1, 1], "항등 톤 곡선")
        XCTAssertEqual(t[51110]?.longs, [1], "DefaultBlackRender 없음")

        // 줄 묶음: 여러 묶음이고 바이트 수가 이미지 전체와 같다.
        let rowsPerStrip = Int(t[278]!.longs[0])
        XCTAssertEqual(rowsPerStrip, 1_000 / (width * 6))
        let counts = t[279]!.longs.map(Int.init)
        XCTAssertEqual(counts.count, (height + rowsPerStrip - 1) / rowsPerStrip)
        XCTAssertEqual(counts.reduce(0, +), width * height * 6)
        XCTAssertEqual(t[273]!.longs.count, counts.count)
        XCTAssertEqual(Int(t[273]!.longs.last!) + counts.last!, file.bytes.count, "줄 데이터가 파일 끝까지다")
    }

    // MARK: 화소

    func testPixelsRoundTripExactlyInTheSameRowOrder() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try DNGLinearWriter.write(
            makeImage(), to: url, using: makeContext(), metadata: nil,
            options: ExportOptions(colorSpace: .sRGB), stripBytes: 1_000)
        let data = pixels(try parse(url))
        XCTAssertEqual(data.count, width * height * 3)
        var worst = 0
        for y in 0..<height {
            for x in 0..<width {
                let expected = value(x: x, y: y)
                let o = (y * width + x) * 3
                for c in 0..<3 {
                    let reference = Int((Double(expected[c]) * 65535).rounded())
                    worst = max(worst, abs(Int(data[o + c]) - reference))
                }
            }
        }
        // 첫 줄이 화상 맨 위 줄이고 좌우도 뒤집히지 않는다. 16비트 양자화 오차는 1 이내다.
        XCTAssertLessThanOrEqual(worst, 1, "선형 sRGB 화소가 그대로 기록돼야 한다")
    }

    func testWideGamutOutputUsesTheIndependentColorimetryMatrix() throws {
        for space in [ExportColorSpace.displayP3, .adobeRGB] {
            let url = temporaryURL()
            defer { try? FileManager.default.removeItem(at: url) }
            try DNGLinearWriter.write(
                makeImage(), to: url, using: makeContext(), metadata: nil,
                options: ExportOptions(colorSpace: space))
            let file = try parse(url)
            let data = pixels(file)

            // 독립 기준: 선형 sRGB → XYZ(D65) → 대상 RGB. 공개 규격의 sRGB 행렬(IEC 61966-2-1)을 직접 적었다.
            let toXYZ: [[Double]] = [
                [0.4124564, 0.3575761, 0.1804375],
                [0.2126729, 0.7151522, 0.0721750],
                [0.0193339, 0.1191920, 0.9503041],
            ]
            let toTarget = invert(space.dngSpace.rgbToXYZ)
            var worst = 0.0
            for (x, y) in [(0, 0), (52, 0), (0, 30), (52, 30), (17, 9), (30, 21)] {
                let v = value(x: x, y: y)
                let xyz = (0..<3).map { r in (0..<3).reduce(0.0) { $0 + toXYZ[r][$1] * Double(v[$1]) } }
                let o = (y * width + x) * 3
                for c in 0..<3 {
                    let target = (0..<3).reduce(0.0) { $0 + toTarget[c][$1] * xyz[$1] }
                    let clamped = min(max(target, 0), 1)
                    worst = max(worst, abs(Double(data[o + c]) / 65535 - clamped))
                }
            }
            XCTAssertLessThan(worst, 2e-4, "\(space) 변환이 독립 계산과 달라서는 안 된다")

            // ColorMatrix1 은 XYZ → 그 공간의 RGB 이고 백색(D65)을 (1,1,1) 로 보낸다.
            let matrix = file.ifd0[50721]!.signedRationals
            // 백색점 xy = (0.3127, 0.3290) 에서 구한 D65 의 XYZ(Y = 1).
            let white = [0.3127 / 0.3290, 1.0, (1 - 0.3127 - 0.3290) / 0.3290]
            for row in 0..<3 {
                let value = (0..<3).reduce(0.0) { $0 + matrix[row * 3 + $1] * white[$1] }
                XCTAssertEqual(value, 1, accuracy: 2e-4, "D65 백색은 (1,1,1) 이어야 한다")
            }
        }
    }

    private func invert(_ m: simd_double3x3) -> [[Double]] {
        let inverse = m.inverse
        return (0..<3).map { r in (0..<3).map { c in inverse[c][r] } }
    }

    // MARK: 메타데이터

    private func sampleMeta(_ policy: ExportMetadataPolicy) -> ExportMeta {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return ExportMeta(
            scannerMake: "Epson", scannerModel: "V850", resolutionDPI: 3200, filmType: "colorNegative",
            filmStock: "Portra 400", software: "Negaflow 9", sourceDate: date, metadataDate: date,
            sourceMetadata: ExportSourceMetadata(tiff: ["Artist": .string("Kim"), "Copyright": .string("(c) Kim")]),
            metadataPolicy: policy)
    }

    func testMetadataGoesToTIFFAndEXIFTags() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try DNGLinearWriter.write(
            makeImage(), to: url, using: makeContext(), metadata: sampleMeta(.removeLocation), options: ExportOptions())
        let file = try parse(url)
        XCTAssertEqual(file.ifd0[271]?.string, "Epson")
        XCTAssertEqual(file.ifd0[272]?.string, "V850")
        XCTAssertEqual(file.ifd0[305]?.string, "Negaflow 9")
        XCTAssertEqual(file.ifd0[306]?.string, "2023:11:14 22:13:20")
        XCTAssertEqual(file.ifd0[282]?.rationals, [3200])
        XCTAssertEqual(file.ifd0[296]?.shorts, [2])
        XCTAssertEqual(file.ifd0[315]?.string, "Kim")
        XCTAssertEqual(file.ifd0[33432]?.string, "(c) Kim")
        XCTAssertEqual(file.exif[36864]?.bytes, Array("0231".utf8))
        XCTAssertEqual(file.exif[36867]?.string, "2023:11:14 22:13:20")
        XCTAssertEqual(file.exif[36881]?.string, "+00:00", "UTC 로 적은 시각에는 오프셋도 적는다")
        let comment = file.exif[37510]!
        XCTAssertEqual(Array(comment.bytes.prefix(8)), Array("ASCII\0\0\0".utf8))
        XCTAssertEqual(String(decoding: comment.bytes.dropFirst(8), as: UTF8.self),
                       "FilmType: colorNegative; FilmStock: Portra 400")
    }

    /// 정책은 TIFF 내보내기와 같다: minimal 은 사용자가 적은 필름 스톡과 원본 저작권을 싣지 않고,
    /// copyrightOnly 는 저작권만 남기며 장비·날짜·해상도를 적지 않는다.
    func testMetadataPoliciesMatchTheTIFFExportRules() throws {
        let minimalURL = temporaryURL()
        let copyrightURL = temporaryURL()
        defer {
            try? FileManager.default.removeItem(at: minimalURL)
            try? FileManager.default.removeItem(at: copyrightURL)
        }
        try DNGLinearWriter.write(
            makeImage(), to: minimalURL, using: makeContext(), metadata: sampleMeta(.minimal), options: ExportOptions())
        let minimal = try parse(minimalURL)
        XCTAssertEqual(String(decoding: minimal.exif[37510]!.bytes.dropFirst(8), as: UTF8.self), "FilmType: colorNegative")
        XCTAssertNil(minimal.ifd0[315])
        XCTAssertNil(minimal.ifd0[33432])
        XCTAssertEqual(minimal.ifd0[271]?.string, "Epson")

        try DNGLinearWriter.write(
            makeImage(), to: copyrightURL, using: makeContext(), metadata: sampleMeta(.copyrightOnly), options: ExportOptions())
        let copyright = try parse(copyrightURL)
        XCTAssertEqual(copyright.ifd0[315]?.string, "Kim")
        XCTAssertEqual(copyright.ifd0[33432]?.string, "(c) Kim")
        for tag: UInt16 in [271, 272, 305, 306, 282, 283, 296, 34665] {
            XCTAssertNil(copyright.ifd0[tag], "copyrightOnly 는 태그 \(tag) 를 적지 않는다")
        }
        XCTAssertTrue(copyright.exif.isEmpty)
    }

    func testNoMetadataStillWritesSoftwareButNoEXIFIFD() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try DNGLinearWriter.write(makeImage(), to: url, using: makeContext(), metadata: nil, options: ExportOptions())
        let file = try parse(url)
        XCTAssertEqual(file.ifd0[305]?.string, "Negaflow")
        XCTAssertNil(file.ifd0[34665])
        XCTAssertTrue(file.exif.isEmpty)
    }

    // MARK: 실패는 보이게

    func testRejectsAlphaAndPrinterProfiles() throws {
        var options = ExportOptions()
        options.preserveAlpha = true
        XCTAssertThrowsError(try options.validate(for: .dng))

        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let profile = try ICCOutputProfileTestFixture.snapshot()
        XCTAssertThrowsError(try ExportEngine.write(
            makeImage(), to: url, format: .dng, using: makeContext(), outputProfile: profile))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "거절한 내보내기가 파일을 남기면 안 된다")
    }

    /// 무압축 입력(TIFF · 카메라 RAW · DNG · BMP)만 DNG 로 낸다. JPEG · PNG · HEIC 은 확장자로, 확장자가 없거나
    /// 낯설면 파일 내용(UTI)으로 가려낸다.
    func testDNGExportExcludesJPEGPNGAndHEICSources() throws {
        for name in ["a.jpg", "a.JPEG", "a.png", "a.PNG", "a.heic", "a.heif"] {
            XCTAssertTrue(ImageLoader.isExcludedFromDNGExport(URL(fileURLWithPath: "/x/\(name)")), name)
        }
        for name in ["a.tif", "a.TIFF", "a.dng", "a.cr3", "a.nef", "a.arw", "a.raf", "a.bmp"] {
            XCTAssertFalse(ImageLoader.isExcludedFromDNGExport(URL(fileURLWithPath: "/x/\(name)")), name)
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-dng-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var bytes = [UInt8](repeating: 128, count: 8 * 8 * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        for (uti, expectedExcluded) in [("public.jpeg", true), ("public.png", true), ("public.tiff", false)] {
            let url = directory.appendingPathComponent("noext-\(uti)")
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, uti as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            XCTAssertEqual(ImageLoader.isExcludedFromDNGExport(url), expectedExcluded, uti)
        }
    }

    func testRejectsAWorkingSpaceThatIsNotLinearSRGB() throws {
        let p3Context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
        ])
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try DNGLinearWriter.write(
            makeImage(), to: url, using: p3Context, metadata: nil, options: ExportOptions()))
    }
}

private extension UInt32 {
    init(le bytes: [UInt8], at index: Int) {
        self = UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8
            | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
    }
}
