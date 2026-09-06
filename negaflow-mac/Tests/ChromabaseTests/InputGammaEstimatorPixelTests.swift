import XCTest
import CoreGraphics
import CoreImage
import ImageIO
@testable import Chromabase

final class InputGammaEstimatorPixelTests: XCTestCase {
    func testIntegerPixelAdapterRecoversGammaWithoutResamplingOrColorConversion() throws {
        for bits in [8, 16] {
            for gamma in [0.5, 2.2] {
                let width = 384, height = 256
                var bytes = Data()
                let weights = [0.0, 0, 0, 0, 0.05, 0.15, 0.32, 0.5, 0.7, 0.9, 0.98, 1, 1, 1, 1, 1]
                for y in 0..<height {
                    for x in 0..<width {
                        let offset = Double((x / 16 + y / 16) % 13) * 0.008
                        let a = [0.08 + offset, 0.4 + offset, 0.14 + offset]
                        let b = [0.65 - offset, 0.2 + offset, 0.75 - offset]
                        for c in 0..<3 {
                            let linear = pow(a[c], gamma) + weights[x % 16] * (pow(b[c], gamma) - pow(a[c], gamma))
                            let encoded = pow(linear, 1 / gamma)
                            if bits == 8 { bytes.append(UInt8((encoded * 255).rounded())) }
                            else {
                                let word = UInt16((encoded * 65535).rounded())
                                bytes.append(UInt8(word >> 8)); bytes.append(UInt8(word & 255))
                            }
                        }
                    }
                }
                let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
                let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: bits,
                    bitsPerPixel: bits * 3, bytesPerRow: width * 3 * bits / 8,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
                let estimate = try XCTUnwrap(InputGammaEstimator.estimate(image), "\(bits)-bit gamma \(gamma)")
                XCTAssertEqual(estimate.gamma, gamma, accuracy: bits == 8 ? 0.08 : 0.01)
                XCTAssertLessThanOrEqual(estimate.edgeCount, 512)
                if bits == 16, gamma == 2.2 { try checkAutomaticAndManualAgreement(image) }
            }
        }
    }

    private func checkAutomaticAndManualAgreement(_ image: CGImage) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gamma-edges-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let info = try ImageLoader.inputGammaSourceInfo(url)
        let power = try XCTUnwrap(info.estimatedGamma)
        let automatic = try ImageLoader.loadImportedDecoded(url, inputGamma: .automatic)
        let manual = try ImageLoader.loadImportedDecoded(url, inputGamma: power)
        var params = DevelopParameters()
        params.filmType = .colorNegative
        let engine = ChromabaseEngine()
        let reference = engine.developScanner(image: automatic.image, base: nil, params: params)
        params.inputGamma = power
        var measurements = DevelopSceneMeasurements()
        try InputGammaRenderReference.prepare(source: url, params: params, measurements: &measurements)
        let adjusted = engine.developScanner(image: manual.image, base: nil, params: params, measurements: &measurements)
        let size = image.width * image.height * 4
        var first = [Float](repeating: 0, count: size), second = first
        let space = CGColorSpace(name: CGColorSpace.linearSRGB)
        let context = ChromabaseEngine.sharedLinearRenderContext
        context.render(reference, toBitmap: &first, rowBytes: image.width * 16,
            bounds: reference.extent, format: .RGBAf, colorSpace: space)
        context.render(adjusted, toBitmap: &second, rowBytes: image.width * 16,
            bounds: adjusted.extent, format: .RGBAf, colorSpace: space)
        XCTAssertLessThan(zip(first, second).map { abs($0 - $1) }.max() ?? .infinity, 1e-5)
    }
}
