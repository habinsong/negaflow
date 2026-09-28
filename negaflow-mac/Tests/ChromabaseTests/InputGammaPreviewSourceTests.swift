import XCTest
import CoreImage
@testable import Chromabase

final class InputGammaPreviewSourceTests: XCTestCase {
    func testCachedGraphMatchesAuthoritativeDecodeAcrossGammaAndProfiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in [CGColorSpace.linearSRGB, CGColorSpace.adobeRGB1998, CGColorSpace.sRGB] {
            let space = try XCTUnwrap(CGColorSpace(name: name))
            let url = directory.appendingPathComponent(UUID().uuidString + ".tiff")
            var values = [UInt16](repeating: 0, count: 96 * 64 * 3)
            for i in values.indices { values[i] = UInt16((i * 199) % 65536) }
            let data = values.withUnsafeBytes { Data($0) }
            let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
            let cg = try XCTUnwrap(CGImage(width: 96, height: 64, bitsPerComponent: 16, bitsPerPixel: 48,
                bytesPerRow: 96 * 6, space: space, bitmapInfo: [.byteOrder16Little], provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            XCTAssertTrue(ImageLoader.saveScannerTIFF(cg, to: url))
            let bytes = try Data(contentsOf: url)
            let source = try InputGammaPreviewSource(url: url)
            XCTAssertTrue(source.matches(url))
            for value in [0.1, 0.3, 1, 1.8, 2.2, 4] {
                let gamma = try InputGammaInterpretation.power(value)
                for dimension: CGFloat in [32, 96] {
                    let expected = try ImageLoader.loadImportedPreview(url, maxDimension: dimension,
                        highResolutionThreshold: 0, inputGamma: gamma)?.image
                        ?? ImageLoader.loadImportedDecoded(url, inputGamma: gamma).image
                    let actual = try source.image(gamma: gamma, maxDimension: dimension, applyOrientation: true)
                    XCTAssertEqual(actual.extent, expected.extent)
                    let a = pixels(actual), b = pixels(expected)
                    let error = zip(a, b).map { abs($0 - $1) }.max() ?? 0
                    XCTAssertLessThan(error, 0.0005, "\(name) gamma=\(value), size=\(dimension), error=\(error)")
                }
            }
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            try bytes.write(to: url, options: .atomic)
            XCTAssertFalse(source.matches(url))
        }
    }

    /// iCloud 업로드·태그처럼 확장 속성만 바뀌면(ctime 만 변함) 같은 원본으로 봐야 한다.
    func testMetadataOnlyChangeKeepsTheSourceUsable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("frame.tiff")
        let data = Data((0..<(16 * 16 * 6)).map { UInt8(truncatingIfNeeded: $0 &* 37) })
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let cg = try XCTUnwrap(CGImage(width: 16, height: 16, bitsPerComponent: 16, bitsPerPixel: 48,
            bytesPerRow: 16 * 6, space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            bitmapInfo: [.byteOrder16Little], provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        XCTAssertTrue(ImageLoader.saveScannerTIFF(cg, to: url))
        let source = try InputGammaPreviewSource(url: url)
        let before = try InputGammaFileObservation.read(url)

        Thread.sleep(forTimeInterval: 0.01)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        XCTAssertEqual(try InputGammaFileObservation.read(url), before)
        XCTAssertTrue(source.matches(url))
    }

    private func pixels(_ image: CIImage) -> [Float] {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var result = [Float](repeating: 0, count: width * height * 4)
        ChromabaseEngine.sharedLinearRenderContext.render(image, toBitmap: &result, rowBytes: width * 16,
            bounds: image.extent, format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
        return result
    }
}
