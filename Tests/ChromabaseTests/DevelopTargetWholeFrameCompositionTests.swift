import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

/// 기본 타겟 경로에 문서화되지 않은 공간 필터나 색 변형이 끼어들지 않는지 전체 프레임으로 검증한다.
///
/// 이 테스트는 색감의 미적 품질이나 스캐너 재현 정확도를 숫자로 판정하지 않는다. 그 판단에는
/// 동일 네거티브의 실기 reference scan과 사람의 시각 QA가 필요하다. 여기서는 모든 픽셀에 대해
/// `반전 -> 타겟 변환`으로 선언된 조합과 실제 엔진 조합이 같은지만 확인한다.
final class DevelopTargetWholeFrameCompositionTests: XCTestCase {
    private let width = 192
    private let height = 128
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private let baseRGB = SIMD3<Double>(0.84, 0.55, 0.34)

    @MainActor
    func testDefaultTargetsContainOnlyTheirDeclaredWholeFrameTransform() {
        let input = makeSpatialColorNegative()
        let base = FilmBase(rgb: baseRGB, source: .manual)

        for target in DevelopTarget.allCases {
            XCTContext.runActivity(named: target.displayName) { _ in
                var params = DevelopParameters()
                params.filmType = .colorNegative
                params.developTarget = target
                params.baseEstimationMode = .manual
                params.manualBaseRGB = baseRGB

                let actual = ChromabaseEngine().applyNegativeFilmPipeline(
                    to: input,
                    base: base,
                    params: params,
                    sampleColorSpace: linear,
                    extent: input.extent
                )
                let expected = declaredTargetTransform(
                    input: input,
                    base: base,
                    params: params
                )

                assertWholeFrameEqual(actual, expected, target: target)
            }
        }
    }

    func testMainDoesNotClampExtendedWholeFrameWorkingValues() {
        let input = makeExtendedPositiveScene()
        var params = DevelopParameters()
        params.filmType = .colorPositive
        params.developTarget = .main

        let actual = ChromabaseEngine().develop(image: input, base: nil, params: params)
        assertWholeFrameEqual(actual, input, target: .main)
    }

    func testProvidedFilmBaseSourceDoesNotChangeWholeFrameDensityEncoding() {
        let input = makeSpatialColorNegative()
        let manual = NegativeInversion.apply(
            to: input,
            base: FilmBase(rgb: baseRGB, source: .manual)
        )

        for source in [FilmBase.Source.auto, .border] {
            let measured = NegativeInversion.apply(
                to: input,
                base: FilmBase(rgb: baseRGB, source: source)
            )
            assertWholeFrameEqual(measured, manual, target: .main)
        }
    }

    /// scene-adaptive 반전은 **채널별** 측정 Dmax 로 필름 염료 기울기 차이를 독립 정규화한다
    /// (= 자동 화이트밸런스, 오렌지/블루 캐스트·탈채도 제거). 단 물성 하한(densestFloor 1.8D)이
    /// 극단 단색 장면의 채널 폭주(→ 보라 hue shift)를 막으므로, 채널 간 Dmax 비는 유계여야 한다.
    /// 과거의 "RGB 공통 스케일" 계약은 이 채널별 WB 를 막아 잔여 캐스트를 남겼다(회귀 원인).
    func testGenericDensityScaleIsPerChannelButBounded() throws {
        let stats = try XCTUnwrap(
            NegativeInversion.sampleStats(
                makeSpatialColorNegative(),
                base: FilmBase(rgb: baseRGB, source: .manual)
            )
        )
        let mx = max(stats.dmaxNorm.x, max(stats.dmaxNorm.y, stats.dmaxNorm.z))
        let mn = min(stats.dmaxNorm.x, min(stats.dmaxNorm.y, stats.dmaxNorm.z))
        XCTAssertGreaterThan(mn, 0.4, "채널 Dmax 하한(저신호 폭주 방지)")
        XCTAssertLessThan(mx / mn, 2.0,
            "채널 간 Dmax 비가 유계여야 한다(물성 하한이 단색 장면 폭주를 막음). ratio=\(mx / mn)")
    }

