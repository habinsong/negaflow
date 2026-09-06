import XCTest
import CoreImage
import CoreGraphics
import ImageIO
@testable import Chromabase

final class InputGammaInterpretationTests: XCTestCase {
    func testGammaKeepsNumericPrecisionAndRejectsInvalidValues() throws {
        for value in [0.10, 1, 1.2345, 1.8, 2.2, 4] {
            let gamma = try InputGammaInterpretation.power(value)
            XCTAssertEqual(gamma.value, value)
            XCTAssertEqual(try JSONDecoder().decode(InputGammaInterpretation.self,
                from: JSONEncoder().encode(gamma)), gamma)
        }
        for value in [0, -1, 4.01, .nan, .infinity] {
            XCTAssertThrowsError(try InputGammaInterpretation.power(value))
        }
    }

    func testLinearProfilePreservesEveryNonCurveTag() throws {
        let source = SyntheticScannerICCProfile.data()
        let changed = try InputGammaProfile.linearizedData(source)
        let oldTags = tags(source)
        let newTags = tags(changed)
        XCTAssertEqual(Set(oldTags.keys), Set(newTags.keys))
        for (name, payload) in oldTags {
            if ["rTRC", "gTRC", "bTRC"].contains(name) {
                XCTAssertEqual(newTags[name], Data([0x63, 0x75, 0x72, 0x76, 0, 0, 0, 0, 0, 0, 0, 0]))
            } else {
                XCTAssertEqual(newTags[name], payload, name)
            }
        }
        XCTAssertEqual(source, SyntheticScannerICCProfile.data())
    }

    func testExplicitSourceGammaMatchesAnalyticalTransfer() throws {
        let profile = SyntheticScannerICCProfile.data()
        let source = try makeImage(profile: profile)
        let expected = samples(CIImage(cgImage: source))
        let decoded = try InputGammaDecoder.decode(source, sourceICC: profile,
            gamma: .power(SyntheticScannerICCProfile.gamma))
        let analytic = sourceSamples.map { Float(pow(Double($0) / 65535, SyntheticScannerICCProfile.gamma)) }
        let oracle = CIImage(bitmapData: analytic.withUnsafeBytes { Data($0) }, bytesPerRow: 8 * 16,
            size: CGSize(width: 8, height: 4), format: .RGBAf,
            colorSpace: try InputGammaProfile.linearized(profile))
        let reference = samples(oracle)
        // 기존 ColorSync 입력 경로 자체가 power 기준과 약 0.0017 차이를 보입니다.
        // 수동 감마의 정밀도는 CPU power 기준으로 검증하며 자동 경로의 보존은 TIFF 테스트가 담당합니다.
        print("INPUT_GAMMA_ORACLE legacy=\(zip(expected, reference).map { abs($0 - $1) }.max()!) explicit=\(zip(samples(decoded), reference).map { abs($0 - $1) }.max()!)")
        assertClose(samples(decoded), reference, tolerance: 0.00001)
    }

    func testArbitraryGammaOperatesBeforeWorkingColorConversion() throws {
        let adobe = try XCTUnwrap(CGColorSpace(name: CGColorSpace.adobeRGB1998)?.copyICCData() as Data?)
        let source = try makeImage(profile: adobe)
        let linearSpace = try InputGammaProfile.linearized(adobe)
        for gamma in [0.10, 1, 1.8, 2.2, 2.4, 4] {
            let decoded = try InputGammaDecoder.decode(source, sourceICC: adobe, gamma: .power(gamma))
            var expectedPixels = [Float]()
            for value in sourceSamples {
                expectedPixels.append(Float(pow(Double(value) / 65535, gamma)))
            }
            let oracle = CIImage(bitmapData: expectedPixels.withUnsafeBytes { Data($0) }, bytesPerRow: 8 * 16,
                size: CGSize(width: 8, height: 4), format: .RGBAf, colorSpace: linearSpace)
            assertClose(samples(decoded), samples(oracle), tolerance: 0.0001)
        }
    }

