import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class PrintTargetTests: XCTestCase {
    private let extent = CGRect(x: 0, y: 0, width: 96, height: 24)
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    ])

    func testDevelopTargetPrintParsingAndMainDefaultStayExplicit() throws {
        XCTAssertEqual(DevelopTarget(rawValue: "print"), .print)
        XCTAssertNil(DevelopTarget(rawValue: "flat"))
        XCTAssertNil(DevelopTarget(rawValue: "sp3000"))

        let decoded = try JSONDecoder().decode(DevelopParameters.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(decoded.developTarget, .main)

        let preferredProfile = ScannerProfileMatcher.preferredProfileID(
            target: .print,
            filmType: .colorNegative,
            filmStockDminID: "kodak-portra-400",
            currentID: nil,
            profiles: ScannerProfileRegistry.loadAll()
        )
        XCTAssertNil(preferredProfile)
    }

    func testPrintTargetAddsFinishedContrastWithoutClippingSyntheticRamp() {
        let input = syntheticRampWithColorPatch()
        let engine = ChromabaseEngine()
        var mainParams = DevelopParameters()
        mainParams.filmType = .colorPositive

        var printParams = mainParams
        printParams.developTarget = .print

        let main = render(engine.develop(image: input, base: nil, params: mainParams))
        let print = render(engine.develop(image: input, base: nil, params: printParams))

        let mainMidContrast = luma(main, x: 63, y: 12) - luma(main, x: 32, y: 12)
        let printMidContrast = luma(print, x: 63, y: 12) - luma(print, x: 32, y: 12)
        XCTAssertGreaterThan(
            printMidContrast,
            mainMidContrast + 0.015,
            "print target should add visible midtone separation without relying on a sample image"
        )

        XCTAssertLessThan(luma(print, x: 95, y: 12), 0.995, "print target must keep highlight headroom")
        XCTAssertGreaterThan(luma(print, x: 0, y: 12), 0.002, "print target must not hard-crush black")

        let mainPatchSaturation = saturation(main, x: 48, y: 12)
        let printPatchSaturation = saturation(print, x: 48, y: 12)
        XCTAssertGreaterThan(
            printPatchSaturation,
            mainPatchSaturation + 0.01,
            "print target should add restrained color density to a synthetic color patch"
        )
    }

    private func syntheticRampWithColorPatch() -> CIImage {
        let width = Int(extent.width)
        let height = Int(extent.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let t = Double(x) / Double(width - 1)
                var r = t
                var g = t
                var b = t
                if (width * 2 / 5)..<(width * 3 / 5) ~= x &&
                    (height / 3)..<(height * 2 / 3) ~= y {
                    r = min(1, t + 0.18)
                    g = max(0, t - 0.04)
                    b = max(0, t - 0.14)
                }
                let i = (y * width + x) * 4
                bytes[i] = UInt8((r * 255).rounded())
                bytes[i + 1] = UInt8((g * 255).rounded())
                bytes[i + 2] = UInt8((b * 255).rounded())
                bytes[i + 3] = 255
            }
        }
        let cg = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!.makeImage()!
        return CIImage(cgImage: cg)
    }

    private func render(_ image: CIImage) -> [Float] {
        let width = Int(extent.width)
        let height = Int(extent.height)
        var out = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &out,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: extent,
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return out
    }

    private func luma(_ pixels: [Float], x: Int, y: Int) -> Double {
        let i = (y * Int(extent.width) + x) * 4
        return Double(pixels[i]) * 0.2126 + Double(pixels[i + 1]) * 0.7152 + Double(pixels[i + 2]) * 0.0722
    }

    private func saturation(_ pixels: [Float], x: Int, y: Int) -> Double {
        let i = (y * Int(extent.width) + x) * 4
        let r = Double(pixels[i])
        let g = Double(pixels[i + 1])
        let b = Double(pixels[i + 2])
        return max(r, max(g, b)) - min(r, min(g, b))
    }
}