    func testGenericMainKeepsSubjectTileIndependentOfSurroundingScene() {
        let base = FilmBase(rgb: baseRGB, source: .manual)
        let lowKey = render(NegativeInversion.apply(
            to: makeContextVariantNegative(surroundingDensity: 0.18),
            base: base
        ))
        let highKey = render(NegativeInversion.apply(
            to: makeContextVariantNegative(surroundingDensity: 2.55),
            base: base
        ))
        let tileX = (width - 64) / 2
        let tileY = (height - 48) / 2
        var changedSamples = 0
        var maximumError = 0.0

        for y in tileY..<(tileY + 48) {
            for x in tileX..<(tileX + 64) {
                for channel in 0..<3 {
                    let offset = (y * width + x) * 4 + channel
                    let error = abs(Double(lowKey[offset] - highKey[offset]))
                    maximumError = max(maximumError, error)
                    if error > 1e-5 { changedSamples += 1 }
                }
            }
        }

        XCTAssertEqual(
            changedSamples,
            0,
            "같은 피사체 밀도는 주변 장면 분포와 무관해야 합니다. "
                + "changed=\(changedSamples)/\(64 * 48 * 3), maxError=\(maximumError)"
        )
    }

    func testFixedPrintResponseKeepsBrighterThanBaseValuesInsideDisplayRange() {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = Float(baseRGB.x * 1.08)
            pixels[offset + 1] = Float(baseRGB.y * 1.08)
            pixels[offset + 2] = Float(baseRGB.z * 1.08)
        }
        let input = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let output = render(NegativeInversion.apply(
            to: input,
            base: FilmBase(rgb: baseRGB, source: .manual)
        ))