    func testTIFFLoaderAndPreviewUseSameInputInterpretation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("gamma.tif")
        let image = try makeImage(profile: SyntheticScannerICCProfile.data())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try ImageLoader.validateInputGammaSource(url)
        let gamma = try InputGammaInterpretation.power(1.8)
        let full = try ImageLoader.loadImportedDecoded(url, inputGamma: gamma)
        let scanner = try ImageLoader.loadScannerTIFFDecoded(url, inputGamma: gamma)
        XCTAssertEqual(full.provenance.inputGamma, gamma)
        XCTAssertEqual(samples(full.image), samples(scanner.image))
        let preview = try XCTUnwrap(ImageLoader.loadImportedPreview(url, maxDimension: 4,
            highResolutionThreshold: 0, inputGamma: gamma))
        XCTAssertTrue(preview.usesLinearSRGB)
        XCTAssertEqual(preview.image.extent.width, 4)
        let reduced = full.image.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: 0.5, kCIInputAspectRatioKey: 1
        ])
        assertClose(samples(preview.image), samples(reduced), tolerance: 0.001)
        let automatic = try ImageLoader.loadImportedDecoded(url, inputGamma: .automatic)
        let legacy = try XCTUnwrap(ImageLoader.loadImportedDecoded(url))
        XCTAssertEqual(samples(automatic.image), samples(legacy.image))
    }

    func testUnsupportedProfileAndMalformedOffsetsFailExplicitly() {
        var lut = SyntheticScannerICCProfile.data()
        lut.replaceSubrange(132..<136, with: Data("A2B0".utf8))
        XCTAssertThrowsError(try InputGammaProfile.linearizedData(lut)) { error in
            XCTAssertEqual(error as? InputGammaDecodeError, .unsupportedProfile)
        }
        var malformed = SyntheticScannerICCProfile.data()
        malformed.replaceSubrange(136..<140, with: [0xff, 0xff, 0xff, 0xfc])
        XCTAssertThrowsError(try InputGammaProfile.linearizedData(malformed))
        XCTAssertThrowsError(try InputGammaProfile.linearizedData(Data(repeating: 0, count: 127)))
    }

    private var sourceSamples: [UInt16] {
        (0..<32).flatMap { i -> [UInt16] in
            let red = UInt16(i * 2000)
            return [red, UInt16(63000 - i * 1500), UInt16(i * 1000 + 1), 65535]
        }
    }

    private func makeImage(profile: Data) throws -> CGImage {
        let space = try XCTUnwrap(CGColorSpace(iccData: profile as CFData))
        let data = sourceSamples.withUnsafeBytes { Data($0) }
        return try XCTUnwrap(CGImage(width: 8, height: 4, bitsPerComponent: 16, bitsPerPixel: 64,
            bytesPerRow: 8 * 8, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
                .union(.byteOrder16Little),
            provider: CGDataProvider(data: data as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent))
    }

    private func samples(_ image: CIImage) -> [Float] {
        let width = Int(image.extent.width.rounded(.down))
        let height = Int(image.extent.height.rounded(.down))
        var output = [Float](repeating: 0, count: width * height * 4)
        ChromabaseEngine.sharedLinearRenderContext.render(image, toBitmap: &output,
            rowBytes: width * 16, bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
        return output
    }

    private func assertClose(_ actual: [Float], _ expected: [Float], tolerance: Float,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        let error = zip(actual, expected).map { abs($0 - $1) }.max() ?? .infinity
        XCTAssertLessThanOrEqual(error, tolerance, file: file, line: line)
    }

    private func tags(_ data: Data) -> [String: Data] {
        func u32(_ offset: Int) -> Int {
            (0..<4).reduce(0) { ($0 << 8) | Int(data[offset + $1]) }
        }
        var result: [String: Data] = [:]
        for i in 0..<u32(128) {
            let start = 132 + i * 12
            let name = String(decoding: data[start..<(start + 4)], as: UTF8.self)
            let offset = u32(start + 4)
            result[name] = data.subdata(in: offset..<(offset + u32(start + 8)))
        }
        return result
    }
}
