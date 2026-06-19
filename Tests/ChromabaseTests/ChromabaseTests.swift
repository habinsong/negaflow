import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class ChromabaseTests: XCTestCase {
    func testPresetLoadAll() {
        let presets = PresetRegistry.loadAll()
        XCTAssertEqual(presets.count, 6, "expected 6 built-in presets")
        let names = Set(presets.map(\.name))
        XCTAssertTrue(names.contains("Neutral"))
        XCTAssertTrue(names.contains("Rich Neutral"))
        XCTAssertTrue(names.contains("Soft Print"))
        XCTAssertTrue(names.contains("Clear Chrome"))
        XCTAssertTrue(names.contains("Warm Lab"))
        XCTAssertTrue(names.contains("Deep Slide"))
    }

    func testRichNeutralIsRicherThanNeutral() {
        let neutral = PresetRegistry.load(named: "neutral")!
        let rich    = PresetRegistry.load(named: "rich-neutral")!
        XCTAssertGreaterThan(rich.baseParameters.density, neutral.baseParameters.density,
                             "Rich Neutral should have higher density than Neutral")
        XCTAssertGreaterThan(rich.baseParameters.colorDepth, neutral.baseParameters.colorDepth,
                             "Rich Neutral should have more color depth")
    }

    func testDevelopParametersPresetOverride() {
        let preset = PresetRegistry.load(named: "rich-neutral")!
        var overrides = DevelopParameters()
        overrides.exposure = 0.5
        let merged = DevelopParameters(preset: preset, overrides: overrides)
        XCTAssertEqual(merged.exposure, preset.baseParameters.exposure + 0.5, accuracy: 1e-9)
    }

    func testInversionRequiresInversion() {
        XCTAssertTrue(FilmType.colorNegative.requiresInversion)
        XCTAssertTrue(FilmType.bwNegative.requiresInversion)
        XCTAssertFalse(FilmType.colorPositive.requiresInversion)
        XCTAssertFalse(FilmType.bwPositive.requiresInversion)
    }

    func testColorNegativeInversionMapsDenseNegativeBrighterThanClearBase() {
        let width = 4
        let height = 2
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if x < width / 2 {
                    bytes[i] = 224
                    bytes[i + 1] = 158
                    bytes[i + 2] = 107
                } else {
                    bytes[i] = 90
                    bytes[i + 1] = 72
                    bytes[i + 2] = 54
                }
                bytes[i + 3] = 255
            }
        }
        let input = makeTestImage(bytes: bytes, width: width, height: height)
        let base = FilmBase(rgb: SIMD3(224.0 / 255.0, 158.0 / 255.0, 107.0 / 255.0), source: .border)
        let output = NegativeInversion.apply(to: input, base: base)
        let rendered = renderRGBA8(output, width: width, height: height)

        let clearBaseLuma = luma(rendered, x: 0, y: 0, width: width)
        let denseLuma = luma(rendered, x: 3, y: 0, width: width)
        XCTAssertLessThan(clearBaseLuma, 35, "필름 베이스 자체는 반전 후 검은 기준점에 가까워야 한다.")
        XCTAssertGreaterThan(denseLuma - clearBaseLuma, 90, "어두운 네거티브 밀도는 반전 후 밝은 양화로 올라와야 한다.")
    }

    func testFilmBaseEstimatorUsesBrightOrangeCandidatesWhenBorderHasDarkHolder() {
        let width = 48
        let height = 32
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i] = 18
                bytes[i + 1] = 8
                bytes[i + 2] = 5
                if y < 5 && x % 5 == 0 {
                    bytes[i] = 185
                    bytes[i + 1] = 110
                    bytes[i + 2] = 70
                }
                bytes[i + 3] = 255
            }
        }

        let image = makeTestImage(bytes: bytes, width: width, height: height)
        let base = FilmBaseEstimator.estimate(from: image, edgeFraction: 0.16)
        XCTAssertNotNil(base)
        XCTAssertGreaterThan(base?.rgb.x ?? 0, 0.6, "어두운 홀더 평균이 아니라 밝은 오렌지 필름 베이스 후보를 잡아야 한다.")
        XCTAssertGreaterThan(base?.rgb.y ?? 0, 0.35)
        XCTAssertGreaterThan(base?.rgb.z ?? 0, 0.2)
    }

    func testColorNegativeNoLookAndAllLooksStayBounded() {
        let fixture = makeSyntheticColorNegativeFixture()
        let engine = ChromabaseEngine()
        var parameterSets: [(String, DevelopParameters)] = []
        var noLook = DevelopParameters()
        noLook.filmType = .colorNegative
        parameterSets.append(("none", noLook))
        for preset in PresetRegistry.loadAll() where preset.filmTypes.contains(FilmType.colorNegative.rawValue) {
            var overrides = DevelopParameters()
            overrides.filmType = .colorNegative
            var params = DevelopParameters(preset: preset, overrides: overrides)
            params.filmType = .colorNegative
            parameterSets.append((preset.id, params))
        }

        for (name, params) in parameterSets {
            let output = engine.develop(image: fixture.image, base: fixture.base, params: params)
            let rendered = renderRGBA8(output, width: fixture.width, height: fixture.height)
            let stats = lumaStats(rendered)
            XCTAssertLessThan(stats.p05, 90, "\(name) 룩이 암부를 잃으면 안 된다.")
            XCTAssertGreaterThan(stats.p95, 130, "\(name) 룩이 명부를 잃으면 안 된다.")
            XCTAssertLessThan(stats.mean, 220, "\(name) 룩이 흰 화면으로 날아가면 안 된다.")
        }
    }

    func testLowRangeColorNegativeDevelopsToVisiblePositive() {
        let width = 48
        let height = 32
        let base = SIMD3<Double>(0.224, 0.094, 0.067)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let isBorder = y < 3 || y >= height - 3 || x < 3 || x >= width - 3
                let positiveLuma = Double(x) / Double(width - 1)
                let dense = SIMD3<Double>(
                    base.x * (0.18 + positiveLuma * 0.50),
                    base.y * (0.16 + positiveLuma * 0.48),
                    base.z * (0.14 + positiveLuma * 0.45)
                )
                let sample = isBorder ? base : dense
                bytes[i] = UInt8(max(0, min(255, Int(sample.x * 255))))
                bytes[i + 1] = UInt8(max(0, min(255, Int(sample.y * 255))))
                bytes[i + 2] = UInt8(max(0, min(255, Int(sample.z * 255))))
                bytes[i + 3] = 255
            }
        }

        let image = makeTestImage(bytes: bytes, width: width, height: height)
        var params = DevelopParameters()
        params.filmType = .colorNegative
        let output = ChromabaseEngine().develop(
            image: image,
            base: FilmBase(rgb: base, source: .border),
            params: params
        )
        let rendered = renderRGBA8(output, width: width, height: height)
        let stats = lumaStats(rendered)

        XCTAssertGreaterThan(stats.p95, 145, "저노출 raw 컬러 네거티브가 현상 후에도 검붉게 죽으면 안 된다.")
        XCTAssertGreaterThan(stats.mean, 70, "저노출 raw 컬러 네거티브는 기본 현상만으로도 화면에서 식별 가능해야 한다.")
        XCTAssertLessThan(stats.p05, 80, "검은 필름 홀더/암부는 검은 기준을 유지해야 한다.")
    }

    func testColorNegativeExportsJPEGAndTIFFFromSameDevelopedImage() throws {
        let fixture = makeSyntheticColorNegativeFixture()
        var params = DevelopParameters()
        params.filmType = .colorNegative
        let output = ChromabaseEngine().develop(image: fixture.image, base: fixture.base, params: params)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let jpg = tempDir.appendingPathComponent("negaflow_export_\(UUID().uuidString).jpg")
        let jpeg = tempDir.appendingPathComponent("negaflow_export_\(UUID().uuidString).jpeg")
        let tif = tempDir.appendingPathComponent("negaflow_export_\(UUID().uuidString).tif")
        let tiff = tempDir.appendingPathComponent("negaflow_export_\(UUID().uuidString).tiff")
        defer {
            try? FileManager.default.removeItem(at: jpg)
            try? FileManager.default.removeItem(at: jpeg)
            try? FileManager.default.removeItem(at: tif)
            try? FileManager.default.removeItem(at: tiff)
        }

        try ExportEngine.write(output, to: jpg, format: .jpeg, using: context)
        try ExportEngine.write(output, to: jpeg, format: .jpeg, using: context)
        try ExportEngine.write(output, to: tif, format: .tiff16, using: context)
        try ExportEngine.write(output, to: tiff, format: .tiff16, using: context)

        for url in [jpg, jpeg, tif, tiff] {
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            XCTAssertGreaterThan(size, 1024, "\(url.lastPathComponent) 출력이 비어 있으면 안 된다.")
        }
    }

    // MARK: - input format classification

    func testImageLoaderKindClassification() {
        XCTAssertEqual(ImageLoader.kind(of: URL(fileURLWithPath: "/a/scan.tiff")), .standardImage)
        XCTAssertEqual(ImageLoader.kind(of: URL(fileURLWithPath: "/a/scan.TIF")), .standardImage)
        XCTAssertEqual(ImageLoader.kind(of: URL(fileURLWithPath: "/a/photo.jpeg")), .standardImage)
        XCTAssertEqual(ImageLoader.kind(of: URL(fileURLWithPath: "/a/p.png")), .standardImage)
        XCTAssertEqual(ImageLoader.kind(of: URL(fileURLWithPath: "/a/r.dng")), .rawDng)
        XCTAssertEqual(ImageLoader.kind(of: URL(fileURLWithPath: "/a/r.cr2")), .rawDng)
        XCTAssertEqual(ImageLoader.kind(of: URL(fileURLWithPath: "/a/r.NEF")), .rawDng)
    }

    func testImageLoaderLoadsStandardFormat() {
        // 합성 네거티브를 만들어 로드 검증.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cbtest_\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let w = 120, h = 80
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = 200; bytes[i+1] = 150; bytes[i+2] = 100; bytes[i+3] = 255
        }
        let cs = CGColorSpace(name: CGColorSpace.genericRGBLinear)!
        let ctx = CGContext(data: &bytes, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let img = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(tmp as CFURL, "public.tiff" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)

        let loaded = ImageLoader.load(tmp)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.extent.width, CGFloat(w))
    }

    // MARK: - positive path

    func testPositiveDoesNotEstimateFilmBase() {
        // 포지티브는 requiresInversion == false 이므로 film base 추정이 불필요.
        XCTAssertFalse(FilmType.colorPositive.requiresInversion)
        XCTAssertFalse(FilmType.bwPositive.requiresInversion)
    }

    func testAutoLevelsExpandsLowRangePositiveRawWithoutFlattening() {
        let width = 32
        let height = 16
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = UInt8(12 + (x * 50 / (width - 1)))
                let i = (y * width + x) * 4
                bytes[i] = v
                bytes[i + 1] = UInt8(min(255, Int(v) + 3))
                bytes[i + 2] = UInt8(min(255, Int(v) + 6))
                bytes[i + 3] = 255
            }
        }
        let input = makeTestImage(bytes: bytes, width: width, height: height)
        let output = AutoLevels.apply(to: input)
        let rendered = renderRGBA8(output, width: width, height: height)

        var minLuma = 255
        var maxLuma = 0
        for i in stride(from: 0, to: rendered.count, by: 4) {
            let luma = (Int(rendered[i]) + Int(rendered[i + 1]) + Int(rendered[i + 2])) / 3
            minLuma = min(minLuma, luma)
            maxLuma = max(maxLuma, luma)
        }
        XCTAssertLessThan(minLuma, 20)
        XCTAssertGreaterThan(maxLuma, 220)
        XCTAssertGreaterThan(maxLuma - minLuma, 180, "AutoLevels가 raw를 회색 평면으로 만들면 안 된다.")
    }

    func testImageTransformFlipAndRotate() {
        let width = 4
        let height = 2
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if x < 2 {
                    bytes[i] = 255
                } else {
                    bytes[i + 2] = 255
                }
                bytes[i + 3] = 255
            }
        }
        let input = makeTestImage(bytes: bytes, width: width, height: height)
        let flipped = ImageTransformStage.apply(to: input, transform: ImageTransform(flipHorizontal: true))
        let rendered = renderRGBA8(flipped, width: width, height: height)
        XCTAssertGreaterThan(rendered[2], rendered[0], "좌우 뒤집기 후 왼쪽 픽셀은 파란쪽이어야 한다.")

        let rotated = ImageTransformStage.apply(to: input, transform: ImageTransform(rotation: .deg90))
        XCTAssertEqual(Int(rotated.extent.width), height)
        XCTAssertEqual(Int(rotated.extent.height), width)
    }

    func testBwPositivePresetSaturatesToZeroViaPositiveDevelop() {
        // PositiveDevelop이 extent를 유한으로 유지하는지가 핵심.
        let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: extent)
        let out = PositiveDevelop.applyBaseGrade(to: input, filmType: .bwPositive)
        XCTAssertTrue(out.extent.isInfinite == false, "positive grade must keep finite extent")
        XCTAssertEqual(out.extent.width, 8, accuracy: 0.001)
    }

    func testColorPositiveDeepSlideKeepsVisibleContrast() {
        let width = 32
        let height = 16
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let bright = x < width / 2 ? UInt8(24) : UInt8(220)
                let i = (y * width + x) * 4
                bytes[i] = bright
                bytes[i + 1] = UInt8(min(255, Int(bright) + 10))
                bytes[i + 2] = UInt8(max(0, Int(bright) - 10))
                bytes[i + 3] = 255
            }
        }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let input = makeTestImage(bytes: bytes, width: width, height: height)
        var params = PresetRegistry.load(named: "deep-slide")!.baseParameters
        params.filmType = .colorPositive
        let output = ChromabaseEngine().develop(image: input, base: nil, params: params)

        let rendered = renderRGBA8(output, width: width, height: height, colorSpace: cs)

        var minLuma = 255
        var maxLuma = 0
        for i in stride(from: 0, to: rendered.count, by: 4) {
            let luma = (Int(rendered[i]) + Int(rendered[i + 1]) + Int(rendered[i + 2])) / 3
            minLuma = min(minLuma, luma)
            maxLuma = max(maxLuma, luma)
        }
        XCTAssertGreaterThan(maxLuma - minLuma, 100, "슬라이드 현상이 회색 평면으로 눌리면 안 된다.")
    }

    func testHalationDoesNotLiftDarkFrameToGray() {
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let input = CIImage(color: CIColor(red: 0.02, green: 0.02, blue: 0.02)).cropped(to: extent)
        var params = DevelopParameters()
        params.halation = 0.08

        let output = TextureStage.apply(to: input, params: params)
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        var rendered = [UInt8](repeating: 0, count: 16 * 16 * 4)
        ctx.render(output, toBitmap: &rendered, rowBytes: 16 * 4,
                   bounds: extent, format: .RGBA8, colorSpace: cs)

        let center = ((8 * 16) + 8) * 4
        let luma = (Int(rendered[center]) + Int(rendered[center + 1]) + Int(rendered[center + 2])) / 3
        XCTAssertLessThan(luma, 20, "halation이 하이라이트 없는 암부를 회색으로 띄우면 안 된다.")
    }

    private func makeTestImage(bytes: [UInt8], width: Int, height: Int) -> CIImage {
        var mutable = bytes
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let cg = CGContext(data: &mutable, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: width * 4, space: cs,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        return CIImage(cgImage: cg)
    }

    private func renderRGBA8(
        _ image: CIImage,
        width: Int,
        height: Int,
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    ) -> [UInt8] {
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        var rendered = [UInt8](repeating: 0, count: width * height * 4)
        ctx.render(image, toBitmap: &rendered, rowBytes: width * 4,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height),
                   format: .RGBA8, colorSpace: colorSpace)
        return rendered
    }

    private func luma(_ rgba: [UInt8], x: Int, y: Int, width: Int) -> Int {
        let i = (y * width + x) * 4
        return (Int(rgba[i]) + Int(rgba[i + 1]) + Int(rgba[i + 2])) / 3
    }

    private func lumaStats(_ rgba: [UInt8]) -> (p05: Int, p95: Int, mean: Int) {
        var values: [Int] = []
        values.reserveCapacity(rgba.count / 4)
        var sum = 0
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let v = (Int(rgba[i]) + Int(rgba[i + 1]) + Int(rgba[i + 2])) / 3
            values.append(v)
            sum += v
        }
        values.sort()
        return (
            values[max(0, Int(Double(values.count - 1) * 0.05))],
            values[max(0, Int(Double(values.count - 1) * 0.95))],
            sum / max(1, values.count)
        )
    }

    private func makeSyntheticColorNegativeFixture() -> (image: CIImage, base: FilmBase, width: Int, height: Int) {
        let width = 64
        let height = 40
        let base = SIMD3<Double>(0.86, 0.54, 0.34)
        let gamma = 0.72
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let normalizedX = Double(x) / Double(width - 1)
                var positive = SIMD3<Double>(
                    0.62 + normalizedX * 0.25,
                    0.66 + normalizedX * 0.2,
                    0.67 + normalizedX * 0.18
                )
                if x > width / 3 && x < width * 2 / 3 && y > 4 {
                    positive = SIMD3(0.05, 0.04, 0.04)
                }
                if x > width / 2 && y > height / 2 {
                    positive = SIMD3(0.45, 0.18, 0.08)
                }
                if x > width / 4 && x < width / 2 && y < height / 4 {
                    positive = SIMD3(0.94, 0.9, 0.82)
                }
                let negative = SIMD3(
                    base.x * pow(max(0.0, 1.0 - positive.x), 1.0 / gamma),
                    base.y * pow(max(0.0, 1.0 - positive.y), 1.0 / gamma),
                    base.z * pow(max(0.0, 1.0 - positive.z), 1.0 / gamma)
                )
                let i = (y * width + x) * 4
                bytes[i] = UInt8(max(0, min(255, Int(negative.x * 255))))
                bytes[i + 1] = UInt8(max(0, min(255, Int(negative.y * 255))))
                bytes[i + 2] = UInt8(max(0, min(255, Int(negative.z * 255))))
                bytes[i + 3] = 255
            }
        }
        let image = makeTestImage(bytes: bytes, width: width, height: height)
        return (image, FilmBase(rgb: base, source: .border), width, height)
    }
}