        let baseOutput = NegativeInversion.positiveValue(
            transmission: baseRGB.x,
            dmin: baseRGB.x,
            dmaxNorm: 1.6
        )
        var invalidSamples = 0
        for offset in stride(from: 0, to: output.count, by: 4) {
            for channel in 0..<3 {
                let value = Double(output[offset + channel])
                if !value.isFinite || value < 0 || value >= baseOutput {
                    invalidSamples += 1
                }
            }
        }
        XCTAssertEqual(
            invalidSamples,
            0,
            "베이스보다 밝은 유한 입력은 paper-black 아래의 유한 표시값이어야 합니다. "
                + "invalid=\(invalidSamples)/\(width * height * 3)"
        )
    }

    func testMainDensityRampHasNoWholeFramePlateau() {
        let input = makeWideDensityRamp()
        let output = NegativeInversion.apply(
            to: input,
            base: FilmBase(rgb: baseRGB, source: .manual)
        )
        let pixels = render(output)
        var plateauPairs = 0
        var maximum = -Double.infinity

        for y in 0..<height {
            for channel in 0..<3 {
                for x in 0..<(width - 1) {
                    let current = Double(pixels[(y * width + x) * 4 + channel])
                    let next = Double(pixels[(y * width + x + 1) * 4 + channel])
                    maximum = max(maximum, current, next)
                    if !(next > current) { plateauPairs += 1 }
                }
            }
        }

        XCTAssertEqual(
            plateauPairs,
            0,
            "MAIN 밀도 램프의 서로 다른 입력이 같은 출력 계조로 뭉치면 안 됩니다. "
                + "plateauPairs=\(plateauPairs)/\(height * (width - 1) * 3)"
        )
        XCTAssertGreaterThan(maximum, 0.85, "고밀도 명부가 과도하게 눌렸습니다. max=\(maximum)")
        XCTAssertLessThan(
            maximum,
            1,
            "고밀도 명부는 soft-clip으로 1 아래에서 끝나야 합니다. max=\(maximum)"
        )
    }

    private func declaredTargetTransform(
        input: CIImage,
        base: FilmBase,
        params: DevelopParameters
    ) -> CIImage {
        // auto(프리셋 없음) 파이프라인은 scene-adaptive 반전을 쓴다(applySceneRanged). 이 테스트의
        // 계약은 "반전 뒤 타겟 변환 외에 미선언 공간필터·색변형이 없다" 이므로, 선언 조합의 반전도
        // 파이프라인과 같은 applySceneRanged 를 사용한다(primitive apply 는 별도 결정적 참조).
        var image = NegativeInversion.applySceneRanged(to: input, base: base)

        switch params.developTarget {
        case .main:
            break
        case .print:
            image = PrintPaperGrade.apply(to: image)
        case .noritsu, .sp3000, .f135, .hr:
            image = ScannerTargetGrade.apply(
                to: image,
                target: params.developTarget,
                params: params
            )
        case .rescue:
            image = RescueGrade.apply(
                to: image,
                sampleColorSpace: linear,
                filmType: params.filmType,
                recoverRange: true
            )
        }

        image = ColorModel.apply(to: image, params: params)
        image = ToneMapper.applyExposure(to: image, stops: params.exposure)
        return ToneMapper.applyToneCurves(to: image, params: params)
    }

    /// 그라데이션, 색상 순환, 저·고주파 텍스처, 곡선 경계를 한 프레임에 섞는다.
    /// 단색 패치 평균만 맞추는 구현은 이 프레임의 모든 위치를 동시에 통과할 수 없다.
    private func makeSpatialColorNegative() -> CIImage {
        var pixels = [Float](repeating: 1, count: width * height * 4)

        for y in 0..<height {
            let v = Double(y) / Double(height - 1)
            for x in 0..<width {
                let u = Double(x) / Double(width - 1)
                let radial = hypot(u - 0.52, v - 0.48)
                let lowFrequency = 0.10 * sin(2 * .pi * (u * 1.7 + v * 0.9))
                let fineTexture = 0.035 * sin(2 * .pi * u * 19) * cos(2 * .pi * v * 13)
                let checker = ((x / 3 + y / 3).isMultiple(of: 2) ? 0.018 : -0.018)
                var density = 0.22 + 1.72 * (0.62 * u + 0.38 * v)
                    + lowFrequency + fineTexture + checker

                if radial < 0.18 {
                    density += 0.30 * (1 - radial / 0.18)
                }
                if u > 0.70, v > 0.58 {
                    density -= 0.24 * (u - 0.70) / 0.30
                }

                let hue = 2 * Double.pi * (u + 0.37 * v)
                let chroma = 0.08 + 0.20 * (0.5 + 0.5 * sin(2 * .pi * v * 2.3))
                let colorOffsets = SIMD3<Double>(
                    chroma * cos(hue),
                    chroma * cos(hue - 2 * .pi / 3),
                    chroma * cos(hue + 2 * .pi / 3)
                )
                let densities = SIMD3<Double>(repeating: density) + colorOffsets
                let offset = (y * width + x) * 4
                pixels[offset] = transmission(densities.x, baseRGB.x)
                pixels[offset + 1] = transmission(densities.y, baseRGB.y)
                pixels[offset + 2] = transmission(densities.z, baseRGB.z)
            }
        }

        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func makeExtendedPositiveScene() -> CIImage {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            let v = Double(y) / Double(height - 1)
            for x in 0..<width {
                let u = Double(x) / Double(width - 1)
                let highlight = 1.65 * pow(u, 1.4)
                let texture = 0.06 * sin(2 * .pi * u * 17) * cos(2 * .pi * v * 11)
                let hue = 2 * .pi * (u + v * 0.25)
                let offset = (y * width + x) * 4
                pixels[offset] = Float(0.04 + highlight + texture + 0.16 * cos(hue))
                pixels[offset + 1] = Float(0.04 + highlight + texture + 0.16 * cos(hue - 2 * .pi / 3))
                pixels[offset + 2] = Float(0.04 + highlight + texture + 0.16 * cos(hue + 2 * .pi / 3))
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func makeWideDensityRamp() -> CIImage {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            let rowOffset = 0.08 * Double(y) / Double(height - 1)
            for x in 0..<width {
                let u = Double(x) / Double(width - 1)
                let density = 0.05 + 2.75 * u + rowOffset
                let offset = (y * width + x) * 4
                pixels[offset] = Float(baseRGB.x * pow(10, -density))
                pixels[offset + 1] = Float(baseRGB.y * pow(10, -(density + 0.03)))
                pixels[offset + 2] = Float(baseRGB.z * pow(10, -(density + 0.06)))
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func makeContextVariantNegative(surroundingDensity: Double) -> CIImage {
        let tileX = (width - 64) / 2
        let tileY = (height - 48) / 2
        var pixels = [Float](repeating: 1, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let inTile = x >= tileX && x < tileX + 64 && y >= tileY && y < tileY + 48
                let density: Double
                let offsets: SIMD3<Double>
                if inTile {
                    let u = Double(x - tileX) / 63.0
                    let v = Double(y - tileY) / 47.0
                    density = 0.42 + 1.34 * (0.58 * u + 0.42 * v)
                        + 0.07 * sin(2 * .pi * u * 9) * cos(2 * .pi * v * 7)
                    offsets = SIMD3(0.12 * sin(2 * .pi * u),
                                    0.10 * sin(2 * .pi * (u + 1.0 / 3.0)),
                                    0.11 * sin(2 * .pi * (u + 2.0 / 3.0)))
                } else {
                    density = surroundingDensity
                    offsets = surroundingDensity < 1
                        ? SIMD3(0.16, -0.08, -0.08)
                        : SIMD3(-0.12, -0.04, 0.16)
                }
                let d = SIMD3<Double>(repeating: density) + offsets
                let offset = (y * width + x) * 4
                pixels[offset] = Float(baseRGB.x * pow(10, -d.x))
                pixels[offset + 1] = Float(baseRGB.y * pow(10, -d.y))
                pixels[offset + 2] = Float(baseRGB.z * pow(10, -d.z))
            }
        }

        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func transmission(_ density: Double, _ base: Double) -> Float {
        Float(base * pow(10, -max(0.04, min(2.35, density))))
    }

    private func render(_ image: CIImage) -> [Float] {
        let context = CIContext(options: [
            .workingColorSpace: linear,
            .outputColorSpace: linear,
            .workingFormat: CIFormat.RGBAf,
        ])
        var pixels = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        return pixels
    }

    private func assertWholeFrameEqual(
        _ actualImage: CIImage,
        _ expectedImage: CIImage,
        target: DevelopTarget,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = render(actualImage)
        let expected = render(expectedImage)
        var changedPixels = 0
        var maximumError = 0.0
        var squaredError = 0.0
        var sampleCount = 0
        let tolerance = 1e-4

        for pixel in 0..<(width * height) {
            var pixelChanged = false
            for channel in 0..<3 {
                let index = pixel * 4 + channel
                let error = abs(Double(actual[index] - expected[index]))
                maximumError = max(maximumError, error)
                squaredError += error * error
                sampleCount += 1
                if error > tolerance { pixelChanged = true }
            }
            if pixelChanged { changedPixels += 1 }
        }

        let rms = sqrt(squaredError / Double(max(1, sampleCount)))
        XCTAssertEqual(
            changedPixels,
            0,
            "\(target.displayName) 기본 경로가 선언된 타겟 변환 외에 전체 프레임을 변경했습니다. "
                + "changed=\(changedPixels)/\(width * height), maxError=\(maximumError), rms=\(rms)",
            file: file,
            line: line
        )
    }
}
