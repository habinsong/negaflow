import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class ChromabaseTests: XCTestCase {
    func testOrientationTemplatePreservesRotationAndFlipsWithoutCrop() {
        let transform = ImageTransform(
            rotation: .deg270,
            flipHorizontal: true,
            flipVertical: true,
            cropRect: SIMD4(0.1, 0.2, 0.6, 0.5)
        )

        XCTAssertEqual(
            transform.orientationTemplate,
            ImageTransform(rotation: .deg270, flipHorizontal: true, flipVertical: true)
        )
    }

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
        overrides.contrast = 0.2
        overrides.saturation = 0.1
        let merged = DevelopParameters(preset: preset, overrides: overrides)
        XCTAssertEqual(merged.exposure, preset.baseParameters.exposure + 0.5, accuracy: 1e-9)
        XCTAssertEqual(merged.contrast, preset.baseParameters.contrast + 0.2, accuracy: 1e-9)
        XCTAssertEqual(merged.saturation, preset.baseParameters.saturation + 0.1, accuracy: 1e-9)
    }

    func testDevelopParametersDecodeOlderSidecarDefaultsNewControls() throws {
        let data = #"{"filmType":"colorNegative","exposure":0.25,"density":0.1}"#
            .data(using: .utf8)!
        let params = try JSONDecoder().decode(DevelopParameters.self, from: data)
        XCTAssertEqual(params.exposure, 0.25, accuracy: 1e-9)
        XCTAssertEqual(params.density, 0.1, accuracy: 1e-9)
        XCTAssertEqual(params.contrast, 0, accuracy: 1e-9)
        XCTAssertEqual(params.curveLights, 0, accuracy: 1e-9)
        XCTAssertEqual(params.vibrance, 0, accuracy: 1e-9)
        XCTAssertEqual(params.clarity, 0, accuracy: 1e-9)
    }

    func testPresetMapsContrastAndSaturationToSeparateControls() {
        let preset = PresetRegistry.load(named: "clear-chrome")!
        let params = preset.baseParameters
        XCTAssertEqual(params.contrast, preset.tone.contrast, accuracy: 1e-9)
        XCTAssertEqual(params.saturation, preset.color.saturation, accuracy: 1e-9)
    }

    func testToneCurveControlsChangeMidtones() {
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        var params = DevelopParameters()
        params.curveLights = 0.8
        let output = ToneMapper.applyToneCurves(to: input, params: params)
        let baseline = renderRGBA8(input, width: 8, height: 8)
        let adjusted = renderRGBA8(output, width: 8, height: 8)
        XCTAssertGreaterThan(luma(adjusted, x: 4, y: 4, width: 8), luma(baseline, x: 4, y: 4, width: 8) + 10)
    }

    func testColorControlsAndCalibrationAffectChannels() {
        let input = CIImage(color: CIColor(red: 0.45, green: 0.22, blue: 0.18))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        var params = DevelopParameters()
        params.saturation = 0.6
        params.redPrimary = 0.7
        let output = ColorModel.apply(to: input, params: params)
        let baseline = renderRGBA8(input, width: 8, height: 8)
        let adjusted = renderRGBA8(output, width: 8, height: 8)
        let center = ((4 * 8) + 4) * 4
        XCTAssertGreaterThan(adjusted[center], baseline[center])
    }

    func testEffectsControlsKeepFiniteExtent() {
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let input = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4)).cropped(to: extent)
        var params = DevelopParameters()
        params.clarity = 0.6
        params.vignette = 0.4
        let output = TextureStage.apply(to: input, params: params)
        XCTAssertFalse(output.extent.isInfinite)
        XCTAssertEqual(output.extent.width, 16, accuracy: 0.001)
        XCTAssertEqual(output.extent.height, 16, accuracy: 0.001)
    }

    func testInversionRequiresInversion() {
        XCTAssertTrue(FilmType.colorNegative.requiresInversion)
        XCTAssertTrue(FilmType.bwNegative.requiresInversion)
        XCTAssertFalse(FilmType.colorPositive.requiresInversion)
        XCTAssertFalse(FilmType.bwPositive.requiresInversion)
    }

    func testNegativeInversionKeepsDenseHighlightSeparation() {
        let base = FilmBase(rgb: SIMD3(repeating: 0.2), source: .manual)
        let width = 64
        let height = 32
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8 = x < width / 2 ? 3 : 8
                let offset = (y * width + x) * 4
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
            }
        }
        let image = makeTestImage(
            bytes: bytes,
            width: width,
            height: height,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        let output = renderLinearRGBA8(NegativeInversion.apply(to: image, base: base), width: width, height: height)

        XCTAssertGreaterThanOrEqual(
            luma(output, x: 16, y: 16, width: width) - luma(output, x: 48, y: 16, width: width),
            22,
            "고밀도 네거티브의 인접 명부 계조가 백색으로 뭉개지면 안 된다."
        )
    }

    func testColorNegativeInversionMapsDenseNegativeBrighterThanClearBase() {
        let width = 64
        let height = 32
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
        let input = makeTestImage(
            bytes: bytes,
            width: width,
            height: height,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        let base = FilmBase(rgb: SIMD3(224.0 / 255.0, 158.0 / 255.0, 107.0 / 255.0), source: .border)
        let output = NegativeInversion.apply(to: input, base: base)
        let rendered = renderLinearRGBA8(output, width: width, height: height)

        let clearBaseLuma = luma(rendered, x: 0, y: 0, width: width)
        let denseLuma = luma(rendered, x: width - 1, y: 0, width: width)
        XCTAssertLessThan(clearBaseLuma, 35, "필름 베이스 자체는 반전 후 검은 기준점에 가까워야 한다.")
        XCTAssertGreaterThan(denseLuma - clearBaseLuma, 75, "어두운 네거티브 밀도는 반전 후 밝은 양화로 올라와야 한다.")
    }

    func testNegativeInversionRetainsMidtoneDyeSeparation() {
        let width = 64
        let height = 32
        let base = FilmBase(rgb: SIMD3(0.8, 0.5, 0.3), source: .manual)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let transmission: (UInt8, UInt8, UInt8) = x < width / 2
                    ? (82, 54, 38)
                    : (118, 78, 19)
                bytes[offset] = transmission.0
                bytes[offset + 1] = transmission.1
                bytes[offset + 2] = transmission.2
                bytes[offset + 3] = 255
            }
        }
        let input = makeTestImage(
            bytes: bytes,
            width: width,
            height: height,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        let rendered = renderLinearRGBA8(
            NegativeInversion.apply(to: input, base: base),
            width: width,
            height: height
        )
        let warm = (rendered[0], rendered[1], rendered[2])
        let coolOffset = (width - 1) * 4
        let cool = (rendered[coolOffset], rendered[coolOffset + 1], rendered[coolOffset + 2])

        XCTAssertGreaterThan(warm.0 - warm.2, 55, "황갈색 중간톤의 R/B 분리가 회색으로 눌리면 안 된다.")
        XCTAssertGreaterThan(cool.2 - cool.0, 55, "청색 중간톤의 B/R 분리가 회색으로 눌리면 안 된다.")
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
                if y < 5 {
                    bytes[i] = 185
                    bytes[i + 1] = 110
                    bytes[i + 2] = 70
                }
                bytes[i + 3] = 255
            }
        }

        let image = makeTestImage(
            bytes: bytes,
            width: width,
            height: height,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        let base = FilmBaseEstimator.estimate(from: image, edgeFraction: 0.16)
        XCTAssertNotNil(base)
        XCTAssertGreaterThan(base?.rgb.x ?? 0, 0.6, "어두운 홀더 평균이 아니라 밝은 오렌지 필름 베이스 후보를 잡아야 한다.")
        XCTAssertGreaterThan(base?.rgb.y ?? 0, 0.35)
        XCTAssertGreaterThan(base?.rgb.z ?? 0, 0.2)
    }

    func testFilmBaseEstimatorRejectsSparseOrangePerforationCandidates() {
        let width = 48
        let height = 32
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i] = 18
                bytes[i + 1] = 8
                bytes[i + 2] = 5
                if y < 5 && x.isMultiple(of: 5) {
                    bytes[i] = 185
                    bytes[i + 1] = 110
                    bytes[i + 2] = 70
                }
                bytes[i + 3] = 255
            }
        }

        let image = makeTestImage(
            bytes: bytes,
            width: width,
            height: height,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        XCTAssertNil(
            FilmBaseEstimator.estimate(from: image, edgeFraction: 0.16),
            "연속된 필름 베이스가 아닌 퍼포레이션/홀더의 산발적 색을 베이스로 쓰면 안 된다."
        )
    }

    func testFilmBaseEstimatorIgnoresWarmFilmlessEdgeGap() {
        let width = 80
        let height = 50
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let edge = x < 5 || x >= width - 5 || y < 5 || y >= height - 5
                let realBase = y < 5 && x >= 18 && x < 62
                if realBase {
                    bytes[i] = 62
                    bytes[i + 1] = 27
                    bytes[i + 2] = 18
                } else if edge {
                    bytes[i] = 245
                    bytes[i + 1] = 236
                    bytes[i + 2] = 220
                } else {
                    bytes[i] = 34
                    bytes[i + 1] = 16
                    bytes[i + 2] = 10
                }
            }
        }

        let base = FilmBaseEstimator.estimate(
            from: makeTestImage(
                bytes: bytes,
                width: width,
                height: height,
                colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
            ),
            edgeFraction: 0.10
        )
        XCTAssertLessThan(base?.rgb.x ?? 1, 0.35, "따뜻한 무필름 빈 공간을 필름 베이스로 쓰면 안 된다.")
        XCTAssertGreaterThan(base?.rgb.x ?? 0, 0.18)
        XCTAssertGreaterThan((base?.rgb.x ?? 0) - (base?.rgb.z ?? 0), 0.12)
    }

    func testNegativeInversionMapsExposedLowlightToBlackWhenBaseIsInsideFrame() {
        let width = 80
        let height = 50
        let base = SIMD3<Double>(0.24, 0.10, 0.07)
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let unexposedBase = x < 8 && y < 16
                let lowlight = x < width / 2
                let factor: Double
                if unexposedBase {
                    factor = 1.0
                } else if lowlight {
                    factor = 0.74
                } else {
                    factor = 0.18 + Double(y) / Double(height - 1) * 0.30
                }
                pixels[i] = Float(base.x * factor)
                pixels[i + 1] = Float(base.y * factor)
                pixels[i + 2] = Float(base.z * factor)
            }
        }
        let image = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        let rendered = renderLinearRGBA8(
            NegativeInversion.apply(to: image, base: FilmBase(rgb: base, source: .border)),
            width: width,
            height: height
        )

        XCTAssertLessThan(luma(rendered, x: 20, y: 25, width: width), 45)
        XCTAssertGreaterThan(luma(rendered, x: 70, y: 25, width: width), 145)
    }

    func testNegativeInversionKeepsShadowToeInsteadOfClippingLowlightSteps() {
        let width = 96
        let height = 48
        let base = SIMD3<Double>(0.24, 0.10, 0.07)
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let factor: Double
                if x < 12 && y < 12 {
                    factor = 1.0
                } else {
                    switch x {
                    case 0..<32: factor = 0.78
                    case 32..<64: factor = 0.68
                    default: factor = 0.20
                    }
                }
                pixels[i] = Float(base.x * factor)
                pixels[i + 1] = Float(base.y * factor)
                pixels[i + 2] = Float(base.z * factor)
            }
        }
        let image = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        let rendered = renderLinearRGBA8(
            NegativeInversion.apply(to: image, base: FilmBase(rgb: base, source: .border)),
            width: width,
            height: height
        )

        let clearBase = luma(rendered, x: 6, y: 6, width: width)
        let lowlightA = luma(rendered, x: 24, y: 24, width: width)
        let lowlightB = luma(rendered, x: 48, y: 24, width: width)
        let highlight = luma(rendered, x: 84, y: 24, width: width)

        XCTAssertLessThan(clearBase, 18, "미노광 필름 베이스는 양화의 검은 기준에 남아야 한다.")
        XCTAssertGreaterThan(lowlightA, clearBase + 4, "암부 첫 단계가 0으로 붙으면 SP-3000 같은 shadow toe가 사라진다.")
        XCTAssertGreaterThan(lowlightB, lowlightA + 4, "서로 다른 저밀도 암부 단계가 같은 검정으로 클립되면 안 된다.")
        XCTAssertGreaterThan(highlight, 145, "명부는 충분히 올라와야 한다.")
    }

    func testFilmBaseEstimatorUsesLowSignalContinuousOrangeBorder() {
        let width = 48
        let height = 32
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if y < 5 {
                    bytes[i] = 50
                    bytes[i + 1] = 22
                    bytes[i + 2] = 16
                } else {
                    bytes[i] = 18
                    bytes[i + 1] = 8
                    bytes[i + 2] = 5
                }
                bytes[i + 3] = 255
            }
        }

        let base = FilmBaseEstimator.estimate(
            from: makeTestImage(bytes: bytes, width: width, height: height),
            edgeFraction: 0.16
        )
        XCTAssertEqual(base?.rgb.x ?? 0, Double(50) / 255, accuracy: 0.02)
        XCTAssertEqual(base?.rgb.y ?? 0, Double(22) / 255, accuracy: 0.02)
        XCTAssertEqual(base?.rgb.z ?? 0, Double(16) / 255, accuracy: 0.02)
    }

    func testFilmBaseEstimatorUsesDistributedOrangeMaskWhenBorderIsAbsent() {
        let width = 64
        let height = 48
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let bright = x > 14 && x < 50 && y > 10 && y < 38
                let border = x < 4 || x >= width - 4 || y < 3 || y >= height - 3
                let borderHighlight = border && (x + y).isMultiple(of: 5)
                bytes[i] = bright ? 104 : (borderHighlight ? 70 : 38)
                bytes[i + 1] = bright ? 56 : (borderHighlight ? 38 : 20)
                bytes[i + 2] = bright ? 42 : (borderHighlight ? 28 : 15)
            }
        }

        let base = FilmBaseEstimator.estimate(
            from: makeTestImage(bytes: bytes, width: width, height: height),
            edgeFraction: 0.06
        )
        XCTAssertGreaterThan(base?.rgb.x ?? 0, 0.35)
        XCTAssertGreaterThan(base?.rgb.y ?? 0, 0.18)
        XCTAssertGreaterThan(base?.rgb.z ?? 0, 0.13)
    }

    func testFilmBaseEstimatorRejectsDimContinuousEdgeForBrighterMaskSample() {
        let width = 64
        let height = 48
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let dimEdge = y < 5 || y >= height - 5 || x < 4 || x >= width - 4
                let brightMask = x > 12 && x < 52 && y > 9 && y < 39
                bytes[i] = brightMask ? 108 : (dimEdge ? 50 : 38)
                bytes[i + 1] = brightMask ? 58 : (dimEdge ? 22 : 20)
                bytes[i + 2] = brightMask ? 44 : (dimEdge ? 16 : 15)
            }
        }

        let base = FilmBaseEstimator.estimate(
            from: makeTestImage(bytes: bytes, width: width, height: height),
            edgeFraction: 0.06
        )
        XCTAssertGreaterThan(base?.rgb.x ?? 0, 0.38)
        XCTAssertGreaterThan(base?.rgb.y ?? 0, 0.20)
        XCTAssertGreaterThan(base?.rgb.z ?? 0, 0.15)
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
            XCTAssertGreaterThan(stats.p95, 80, "\(name) 룩이 명부를 잃으면 안 된다.")
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

        let image = makeTestImage(
            bytes: bytes,
            width: width,
            height: height,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        var params = DevelopParameters()
        params.filmType = .colorNegative
        let output = ChromabaseEngine().developScanner(
            image: image,
            base: FilmBase(rgb: base, source: .border),
            params: params
        )
        let rendered = renderLinearRGBA8(output, width: width, height: height)
        let stats = lumaStats(rendered)

        XCTAssertGreaterThan(stats.p95, 145, "저노출 raw 컬러 네거티브가 현상 후에도 검붉게 죽으면 안 된다.")
        XCTAssertGreaterThan(stats.mean, 70, "저노출 raw 컬러 네거티브는 기본 현상만으로도 화면에서 식별 가능해야 한다.")
        XCTAssertLessThan(stats.p05, 80, "검은 필름 홀더/암부는 검은 기준을 유지해야 한다.")
    }

    func testScannerPrintGradeMatchesSP3000ChannelBalanceAndShoulder() {
        let width = 96
        let height = 48
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let t = Float(x) / Float(width - 1)
                let offset = (y * width + x) * 4
                pixels[offset] = 0.10 + t * 0.80
                pixels[offset + 1] = 0.10 + t * 0.80
                pixels[offset + 2] = 0.10 + t * 0.80
            }
        }
        let input = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let output = ScannerPrintGrade.apply(to: input)
        let rendered = renderLinearRGBA8(output, width: width, height: height)

        func mean(channel: Int, range: Range<Int>) -> Double {
            var sum = 0
            var count = 0
            for y in 4..<(height - 4) {
                for x in range {
                    sum += Int(rendered[(y * width + x) * 4 + channel])
                    count += 1
                }
            }
            return Double(sum) / Double(count)
        }

        let lowLuma = mean(channel: 1, range: 18..<30)
        let midLuma = mean(channel: 1, range: 45..<57)
        let redMid = mean(channel: 0, range: 45..<57)
        let greenMid = mean(channel: 1, range: 45..<57)
        let blueMid = mean(channel: 2, range: 45..<57)
        let highGreen = mean(channel: 1, range: 76..<90)

        XCTAssertGreaterThan(midLuma - lowLuma, 28, "SP-3000 쪽처럼 낮은 미드톤과 중간톤이 분리되어야 한다.")
        XCTAssertLessThan(highGreen, 252, "출력 shoulder가 명부를 255에 넓게 붙이면 안 된다.")
        XCTAssertGreaterThan(redMid / greenMid, 1.04, "SP-3000 레퍼런스처럼 R/G가 약간 따뜻해야 한다.")
        XCTAssertLessThan(redMid / greenMid, 1.12, "붉은 채널이 녹색 대비 과하게 튀면 안 된다.")
        XCTAssertGreaterThan(greenMid / blueMid, 1.02, "blue가 green보다 약하게 눌려 warm/yellow 축이 남아야 한다.")
        XCTAssertLessThan(greenMid / blueMid, 1.10, "yellow가 SP-3000보다 과하면 안 된다.")
    }

    func testScannerPrintGradeImprovesMidtoneShoulderAndShadowChroma() {
        let width = 112
        let height = 48
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let t = Float(x) / Float(width - 1)
                let offset = (y * width + x) * 4
                let purpleNoise: Float = (x + y).isMultiple(of: 2) ? 0.028 : -0.028
                let base = 0.12 + t * 0.82
                pixels[offset] = base + (x < 20 ? purpleNoise + 0.018 : 0)
                pixels[offset + 1] = base - (x < 20 ? 0.012 : 0)
                pixels[offset + 2] = base - (x < 20 ? purpleNoise - 0.018 : 0)
            }
        }
        let input = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let output = ScannerPrintGrade.apply(to: input)
        let rendered = renderLinearRGBA8(output, width: width, height: height)

        func meanLuma(range: Range<Int>) -> Double {
            var sum = 0
            var count = 0
            for y in 4..<(height - 4) {
                for x in range {
                    let offset = (y * width + x) * 4
                    sum += (Int(rendered[offset]) + Int(rendered[offset + 1]) + Int(rendered[offset + 2])) / 3
                    count += 1
                }
            }
            return Double(sum) / Double(count)
        }
        func meanChroma(range: Range<Int>) -> Double {
            var sum = 0.0
            var count = 0
            for y in 4..<(height - 4) {
                for x in range {
                    let offset = (y * width + x) * 4
                    let r = Double(rendered[offset]) / 255.0
                    let g = Double(rendered[offset + 1]) / 255.0
                    let b = Double(rendered[offset + 2]) / 255.0
                    let luma = r * 0.2126 + g * 0.7152 + b * 0.0722
                    sum += sqrt(pow(r - luma, 2) + pow(g - luma, 2) + pow(b - luma, 2))
                    count += 1
                }
            }
            return sum / Double(count)
        }

        let deepLuma = meanLuma(range: 4..<14)
        let lowMidLuma = meanLuma(range: 24..<40)
        let midLuma = meanLuma(range: 54..<70)
        let highLuma = meanLuma(range: 90..<108)

        XCTAssertLessThan(deepLuma, 48, "검정 toe가 더 떠오르면 암부 바닥이 회색으로 뜬다.")
        XCTAssertGreaterThan(deepLuma, 18, "검정 toe를 너무 누르면 암부가 0 근처로 붙어 계조가 사라진다.")
        XCTAssertGreaterThan(lowMidLuma - deepLuma, 24, "최저부와 낮은 중간톤은 분리되어야 한다.")
        XCTAssertGreaterThan(midLuma - lowMidLuma, 24, "중간톤 대비가 유지되어야 한다.")
        XCTAssertLessThan(highLuma, 248, "하이라이트 shoulder가 명부를 넓게 255에 붙이면 안 된다.")
        XCTAssertLessThan(meanChroma(range: 4..<14), 0.105, "암부의 보라색 색차 노이즈가 다시 강해지면 안 된다.")
    }

    func testScannerPrintGradeExpandsLowChromaHighlightGradation() {
        let width = 96
        let height = 32
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let t = Float(x) / Float(width - 1)
                let value = 0.84 + t * 0.14
                let offset = (y * width + x) * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
            }
        }
        let input = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let output = ScannerPrintGrade.apply(to: input)
        let rendered = renderLinearRGBA8(output, width: width, height: height)

        let lowHighlight = luma(rendered, x: 25, y: height / 2, width: width)
        let midHighlight = luma(rendered, x: 48, y: height / 2, width: width)
        let highHighlight = luma(rendered, x: 82, y: height / 2, width: width)
        XCTAssertGreaterThan(
            highHighlight - lowHighlight,
            22,
            "하늘처럼 저채도 명부가 한 덩어리 흰색으로 뜨지 않게 highlight 내부 계조를 벌려야 한다."
        )
        XCTAssertLessThan(midHighlight, 230, "저채도 명부 중간값이 너무 높으면 SP-3000 하늘보다 붕 떠 보인다.")
        XCTAssertLessThan(lowHighlight, 235, "낮은 명부가 너무 높게 떠 있으면 하늘이 하얗게 붕 뜬다.")
    }

    func testScannerOutputGradeRecoversLowChromaSkyShoulder() {
        let width = 96
        let height = 40
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let t = Float(x) / Float(width - 1)
                let value = 0.35 + t * 0.045
                let offset = (y * width + x) * 4
                pixels[offset] = value * 0.993
                pixels[offset + 1] = value
                pixels[offset + 2] = value * 1.004
            }
        }
        let input = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let before = renderLinearRGBA8(input, width: width, height: height)
        let output = ScannerOutputGrade.apply(to: input)
        let after = renderLinearRGBA8(output, width: width, height: height)

        let beforeLow = luma(before, x: 20, y: height / 2, width: width)
        let beforeMid = luma(before, x: 50, y: height / 2, width: width)
        let beforeHigh = luma(before, x: 84, y: height / 2, width: width)
        let afterLow = luma(after, x: 20, y: height / 2, width: width)
        let afterMid = luma(after, x: 50, y: height / 2, width: width)
        let afterHigh = luma(after, x: 84, y: height / 2, width: width)
        let midOffset = ((height / 2) * width + 50) * 4
        let afterRed = after[midOffset]
        let afterGreen = after[midOffset + 1]
        let afterBlue = after[midOffset + 2]

        XCTAssertGreaterThan(beforeLow - afterLow, 5, "스캐너 하늘 저채도 명부가 SP-3000보다 하얗게 떠 있으면 안 된다.")
        XCTAssertGreaterThan(beforeMid - afterMid, 3, "하늘 중간 명부도 shoulder 안쪽으로 들어와야 한다.")
        XCTAssertLessThan(beforeHigh - afterHigh, beforeLow - afterLow, "상단 명부를 저명부만큼 강하게 누르면 하늘 계조가 죽는다.")
        XCTAssertGreaterThan(afterHigh - afterLow, 8, "명부를 한 덩어리 회색으로 누르지 말고 내부 계조를 남겨야 한다.")
        XCTAssertGreaterThan(afterRed, afterGreen, "SP-3000 하늘처럼 붉은 채널이 녹색보다 약하게 살아 있어야 한다.")
        XCTAssertGreaterThan(afterBlue, afterGreen, "저채도 하늘을 순수 회색/녹색 쪽으로 밀지 말고 파란 채널도 보존해야 한다.")
    }

    func testScannerOutputGradeReducesWarmPurpleMidtoneChromaWithoutLumaShift() {
        let width = 80
        let height = 32
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let speckle: Float = (x + y).isMultiple(of: 2) ? 0.030 : -0.018
                pixels[offset] = 0.21 + speckle
                pixels[offset + 1] = 0.13
                pixels[offset + 2] = 0.20 - speckle * 0.4
            }
        }
        let input = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let before = renderLinearRGBA8(input, width: width, height: height)
        let output = ScannerOutputGrade.apply(to: input)
        let after = renderLinearRGBA8(output, width: width, height: height)

        XCTAssertLessThan(meanChroma(after), meanChroma(before) * 0.95, "우하단 중간톤 warm/purple 컬러 노이즈는 휘도보다 색차만 줄어야 한다.")
        XCTAssertLessThan(abs(meanLuma(after) - meanLuma(before)), 3.0, "중간톤 컬러 노이즈 제거가 전체 밝기를 밀면 안 된다.")
    }

    func testNegativeDevelopKeepsPixelToneWhenCropChanges() {
        let fixture = makeSyntheticColorNegativeFixture()
        let engine = ChromabaseEngine()
        var identity = DevelopParameters()
        identity.filmType = .colorNegative
        let developed = engine.develop(image: fixture.image, base: fixture.base, params: identity)

        var cropped = identity
        cropped.imageTransform.cropRect = SIMD4(0.25, 0.25, 0.5, 0.5)
        let cropOutput = engine.develop(image: fixture.image, base: fixture.base, params: cropped)
        let expected = ImageTransformStage.apply(to: developed, transform: cropped.imageTransform)

        let width = Int(expected.extent.width)
        let height = Int(expected.extent.height)
        let actualPixels = renderRGBA8(cropOutput, width: width, height: height)
        let expectedPixels = renderRGBA8(expected, width: width, height: height)
        XCTAssertLessThanOrEqual(
            meanChannelDifference(actualPixels, expectedPixels),
            1.0,
            "크롭은 공간 범위만 바꿔야 하며 자동 레벨이나 색 현상 결과를 다시 계산하면 안 된다."
        )
    }

    func testNeutralLookDoesNotAddTextureEffects() {
        let neutral = PresetRegistry.load(named: "neutral")!.baseParameters
        XCTAssertEqual(neutral.highlight, 0, accuracy: 0.0001)
        XCTAssertEqual(neutral.shadow, 0, accuracy: 0.0001)
        XCTAssertEqual(neutral.grain, 0, accuracy: 0.0001)
        XCTAssertEqual(neutral.sharpness, 0, accuracy: 0.0001)
        XCTAssertEqual(neutral.halation, 0, accuracy: 0.0001)
    }

    func testAutoLevelsDoesNotAmplifyNoiseWithoutTonalRange() {
        let width = 64
        let height = 64
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let value: UInt8 = (x + y).isMultiple(of: 2) ? 100 : 102
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
            }
        }

        let input = makeTestImage(bytes: bytes, width: width, height: height)
        let baseline = renderRGBA8(input, width: width, height: height)
        let output = renderRGBA8(AutoLevels.apply(to: input), width: width, height: height)

        XCTAssertLessThanOrEqual(
            lumaStandardDeviation(output, width: width, height: height),
            lumaStandardDeviation(baseline, width: width, height: height) + 1,
            "평탄한 영역의 미세한 스캔 노이즈를 Auto Levels가 전체 명암으로 키우면 안 된다."
        )
    }

    func testAutoLevelsDoesNotAmplifyNarrowColorChannelNoise() {
        let width = 64
        let height = 64
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let narrowValue: UInt8 = (x + y).isMultiple(of: 2) ? 100 : 102
                bytes[offset] = UInt8(32 + (x * 180 / (width - 1)))
                bytes[offset + 1] = narrowValue
                bytes[offset + 2] = narrowValue
            }
        }

        let input = makeTestImage(bytes: bytes, width: width, height: height)
        let output = renderRGBA8(AutoLevels.apply(to: input), width: width, height: height)
        XCTAssertLessThanOrEqual(
            channelStandardDeviation(output, channel: 1, width: width, height: height),
            2,
            "다른 채널에 유효한 톤이 있어도 좁은 채널의 미세 스캔 노이즈를 확장하면 안 된다."
        )
    }

    func testAutoLevelsSamplingRetainsSixteenBitPrecision() {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let input = CIImage(color: CIColor(
            red: 0.1005,
            green: 0.2005,
            blue: 0.3005,
            alpha: 1,
            colorSpace: linear
        )!)
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let sample = AutoLevels.sampleBlackWhite(
            input,
            blackClip: 0.005,
            whiteClip: 0.001,
            sampleColorSpace: linear
        )

        XCTAssertEqual(sample?.white.x ?? 0, 0.1005, accuracy: 0.0006)
        XCTAssertEqual(sample?.white.y ?? 0, 0.2005, accuracy: 0.0006)
        XCTAssertEqual(sample?.white.z ?? 0, 0.3005, accuracy: 0.0006)
    }

    func testAutoLevelsKeepsLinearScannerHighlightHeadroom() {
        let width = 64
        let height = 16
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = 0.1 + Double(x) / Double(width - 1) * 0.8
                let offset = (y * width + x) * 4
                pixels[offset] = Float(value)
                pixels[offset + 1] = Float(value)
                pixels[offset + 2] = Float(value)
            }
        }
        let input = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let output = AutoLevels.apply(to: input, sampleColorSpace: linear)
        var rendered = [Float](repeating: 0, count: width * height * 4)
        CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear]).render(
            output,
            toBitmap: &rendered,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )

        XCTAssertLessThanOrEqual(rendered[(width - 1) * 4], 0.72)
    }

    func testSoftwareICEFillsAchromaticDustWithMedian() {
        let width = 32
        let height = 32
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        // 평탄 회색 0.5 + 중앙 3x3 무채색 검은 먼지(0.0).
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                // 1px 먼지 하나(작은 점) + 떨어진 곳에 또 하나.
                let isDust = ((x == 16) && (y == 16)) || ((x == 8) && (y == 24))
                let v: Float = isDust ? 0.0 : 0.5
                pixels[offset] = v; pixels[offset + 1] = v; pixels[offset + 2] = v
            }
        }
        let input = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let output = SoftwareICE.apply(to: input, threshold: 0.06, strength: 1.0)
        var rendered = [Float](repeating: 0, count: pixels.count)
        CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear]).render(
            output,
            toBitmap: &rendered,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        // 먼지 중심이 median(0.5) 쪽으로 채워져야 한다(0.0에서 크게 상승).
        let center = rendered[(16 * width + 16) * 4]
        XCTAssertGreaterThan(center, 0.35, "ICE가 먼지를 median으로 채워야 함")
        let dust2 = rendered[(24 * width + 8) * 4]
        XCTAssertGreaterThan(dust2, 0.35, "두 번째 먼지도 채워야 함")
        // 먼지에서 먼 평탄 영역은 거의 그대로(0.5) 유지.
        let flat = rendered[(4 * width + 4) * 4]
        XCTAssertEqual(flat, 0.5, accuracy: 0.05, "평탄 영역은 보존되어야 함")
    }

    func testScannerNoiseReductionSmoothsFlatSensorNoiseWithoutErasingEdge() {
        let width = 48
        let height = 32
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let base: Float = x < width / 2 ? 0.12 : 0.42
                let noise: Float = (x + y).isMultiple(of: 2) ? -0.012 : 0.012
                let offset = (y * width + x) * 4
                pixels[offset] = base + noise
                pixels[offset + 1] = base + noise
                pixels[offset + 2] = base + noise
            }
        }
        let input = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let output = ScannerNoiseReduction.apply(to: input)
        var rendered = [Float](repeating: 0, count: pixels.count)
        CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear]).render(
            output,
            toBitmap: &rendered,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )

        func standardDeviation(_ values: [Float]) -> Double {
            let mean = values.reduce(0, +) / Float(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(values.count)
            return sqrt(Double(variance))
        }

        let inputFlat = stride(from: 2, to: width / 2 - 2, by: 1).flatMap { x in
            stride(from: 2, to: height - 2, by: 1).map { y in pixels[(y * width + x) * 4] }
        }
        let outputFlat = stride(from: 2, to: width / 2 - 2, by: 1).flatMap { x in
            stride(from: 2, to: height - 2, by: 1).map { y in rendered[(y * width + x) * 4] }
        }
        let edgeLeft = rendered[(height / 2 * width + width / 2 - 2) * 4]
        let edgeRight = rendered[(height / 2 * width + width / 2 + 1) * 4]

        XCTAssertLessThan(standardDeviation(outputFlat), standardDeviation(inputFlat) * 0.7)
        XCTAssertGreaterThan(edgeRight - edgeLeft, 0.2)
    }

    func testShadowChromaDenoiseReducesPurpleNoiseWithoutFlatteningBrightDetail() {
        let width = 64
        let height = 32
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if x < width / 2 {
                    let noise: Float = (x + y).isMultiple(of: 2) ? 0.05 : -0.05
                    pixels[offset] = 0.13 + noise
                    pixels[offset + 1] = 0.10
                    pixels[offset + 2] = 0.13 - noise
                } else {
                    let detail: Float = y.isMultiple(of: 2) ? 0.72 : 0.86
                    pixels[offset] = detail
                    pixels[offset + 1] = detail
                    pixels[offset + 2] = detail
                }
            }
        }
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let input = CIImage(bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                            size: CGSize(width: width, height: height),
                            format: .RGBAf,
                            colorSpace: linear)
        let output = ScannerNoiseReduction.reduceShadowChroma(in: input)
        var rendered = [Float](repeating: 0, count: pixels.count)
        CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear]).render(
            output,
            toBitmap: &rendered,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )

        let shadowWidth = width / 2 - 3
        let shadowCoordinates = (2..<(height - 2)).flatMap { y in
            (2..<(shadowWidth - 2)).map { x in (x, y) }
        }
        let inputChroma = shadowCoordinates.map { x, y in
            pixels[(y * width + x) * 4] - pixels[(y * width + x) * 4 + 2]
        }
        let outputChroma = shadowCoordinates.map { x, y in
            rendered[(y * width + x) * 4] - rendered[(y * width + x) * 4 + 2]
        }
        let inputLuma = shadowCoordinates.map { x, y in
            let offset = (y * width + x) * 4
            return pixels[offset] * 0.2126 + pixels[offset + 1] * 0.7152 + pixels[offset + 2] * 0.0722
        }
        let outputLuma = shadowCoordinates.map { x, y in
            let offset = (y * width + x) * 4
            return rendered[offset] * 0.2126 + rendered[offset + 1] * 0.7152 + rendered[offset + 2] * 0.0722
        }
        let brightA = rendered[(height / 2 * width + width - 4) * 4]
        let brightB = rendered[((height / 2 + 1) * width + width - 4) * 4]
        func standardDeviation(_ values: [Float]) -> Double {
            let mean = values.reduce(0, +) / Float(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(values.count)
            return sqrt(Double(variance))
        }

        XCTAssertLessThan(standardDeviation(outputChroma), standardDeviation(inputChroma) * 0.45)
        XCTAssertLessThan(standardDeviation(outputLuma), standardDeviation(inputLuma) * 0.75)
        XCTAssertGreaterThan(abs(brightA - brightB), 0.1)
    }

    func testShadowChromaDenoiseNeutralizesPurpleBiasInDeepShadows() {
        let width = 64
        let height = 32
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if x < width / 2 {
                    let alternating: Float = (x + y).isMultiple(of: 2) ? 0.035 : -0.035
                    pixels[offset] = 0.11 + alternating
                    pixels[offset + 1] = 0.075
                    pixels[offset + 2] = 0.13 - alternating
                } else {
                    let detail: Float = y.isMultiple(of: 2) ? 0.70 : 0.86
                    pixels[offset] = detail
                    pixels[offset + 1] = detail
                    pixels[offset + 2] = detail
                }
            }
        }
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let input = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let output = ScannerNoiseReduction.reduceShadowChroma(in: input)
        var rendered = [Float](repeating: 0, count: pixels.count)
        CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear]).render(
            output,
            toBitmap: &rendered,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )

        let shadowCoordinates = (3..<(height - 3)).flatMap { y in
            (3..<(width / 2 - 3)).map { x in (x, y) }
        }
        let meanRedBlueBias = shadowCoordinates.map { x, y in
            let offset = (y * width + x) * 4
            return Double(rendered[offset] - rendered[offset + 2])
        }.reduce(0, +) / Double(shadowCoordinates.count)
        let brightA = rendered[(height / 2 * width + width - 4) * 4]
        let brightB = rendered[((height / 2 + 1) * width + width - 4) * 4]

        XCTAssertLessThan(abs(meanRedBlueBias), 0.015, "암부 보라색 편향은 색차 노이즈 감소 후 중립에 가까워야 한다.")
        XCTAssertGreaterThan(abs(brightA - brightB), 0.1, "밝은 영역의 실제 디테일은 유지해야 한다.")
    }

    func testScannerNoiseReductionSoftensMidtoneChromaWithoutBleedingLumaEdges() {
        let width = 72
        let height = 36
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if x < width / 2 {
                    let alternating: Float = (x + y).isMultiple(of: 2) ? 0.035 : -0.035
                    pixels[offset] = 0.58 + alternating
                    pixels[offset + 1] = 0.50
                    pixels[offset + 2] = 0.38 - alternating
                } else {
                    let detail: Float = y < height / 2 ? 0.38 : 0.70
                    pixels[offset] = detail + 0.08
                    pixels[offset + 1] = detail
                    pixels[offset + 2] = detail - 0.04
                }
            }
        }
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let input = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let output = ScannerNoiseReduction.reduceShadowChroma(in: input)
        var rendered = [Float](repeating: 0, count: pixels.count)
        CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear]).render(
            output,
            toBitmap: &rendered,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )

        let midtoneCoordinates = (4..<(height - 4)).flatMap { y in
            (4..<(width / 2 - 4)).map { x in (x, y) }
        }
        func meanChroma(_ buffer: [Float]) -> Double {
            midtoneCoordinates.map { x, y in
                let offset = (y * width + x) * 4
                let r = Double(buffer[offset])
                let g = Double(buffer[offset + 1])
                let b = Double(buffer[offset + 2])
                let luma = r * 0.2126 + g * 0.7152 + b * 0.0722
                return sqrt(pow(r - luma, 2) + pow(g - luma, 2) + pow(b - luma, 2))
            }.reduce(0, +) / Double(midtoneCoordinates.count)
        }
        func meanLuma(_ buffer: [Float]) -> Double {
            midtoneCoordinates.map { x, y in
                lumaAt(buffer, x: x, y: y)
            }.reduce(0, +) / Double(midtoneCoordinates.count)
        }
        func lumaAt(_ buffer: [Float], x: Int, y: Int) -> Double {
            let offset = (y * width + x) * 4
            return Double(buffer[offset]) * 0.2126
                + Double(buffer[offset + 1]) * 0.7152
                + Double(buffer[offset + 2]) * 0.0722
        }

        let topLuma = lumaAt(rendered, x: width - 8, y: height / 4)
        let bottomLuma = lumaAt(rendered, x: width - 8, y: height * 3 / 4)
        XCTAssertLessThan(meanChroma(rendered), meanChroma(pixels) * 0.94, "중간톤 색차 노이즈는 평균 색차까지 약하게 낮춰야 한다.")
        XCTAssertLessThan(abs(meanLuma(rendered) - meanLuma(pixels)), 0.015, "중간톤 색차 정리가 luma를 들어올리거나 눌러 DR을 바꾸면 안 된다.")
        XCTAssertGreaterThan(bottomLuma - topLuma, 0.20, "중간톤 chroma 정리가 luma edge를 번지게 하면 안 된다.")
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
        let png = tempDir.appendingPathComponent("negaflow_export_\(UUID().uuidString).png")
        let tif = tempDir.appendingPathComponent("negaflow_export_\(UUID().uuidString).tif")
        let tiff = tempDir.appendingPathComponent("negaflow_export_\(UUID().uuidString).tiff")
        defer {
            try? FileManager.default.removeItem(at: jpg)
            try? FileManager.default.removeItem(at: jpeg)
            try? FileManager.default.removeItem(at: png)
            try? FileManager.default.removeItem(at: tif)
            try? FileManager.default.removeItem(at: tiff)
        }

        try ExportEngine.write(output, to: jpg, format: .jpeg, using: context)
        try ExportEngine.write(output, to: jpeg, format: .jpeg, using: context)
        try ExportEngine.write(output, to: png, format: .png, using: context)
        try ExportEngine.write(output, to: tif, format: .tiff16, using: context)
        try ExportEngine.write(output, to: tiff, format: .tiff16, using: context)

        for url in [jpg, jpeg, png, tif, tiff] {
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            XCTAssertGreaterThan(size, 1024, "\(url.lastPathComponent) 출력이 비어 있으면 안 된다.")
        }
        XCTAssertEqual(imageType(jpg), "public.jpeg")
        XCTAssertEqual(imageType(jpeg), "public.jpeg")
        XCTAssertEqual(imageType(png), "public.png")
        XCTAssertEqual(imageType(tif), "public.tiff")
        XCTAssertEqual(imageType(tiff), "public.tiff")
        XCTAssertEqual(bitsPerComponent(tiff), 16)
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

    func testImageLoaderTreatsScannerTIFFAsLinear() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cbtest_scanner_\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let image = CIImage(color: CIColor(red: 0.2, green: 0.1, blue: 0.05))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let context = CIContext()
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        try! context.writeTIFFRepresentation(of: image, to: tmp, format: .RGBAh, colorSpace: sRGB)

        let loaded = ImageLoader.loadScannerTIFF(tmp)
        XCTAssertEqual(loaded?.colorSpace?.name, CGColorSpace(name: CGColorSpace.linearSRGB)?.name)
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

    private func makeTestImage(
        bytes: [UInt8],
        width: Int,
        height: Int,
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    ) -> CIImage {
        var mutable = bytes
        let cg = CGContext(data: &mutable, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
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

    private func renderLinearRGBA8(
        _ image: CIImage,
        width: Int,
        height: Int,
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    ) -> [UInt8] {
        let ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: colorSpace,
        ])
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

    private func meanChannelDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        XCTAssertEqual(lhs.count, rhs.count)
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }
        let total = zip(lhs, rhs).reduce(0) { partial, pair in
            partial + abs(Int(pair.0) - Int(pair.1))
        }
        return Double(total) / Double(lhs.count)
    }

    private func lumaStandardDeviation(_ bytes: [UInt8], width: Int, height: Int) -> Double {
        let values: [Double] = (0..<(width * height)).map { index in
            Double(luma(bytes, x: index % width, y: index / width, width: width))
        }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)
        return sqrt(variance)
    }

    private func channelStandardDeviation(_ bytes: [UInt8], channel: Int, width: Int, height: Int) -> Double {
        let values: [Double] = (0..<(width * height)).map { index in
            Double(bytes[index * 4 + channel])
        }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)
        return sqrt(variance)
    }

    private func meanLuma(_ bytes: [UInt8]) -> Double {
        var sum = 0.0
        var count = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            sum += Double(bytes[i]) * 0.2126 + Double(bytes[i + 1]) * 0.7152 + Double(bytes[i + 2]) * 0.0722
            count += 1
        }
        return sum / Double(max(1, count))
    }

    private func meanChroma(_ bytes: [UInt8]) -> Double {
        var sum = 0.0
        var count = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = Double(bytes[i]) / 255.0
            let g = Double(bytes[i + 1]) / 255.0
            let b = Double(bytes[i + 2]) / 255.0
            let y = r * 0.2126 + g * 0.7152 + b * 0.0722
            sum += sqrt(pow(r - y, 2) + pow(g - y, 2) + pow(b - y, 2))
            count += 1
        }
        return sum / Double(max(1, count))
    }

    private func imageType(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceGetType(source) as String?
    }

    private func bitsPerComponent(_ url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image.bitsPerComponent
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
        let image = makeTestImage(
            bytes: bytes,
            width: width,
            height: height,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        return (image, FilmBase(rgb: base, source: .border), width, height)
    }
}
