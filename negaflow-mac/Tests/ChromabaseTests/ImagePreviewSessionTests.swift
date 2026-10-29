import CoreImage
import ImageIO
import XCTest
@testable import Chromabase

final class ImagePreviewSessionTests: XCTestCase {
    private final class WeakSession {
        weak var value: ImagePreviewSession?
        init(_ value: ImagePreviewSession?) { self.value = value }
    }
    func testTIFFSessionPreservesColorAlphaAndOrientationAndReleasesOwner() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for gray in [false, true] {
            for alpha in gray ? [false] : [false, true] {
                for spaceName in gray ? [CGColorSpace.linearGray] : [CGColorSpace.linearSRGB, CGColorSpace.adobeRGB1998] {
                    let space = try XCTUnwrap(CGColorSpace(name: spaceName))
                    let width = 128, height = 96, channels = gray ? 1 : alpha ? 4 : 3
                    var values = [UInt16](repeating: 0, count: width * height * channels)
                    for i in values.indices { values[i] = UInt16((i * 199) % (alpha ? 30000 : 65536)) }
                    if alpha { for i in stride(from: 3, to: values.count, by: 4) { values[i] = 32768 } }
                    let data = values.withUnsafeBytes { Data($0) }
                    let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
                    let cg = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 16,
                        bitsPerPixel: channels * 16, bytesPerRow: width * channels * 2, space: space,
                        bitmapInfo: CGBitmapInfo(rawValue: (alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : 0)
                            | CGBitmapInfo.byteOrder16Little.rawValue), provider: provider,
                        decode: nil, shouldInterpolate: false, intent: .defaultIntent))
                    let url = root.appendingPathComponent(UUID().uuidString + ".tiff")
                    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
                        "public.tiff" as CFString, 1, nil))
                    CGImageDestinationAddImage(destination, cg, [kCGImagePropertyOrientation: 6] as CFDictionary)
                    XCTAssertTrue(CGImageDestinationFinalize(destination))
                    let original = try Data(contentsOf: url)
                    var session: ImagePreviewSession? = ImagePreviewSession(url: url, inputGamma: .automatic,
                        rawRendering: .sceneLinear, applyOrientation: true)
                    let owner = WeakSession(session)
                    let first = try XCTUnwrap(session?.preview(maxDimension: 64))
                    let settled = try XCTUnwrap(session?.preview(maxDimension: 256))
                    let expected = try ImageLoader.loadImportedDecoded(url, inputGamma: .automatic).image
                    XCTAssertEqual(first.image.extent.size, CGSize(width: 48, height: 64))
                    XCTAssertEqual(settled.image.extent.size, expected.extent.size)
                    session = nil
                    XCTAssertNil(owner.value, "A completed selection must release its decoder")
                    let error = zip(pixels(settled.image), pixels(expected)).reduce(Float(0)) { max($0, abs($1.0 - $1.1)) }
                    XCTAssertLessThan(error, 0.0005, "\(spaceName), alpha=\(alpha)")
                    XCTAssertEqual(try Data(contentsOf: url), original)
                }
            }
        }
    }

    func testAppleRAWSessionMatchesIndependentDecoderAtBothScales() throws {
        guard let path = ProcessInfo.processInfo.environment["NEGAFLOW_APPLE_RAW_SAMPLE"] else {
            throw XCTSkip("Set NEGAFLOW_APPLE_RAW_SAMPLE to a supported DNG")
        }
        let url = URL(fileURLWithPath: path)
        let unsupported = ImagePreviewSession(url: url, inputGamma: try .power(1.8),
            rawRendering: .cameraRendered, applyOrientation: true)
        XCTAssertThrowsError(try unsupported.preview(maxDimension: 1280))
        for rendering: ImageLoader.RAWRendering in [.sceneLinear, .cameraRendered] {
            let session = ImagePreviewSession(url: url, inputGamma: .automatic,
                rawRendering: rendering, applyOrientation: true)
            for dimension: CGFloat in [1280, 3600] {
                let actual = try XCTUnwrap(session.preview(maxDimension: dimension))
                let expected = try XCTUnwrap(ImageLoader.loadImportedPreview(url, maxDimension: dimension,
                    highResolutionThreshold: 0, rawRendering: rendering))
                XCTAssertEqual(actual.image.extent, expected.image.extent)
                let error = zip(pixels(actual.image), pixels(expected.image)).reduce(Float(0)) { max($0, abs($1.0 - $1.1)) }
                XCTAssertLessThan(error, 0.0005)
            }
        }
    }

    private func pixels(_ image: CIImage) -> [Float] {
        var result = [Float](repeating: 0, count: Int(image.extent.width * image.extent.height) * 4)
        ChromabaseEngine.sharedLinearRenderContext.render(image, toBitmap: &result,
            rowBytes: Int(image.extent.width) * 16, bounds: image.extent, format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
        return result
    }
}
