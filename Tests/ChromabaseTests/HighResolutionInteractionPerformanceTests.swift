import XCTest
import CoreImage
import CoreGraphics
import ImageIO
@testable import Chromabase

final class HighResolutionInteractionPerformanceTests: XCTestCase {
    func test7200DPIEditSequenceStaysResponsive() throws {
        let url = try makeLinearTIFF(width: 4_096, height: 320)
        let preview = try XCTUnwrap(ImageLoader.loadScannerPreview(
            url,
            maxDimension: 1_600,
            highResolutionThreshold: 3_600
        ))

        XCTAssertEqual(preview.sourcePixelSize.width, 4_096)
        XCTAssertLessThanOrEqual(max(preview.image.extent.width, preview.image.extent.height), 1_600.5)
        XCTAssertTrue(preview.usesLinearSRGB)

        let engine = ChromabaseEngine()
        var params = DevelopParameters()
        params.filmType = .colorNegative
        let base = FilmBase(rgb: SIMD3(0.82, 0.56, 0.34), source: .border)
        let rendered = try render(
            engine.developScannerPreview(image: preview.image, base: base, params: params, maxDimension: 1_600)
        )
        XCTAssertGreaterThan(lumaRange(rendered), 0.001)

        var durations: [TimeInterval] = []
        for step in 0..<6 {
            params.exposure = Double(step) * 0.05
            durations.append(try timed {
                _ = try render(engine.developScannerPreview(image: preview.image, base: base, params: params, maxDimension: 1_600))
            })
        }
        XCTAssertLessThan(percentile95(durations), 1.25, "7200dpi preview edits must stay on the bounded preview input, not repeatedly decode/process the full source")
    }

    func testLargeImportedRAWLikeImageEditAndICEPathsStayResponsive() throws {
        let url = try makeLinearTIFF(width: 4_200, height: 280, colorSpace: CGColorSpaceCreateDeviceRGB())
        let preview = try XCTUnwrap(ImageLoader.loadImportedPreview(
            url,
            maxDimension: 1_600,
            highResolutionThreshold: 3_600
        ))

        XCTAssertEqual(preview.sourcePixelSize.width, 4_200)
        XCTAssertLessThanOrEqual(max(preview.image.extent.width, preview.image.extent.height), 1_600.5)
        XCTAssertTrue(preview.usesLinearSRGB)

        let roiImage = gradientImage(width: 1_800, height: 220)
        let roi = CGRect(x: 100, y: 40, width: 1_200, height: 120)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6, scratchSensitivity: 0.7, protectDetail: 0.6)
        let elapsed = timed {
            let field = SoftwareICE.detectComponents(in: roiImage, roi: roi, parameters: params)
            let mask = SoftwareICE.componentMaskBytes(field: field, excluded: [])
            let maskImage = CIImage(
                bitmapData: Data(mask),
                bytesPerRow: field.width * 4,
                size: CGSize(width: field.width, height: field.height),
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
            ).transformed(by: CGAffineTransform(translationX: roi.minX, y: roi.minY))
            _ = SoftwareICE.repair(image: roiImage, roi: roi, mask: maskImage)
        }
        #if DEBUG
        let iceLimit: TimeInterval = 12.0
        #else
        let iceLimit: TimeInterval = 1.25
        #endif
        XCTAssertLessThan(elapsed, iceLimit, "Brush/region ICE representative ROI work should remain ROI-bounded")
    }

    func test3600DPIAndExportContractsRemainUnchanged() throws {
        let url = try makeLinearTIFF(width: 3_600, height: 240)
        XCTAssertNil(ImageLoader.loadScannerPreview(url, maxDimension: 1_600, highResolutionThreshold: 3_600))

        let image = gradientImage(width: 3_600, height: 240)
        XCTAssertEqual(ExportEngine.resized(image, longEdge: nil).extent.width, 3_600)
        XCTAssertEqual(ExportEngine.resized(image, longEdge: 7_200).extent.width, 3_600)
        XCTAssertEqual(ExportEngine.resized(image, longEdge: 1_800).extent.width, 1_800)
    }

    private func makeLinearTIFF(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
    ) throws -> URL {
        var pixels = [UInt16](repeating: UInt16.max, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt16(20_000 + (Double(x) / Double(max(width - 1, 1))) * 30_000)
                pixels[i + 1] = UInt16(14_000 + (Double(y) / Double(max(height - 1, 1))) * 24_000)
                pixels[i + 2] = 9_000
                pixels[i + 3] = UInt16.max
            }
        }
        let data = Data(bytes: pixels, count: pixels.count * MemoryLayout<UInt16>.size)
        let provider = CGDataProvider(data: data as CFData)!
        let cg = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 64,
            bytesPerRow: width * 4 * MemoryLayout<UInt16>.size,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-highres-\(UUID().uuidString).tiff")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, cg, [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5],
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    private func gradientImage(width: Int, height: Int) -> CIImage {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = Float(0.20 + 0.55 * Double(x) / Double(max(width - 1, 1)))
                pixels[i + 1] = Float(0.16 + 0.36 * Double(y) / Double(max(height - 1, 1)))
                pixels[i + 2] = 0.10
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

    private func render(_ image: CIImage) throws -> [UInt8] {
        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!]).render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return pixels
    }

    private func lumaRange(_ pixels: [UInt8]) -> Double {
        var low = 255.0
        var high = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let luma = Double(pixels[index]) * 0.2126
                + Double(pixels[index + 1]) * 0.7152
                + Double(pixels[index + 2]) * 0.0722
            low = min(low, luma)
            high = max(high, luma)
        }
        return high - low
    }

    private func timed(_ body: () throws -> Void) rethrows -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        try body()
        return CFAbsoluteTimeGetCurrent() - start
    }

    private func percentile95(_ values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95)))
        return sorted[index]
    }
}
