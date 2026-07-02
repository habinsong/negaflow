import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class ScannerPreviewDevelopTests: XCTestCase {
    func testScannerPreviewDevelopUsesBoundedImageExtent() throws {
        let input = gradientScannerImage(width: 400, height: 240)
        var params = DevelopParameters()
        params.filmType = .colorNegative

        let preview = ChromabaseEngine().developScannerPreview(
            image: input,
            base: FilmBase(rgb: SIMD3(0.82, 0.56, 0.34), source: .border),
            params: params,
            maxDimension: 80
        )

        XCTAssertEqual(preview.extent.width, 80, accuracy: 0.5)
        XCTAssertEqual(preview.extent.height, 48, accuracy: 0.5)
        XCTAssertGreaterThan(renderedLumaRange(preview), 0.001)
    }

    func testScannerPreviewDevelopBoundsOpticFilm7200Frame() {
        let input = CIImage(color: CIColor(red: 0.70, green: 0.46, blue: 0.28))
            .cropped(to: CGRect(x: 0, y: 0, width: 10_300, height: 7_087))
        var params = DevelopParameters()
        params.filmType = .colorNegative

        let preview = ChromabaseEngine().developScannerPreview(
            image: input,
            base: FilmBase(rgb: SIMD3(0.82, 0.56, 0.34), source: .border),
            params: params,
            maxDimension: 1_600
        )

        XCTAssertLessThanOrEqual(max(preview.extent.width, preview.extent.height), 1_600.5)
    }

    private func gradientScannerImage(width: Int, height: Int) -> CIImage {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = Float(0.22 + 0.60 * Double(x) / Double(max(width - 1, 1)))
                pixels[i + 1] = Float(0.16 + 0.45 * Double(y) / Double(max(height - 1, 1)))
                pixels[i + 2] = 0.11
                pixels[i + 3] = 1
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
    }

    private func renderedLumaRange(_ image: CIImage) -> Double {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let context = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: image.extent,
            format: .RGBAf,
            colorSpace: linear
        )
        var low = Double.greatestFiniteMagnitude
        var high = -Double.greatestFiniteMagnitude
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let luma = Double(pixels[index]) * 0.2126
                + Double(pixels[index + 1]) * 0.7152
                + Double(pixels[index + 2]) * 0.0722
            low = min(low, luma)
            high = max(high, luma)
        }
        return high - low
    }
}
