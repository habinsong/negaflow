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

    func testPrintTargetDoesNotInventPaperContrastWithoutMeasuredOutputProfile() {
        let input = syntheticRampWithColorPatch()
        let engine = ChromabaseEngine()
        var mainParams = DevelopParameters()
        mainParams.filmType = .colorPositive

        var printParams = mainParams
        printParams.developTarget = .print

        let main = render(engine.develop(image: input, base: nil, params: mainParams))
        let print = render(engine.develop(image: input, base: nil, params: printParams))

        XCTAssertEqual(main.count, print.count)
        for index in main.indices {
            XCTAssertEqual(main[index], print[index], accuracy: 1e-6, "index=\(index)")
        }
    }

    func testPositivePipelineAutoLevelsRequiresExplicitOptIn() {
        let input = syntheticRampWithColorPatch()
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.46, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.46, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.46, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0.22, y: 0.22, z: 0.22, w: 0),
            ])
            .cropped(to: extent)
        let engine = ChromabaseEngine()

        for filmType in [FilmType.colorPositive, .bwPositive] {
            var disabled = DevelopParameters()
            disabled.filmType = filmType
            XCTAssertFalse(disabled.autoLevels, "Auto Levels must remain opt-in")

            var enabled = disabled
            enabled.autoLevels = true

            let outputDisabled = render(engine.develop(image: input, base: nil, params: disabled))
            let outputEnabled = render(engine.develop(image: input, base: nil, params: enabled))
            let disabledRange = luma(outputDisabled, x: 95, y: 12) - luma(outputDisabled, x: 0, y: 12)
            let enabledRange = luma(outputEnabled, x: 95, y: 12) - luma(outputEnabled, x: 0, y: 12)

            XCTAssertGreaterThan(
                enabledRange,
                disabledRange + 0.12,
                "\(filmType) must apply Auto Levels only after explicit opt-in"
            )
        }
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

}
