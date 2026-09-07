import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

final class CustomColorTargetTests: XCTestCase {
    struct Reference: Decodable {
        let id: String
        let samples: [Sample]
        struct Sample: Decodable {
            let name: String
            let input: [Double]
            let expected: [Double]
            var lab: ColorTargetLab {
                let angle = input[2] * .pi / 180
                return ColorTargetLab(l: input[0], a: input[1] * cos(angle), b: input[1] * sin(angle))
            }
        }
    }
    private struct Fixtures: Decodable { let targets: [Reference] }
    private let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private lazy var context = CIContext(options: [.workingColorSpace: linear, .workingFormat: CIFormat.RGBAf])

    private func references() throws -> [Reference] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "CustomColorTargets", withExtension: "json"))
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url)).targets
    }

    func testAllTargetsRoundTripWithDistinctRecipeHashesAndNoLegacyAliases() throws {
        var hashes = Set<String>()
        for target in DevelopTarget.customTargets {
            var params = DevelopParameters()
            params.developTarget = target
            let bytes = try JSONEncoder().encode(params)
            let restored = try JSONDecoder().decode(DevelopParameters.self, from: bytes)
            XCTAssertEqual(restored.developTarget, target)
            XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains(target.rawValue))
            hashes.insert(try RenderManifest.developRecipeSHA256(for: restored))
            XCTAssertFalse(target.isScannerEmulation)
            XCTAssertTrue(ScannerProfileMatcher.matchingProfiles(
                target: target, filmType: .colorNegative, profiles: ScannerProfileRegistry.loadAll()
            ).isEmpty)
        }
        XCTAssertEqual(hashes.count, 18)
        XCTAssertEqual(DevelopTarget.allCases.count, 25)
        for rejected in ["cs", "custom", "leica", "fujifilm", "hasselblad", "kodak", "kodachrome", "chrome", "prism", "retro-8090"] {
            XCTAssertNil(DevelopTarget(rawValue: rejected))
        }
        XCTAssertEqual(DevelopParameters().developTarget, .main)
    }

    func testPortraitLandscapeAndExtendedCoordinatesMatchIndependentReference() throws {
        for ref in try references() {
            let profile = try XCTUnwrap(CustomColorTarget.profile(for: try XCTUnwrap(DevelopTarget(rawValue: ref.id))))
            for sample in ref.samples {
                let actual = CustomColorTargetMath.evaluate(sample.lab, profile: profile)
                for (value, expected) in zip([actual.l, actual.a, actual.b], sample.expected) {
                    XCTAssertEqual(value, expected, accuracy: 0.0001, "\(ref.id): \(sample.name)")
                }
            }
        }
    }

    func testToneAndChromaCompressionHaveNoPlateausOrReversals() {
        for profile in CustomColorTarget.profiles {
            var previous = CustomColorTargetMath.tone(-5, profile: profile)
            for i in -499...12500 {
                let value = CustomColorTargetMath.tone(Double(i) / 100, profile: profile)
                XCTAssertGreaterThan(value, previous, profile.target.rawValue)
                previous = value
            }
            XCTAssertLessThan(CustomColorTargetMath.tone(100, profile: profile), 100)
            XCTAssertGreaterThan(CustomColorTargetMath.tone(100, profile: profile), 95)
        }
        var previous = 0.0
        for i in 1...20000 {
            let value = CustomColorTargetMath.chromaRolloff(Double(i) / 100)
            XCTAssertGreaterThan(value, previous)
            previous = value
        }
        XCTAssertEqual(CustomColorTargetMath.chromaRolloff(48), 48)
        XCTAssertEqual(CustomColorTargetMath.chromaRolloff(80), 67.2, accuracy: 1e-10)
    }

    func testMetalActuallyCompilesAndMatchesReferenceIncludingAlphaAndNonzeroExtent() throws {
        XCTAssertNotNil(CustomColorTargetKernel.kernel, CustomColorTargetKernel.source)
        var fingerprints = Set<[Int]>()
        for ref in try references() {
            let target = try XCTUnwrap(DevelopTarget(rawValue: ref.id))
            let colors = ref.samples.map { ColorTargetColorimetry.labD50ToLinearSRGB($0.lab) }
            let alpha: Float = 0.4
            let input = image(colors, alpha: alpha).transformed(by: CGAffineTransform(translationX: 17, y: -9))
            let result = CustomColorTarget.apply(to: input, target: target)
            XCTAssertEqual(result.extent, input.extent)
            let pixels = render(result)
            for (index, sample) in ref.samples.enumerated() {
                let expected = ColorTargetColorimetry.labD50ToLinearSRGB(
                    ColorTargetLab(l: sample.expected[0], a: sample.expected[1], b: sample.expected[2])
                )
                for channel in 0..<3 {
                    XCTAssertEqual(Double(pixels[index * 4 + channel] / alpha), expected[channel],
                                   accuracy: 0.0003, "\(ref.id) \(sample.name) channel=\(channel)")
                }
                XCTAssertEqual(pixels[index * 4 + 3], alpha, accuracy: 1e-6)
            }
            fingerprints.insert(pixels.map { Int(($0 * 10000).rounded()) })
            let transparent = render(CustomColorTarget.apply(to: image([SIMD3(0.3, 0.2, 0.1)], alpha: 0), target: target))
            XCTAssertEqual(transparent, [0, 0, 0, 0])
        }
        XCTAssertEqual(fingerprints.count, 18)
    }

    func testCPUFallbackMatchesMetalAndPreservesCropRegion() throws {
        let colors: [SIMD3<Double>] = (0..<96).map { i in
            let r = Double(i) / 70.0 - 0.1
            let g = Double(i % 17) / 16.0
            let b = Double(i % 11) / 8.0
            return SIMD3(r, g, b)
        }
        let input = image(colors, alpha: 0.7, width: 12).transformed(by: CGAffineTransform(translationX: -23, y: 31))
        let crop = CGRect(x: -17, y: 33, width: 6, height: 4)
        for target in DevelopTarget.customTargets {
            let cpu = render(CustomColorTarget.applyCPU(to: input, target: target).cropped(to: crop))
            let metal = render(CustomColorTarget.apply(to: input, target: target).cropped(to: crop))
            for (a, b) in zip(cpu, metal) { XCTAssertEqual(a, b, accuracy: 0.0003, target.rawValue) }
        }
    }

    func testExistingTargetsAreExactPassThroughAtCustomStage() {
        let input = image([SIMD3(-0.05, 0.2, 1.2), SIMD3(0.5, 0.2, 0.1)], alpha: 1)
        for target in DevelopTarget.standardTargets {
            XCTAssertTrue(CustomColorTarget.apply(to: input, target: target) === input)
        }
    }

    func testCustomRunsOnceAfterCalibrationForPositiveDigitalAndNegative() {
        let input = image((0..<48).map { i in SIMD3(0.05 + Double(i) / 70, 0.15 + Double(i % 9) / 20, 0.12 + Double(i % 7) / 16) }, alpha: 1)
        let engine = ChromabaseEngine()
        for kind in [FilmType.colorPositive, .colorNegative] {
            for digital in [false, true] where kind == .colorPositive || !digital {
                var main = DevelopParameters()
                main.filmType = kind
                main.isDigitalSource = digital ? true : nil
                main.exposure = 0.15
                main.calibration.redHue = 0.15
                let base = kind == .colorNegative ? FilmBase(rgb: SIMD3(0.86, 0.68, 0.5), source: .manual) : nil
                let baseline = engine.develop(image: input, base: base, params: main)
                for target in DevelopTarget.customTargets {
                    var params = main
                    params.developTarget = target
                    let actual = render(engine.develop(image: input, base: base, params: params))
                    let expected = render(CustomColorTarget.apply(to: baseline, target: target))
                    for (a, b) in zip(actual, expected) { XCTAssertEqual(a, b, accuracy: 0.0003, target.rawValue) }
                    XCTAssertNotEqual(actual, render(baseline), target.rawValue)
                }
            }
        }
    }

    func testEveryCustomTargetExportsTIFFWithoutChangingInput() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("custom-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inputURL = folder.appendingPathComponent("input.tiff")
        let input = image([SIMD3(0.2, 0.1, 0.05), SIMD3(0.05, 0.3, 0.1), SIMD3(0.1, 0.2, 0.6), SIMD3(0.8, 0.8, 0.8)], alpha: 1)
        try ExportEngine.write(input, to: inputURL, format: .tiff16, using: context)
        let original = try Data(contentsOf: inputURL)
        var outputs = Set<[Int]>()
        for target in DevelopTarget.customTargets {
            let destination = folder.appendingPathComponent(target.rawValue + ".tiff")
            var params = DevelopParameters()
            params.filmType = .colorPositive
            params.developTarget = target
            try ChromabaseEngine().developFile(input: inputURL, output: destination, format: .tiff16, base: nil, params: params)
            let decoded = try XCTUnwrap(ImageLoader.loadImportedDecoded(destination)).image
            XCTAssertEqual(decoded.extent.size, input.extent.size)
            outputs.insert(render(decoded).map { Int(($0 * 65535).rounded()) })
        }
        XCTAssertEqual(outputs.count, 18)
        XCTAssertEqual(try Data(contentsOf: inputURL), original)
    }

    func testCustomIgnoresStaleScannerProfileFromImportedSettings() throws {
        let profile = try XCTUnwrap(ScannerProfileRegistry.loadAll().first)
        let input = image([SIMD3(0.2, 0.1, 0.05), SIMD3(0.05, 0.3, 0.4)], alpha: 1)
        var params = DevelopParameters()
        params.filmType = .colorPositive
        params.developTarget = .classic
        let engine = ChromabaseEngine()
        let expected = render(engine.develop(image: input, base: nil, params: params))
        params.scannerProfileID = profile.id
        XCTAssertEqual(render(engine.develop(image: input, base: nil, params: params)), expected)
    }

    func testMonochromeCustomResultsRemainNeutral() {
        let input = image([SIMD3(0.2, 0.15, 0.1), SIMD3(0.05, 0.25, 0.5)], alpha: 1)
        for target in DevelopTarget.customTargets {
            var params = DevelopParameters()
            params.filmType = .bwPositive
            params.developTarget = target
            let pixels = render(ChromabaseEngine().develop(image: input, base: nil, params: params))
            for i in stride(from: 0, to: pixels.count, by: 4) {
                XCTAssertEqual(pixels[i], pixels[i + 1], accuracy: 1e-5)
                XCTAssertEqual(pixels[i + 1], pixels[i + 2], accuracy: 1e-5)
            }
        }
    }

    private func image(_ colors: [SIMD3<Double>], alpha: Float, width: Int? = nil) -> CIImage {
        let width = width ?? colors.count
        let pixels = colors.flatMap { [Float($0.x) * alpha, Float($0.y) * alpha, Float($0.z) * alpha, alpha] }
        return CIImage(bitmapData: pixels.withUnsafeBytes { Data($0) },
                       bytesPerRow: width * 16, size: CGSize(width: width, height: colors.count / width),
                       format: .RGBAf, colorSpace: linear)
    }

    private func render(_ image: CIImage) -> [Float] {
        var pixels = [Float](repeating: 0, count: Int(image.extent.width * image.extent.height) * 4)
        context.render(image, toBitmap: &pixels, rowBytes: Int(image.extent.width) * 16,
                       bounds: image.extent, format: .RGBAf, colorSpace: linear)
        return pixels
    }
}
