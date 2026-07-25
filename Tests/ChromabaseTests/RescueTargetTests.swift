import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

/// EXPIRED is intentionally a no-harm target. These tests exercise the whole frame and the
/// evidence gate; they do not treat a preferred scalar contrast or saturation value as truth.
final class RescueTargetTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private let extendedLinear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private let negativeBase = SIMD3<Double>(0.84, 0.56, 0.38)

    func testRescueTargetCompatibility() throws {
        XCTAssertEqual(DevelopTarget.rescue.rawValue, "rescue")
        XCTAssertEqual(DevelopTarget.rescue.displayName, "EXPIRED")
        XCTAssertFalse(DevelopTarget.rescue.isScannerEmulation)
        XCTAssertTrue(DevelopTarget.allCases.contains(.rescue))

        let encoded = try JSONEncoder().encode(DevelopTarget.rescue)
        XCTAssertEqual(try JSONDecoder().decode(DevelopTarget.self, from: encoded), .rescue)
    }

    /// EXPIRED 는 열화 필름 복구 타겟이다 — 측정된 캐스트 증거가 없는 건강한 네거티브에서는
    /// 복구할 열화가 없으므로 MAIN 과 픽셀 동일(no-op)이 올바른 동작이다.
    func testNegativeWithoutEligibleEvidenceIsPixelExactMain() {
        let width = 160
        let height = 96
        let input = makeNegativeNeutralRamp(width: width, height: height)
        let base = FilmBase(rgb: negativeBase, source: .manual)

        let main = developed(input, base: base, filmType: .colorNegative, target: .main)
        let expired = developed(input, base: base, filmType: .colorNegative, target: .rescue)

        XCTAssertEqual(renderFloat(main, width: width, height: height),
                       renderFloat(expired, width: width, height: height))
    }

    func testPositiveWithoutEligibleEvidenceIsPixelExactMainAndDoesNotStretchRange() {
        let width = 160
        let height = 96
        let input = makeFloatImage(width: width, height: height) { x, _ in
            let v = 0.08 + 0.46 * Double(x) / Double(width - 1)
            return (v, v, v)
        }

        let main = developed(input, base: nil, filmType: .colorPositive, target: .main)
        let expired = developed(input, base: nil, filmType: .colorPositive, target: .rescue)

        XCTAssertEqual(renderFloat(main, width: width, height: height),
                       renderFloat(expired, width: width, height: height),
                       "EXPIRED 이름만으로 positive range나 base grade를 바꾸면 안 됩니다")
    }

    func testRescueIgnoresStaleScannerProfileForNegativeAndPositive() {
        let profileID = "noritsu__color-nega__kodak-ultramax-400"
        XCTAssertNotNil(ScannerProfileRegistry.load(named: profileID), "픽스처 profile이 실제로 로드돼야 합니다")

        let width = 160
        let height = 96
        let positive = makeFloatImage(width: width, height: height) { x, _ in
            let v = 0.08 + 0.78 * Double(x) / Double(width - 1)
            return (v, v, v)
        }
        let negative = makeNegativeNeutralRamp(width: width, height: height)
        let base = FilmBase(rgb: negativeBase, source: .manual)

        for (image, filmType, filmBase) in [
            (positive, FilmType.colorPositive, Optional<FilmBase>.none),
            (negative, FilmType.colorNegative, Optional(base)),
        ] {
            let clean = developed(image, base: filmBase, filmType: filmType, target: .rescue)
            let stale = developed(
                image,
                base: filmBase,
                filmType: filmType,
                target: .rescue,
                scannerProfileID: profileID
            )
            XCTAssertEqual(renderFloat(clean, width: width, height: height),
                           renderFloat(stale, width: width, height: height),
                           "EXPIRED에 남아 있던 scannerProfileID를 겹쳐 적용하면 안 됩니다")
        }
    }

    func testEvidenceRequiresAtLeastThreeNeutralLuminanceBands() {
        let image = makeFloatImage(width: 160, height: 96) { _, _ in
            (0.34, 0.30, 0.32)
        }
        let recovery = RescueGrade.measureRecovery(in: image)

        XCTAssertFalse(recovery.isEligible, "recovery=\(recovery)")
        XCTAssertLessThan(recovery.eligibleBandCount, RescueGrade.minimumEligibleBandCount)
        XCTAssertEqual(
            renderFloat(image, width: 160, height: 96),
            renderFloat(RescueGrade.apply(to: image, sampleColorSpace: linear), width: 160, height: 96)
        )
    }

    func testEvidenceRejectsNeutralSamplesWithoutSpatialCoverage() {
        let width = 192
        let height = 120
        let image = makeFloatImage(width: width, height: height) { x, y in
            if x < width / 5, y < height / 3 {
                let v = 0.04 + 0.82 * Double(y) / Double(max(height / 3 - 1, 1))
                return (v * 1.06, v * 0.94, v * 1.01)
            }
            let v = 0.18 + 0.62 * Double(x) / Double(width - 1)
            return (v, v * 0.18, v * 0.08)
        }
        let recovery = RescueGrade.measureRecovery(in: image)

        XCTAssertFalse(recovery.isEligible, "recovery=\(recovery)")
        XCTAssertLessThan(recovery.coveredTileCount, RescueGrade.minimumCoveredTileCount)
    }

    func testEvidenceRejectsSpatiallyAlternatingColourVariation() {
        let width = 192
        let height = 120
        let image = makeFloatImage(width: width, height: height) { x, y in
            let v = 0.04 + 0.82 * Double(x) / Double(width - 1)
            let sign = ((x / 16 + y / 16).isMultiple(of: 2)) ? 1.0 : -1.0
            return (v * (1 + sign * 0.045), v * (1 - sign * 0.040), v * (1 + sign * 0.025))
        }
        let recovery = RescueGrade.measureRecovery(in: image)

        XCTAssertFalse(recovery.isEligible, "recovery=\(recovery)")
    }

    func testEvidenceRejectsHighMADNeutralPopulation() {
        let width = 192
        let height = 120
        let image = makeFloatImage(width: width, height: height) { x, y in
            let l = 18.0 + 68.0 * Double(x) / Double(width - 1)
            let phase = Double((x &* 17 &+ y &* 29) % 101) / 100.0
            let a = 5.0 + (phase - 0.5) * 12.0
            let b = -3.0 + (0.5 - phase) * 10.0
            let rgb = ScannerTargetGrade.labToSRGB(l: l, a: a, b: b)
            return (
                ScannerTargetGrade.srgbDecode(rgb.r),
                ScannerTargetGrade.srgbDecode(rgb.g),
                ScannerTargetGrade.srgbDecode(rgb.b)
            )
        }
        let recovery = RescueGrade.measureRecovery(in: image)

        XCTAssertFalse(recovery.isEligible, "recovery=\(recovery)")
    }

    func testRepeatableNeutralEvidenceEnablesBoundedRelativeCorrection() {
        let width = 192
        let height = 120
        let image = makeMeasuredCastRamp(width: width, height: height)
        let recovery = RescueGrade.measureRecovery(in: image)

        XCTAssertTrue(recovery.isEligible, "recovery=\(recovery)")
        XCTAssertGreaterThanOrEqual(recovery.eligibleBandCount, 3)
        XCTAssertGreaterThanOrEqual(recovery.coveredTileCount, 6)
        XCTAssertGreaterThanOrEqual(recovery.holdoutSampleCount, 24)
        XCTAssertLessThanOrEqual(recovery.maximumObservedMAD, RescueGrade.maximumBandMAD)
        XCTAssertLessThanOrEqual(recovery.maximumObservedHoldoutDelta, RescueGrade.maximumHoldoutDelta)

        let corrected = RescueGrade.apply(to: image, sampleColorSpace: linear)
        XCTAssertLessThan(
            meanLabChroma(corrected, width: width, height: height),
            meanLabChroma(image, width: width, height: height) * 0.65,
            "holdout으로 확인된 중립축 오차만 상대적으로 줄여야 합니다"
        )
    }

    func testRecoverRangeFlagCannotReintroduceAutoLevels() {
        let width = 192
        let height = 120
        let image = makeMeasuredCastRamp(width: width, height: height)
        let enabled = RescueGrade.apply(
            to: image,
            sampleColorSpace: linear,
            recoverRange: true
        )
        let disabled = RescueGrade.apply(
            to: image,
            sampleColorSpace: linear,
            recoverRange: false
        )

        XCTAssertEqual(renderFloat(enabled, width: width, height: height),
                       renderFloat(disabled, width: width, height: height))
    }

    func testCorrectionIsDeterministic() {
        let width = 192
        let height = 120
        let image = makeMeasuredCastRamp(width: width, height: height)
        let first = RescueGrade.apply(to: image, sampleColorSpace: linear)
        let second = RescueGrade.apply(to: image, sampleColorSpace: linear)

        XCTAssertEqual(renderFloat(first, width: width, height: height),
                       renderFloat(second, width: width, height: height))
    }

    func testExtendedRangeSamplesRemainUnclampedAndWithoutPlateaus() {
        let width = 192
        let height = 120
        let image = makeFloatImage(width: width, height: height) { x, _ in
            if x < 24 {
                let v = -0.30 + 0.26 * Double(x) / 23.0
                return (v, v * 0.8, v * 0.6)
            }
            if x >= width - 24 {
                let v = 1.04 + 0.36 * Double(x - (width - 24)) / 23.0
                return (v, v * 1.03, v * 1.06)
            }
            let unitX = Double(x - 24) / Double(width - 49)
            let v = 0.03 + 0.88 * unitX
            return (v * 1.06, v * 0.94, v * 1.01)
        }
        let recovery = RescueGrade.measureRecovery(in: image)
        XCTAssertTrue(recovery.isEligible, "unit-cube evidence가 있어야 extended 보존 경로도 검증할 수 있습니다")

        let corrected = RescueGrade.apply(to: image, sampleColorSpace: linear)
        let sourcePixels = renderFloat(image, width: width, height: height)
        let correctedPixels = renderFloat(corrected, width: width, height: height)

        for y in 0..<height {
            for x in 0..<width where x < 24 || x >= width - 24 {
                let offset = (y * width + x) * 4
                for channel in 0..<3 {
                    XCTAssertEqual(
                        correctedPixels[offset + channel],
                        sourcePixels[offset + channel],
                        accuracy: 1e-6,
                        "측정 cube 밖 값은 원본 방향과 크기를 그대로 보존해야 합니다"
                    )
                }
            }
            for x in 0..<23 {
                XCTAssertGreaterThan(
                    correctedPixels[(y * width + x + 1) * 4],
                    correctedPixels[(y * width + x) * 4],
                    "negative extended ramp에 plateau가 생기면 안 됩니다"
                )
            }
            for x in (width - 24)..<(width - 1) {
                XCTAssertGreaterThan(
                    correctedPixels[(y * width + x + 1) * 4],
                    correctedPixels[(y * width + x) * 4],
                    "positive extended ramp에 plateau가 생기면 안 됩니다"
                )
            }
        }
    }

    // MARK: - Fixtures

    private func makeFloatImage(
        width: Int,
        height: Int,
        pixel: (Int, Int) -> (Double, Double, Double)
    ) -> CIImage {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = pixel(x, y)
                let offset = (y * width + x) * 4
                pixels[offset] = Float(r)
                pixels[offset + 1] = Float(g)
                pixels[offset + 2] = Float(b)
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: extendedLinear
        )
    }

    private func makeNegativeNeutralRamp(width: Int, height: Int) -> CIImage {
        makeFloatImage(width: width, height: height) { x, _ in
            let density = 0.08 + 1.62 * Double(x) / Double(width - 1)
            return (
                negativeBase.x * pow(10, -density),
                negativeBase.y * pow(10, -density),
                negativeBase.z * pow(10, -density)
            )
        }
    }

    private func makeMeasuredCastRamp(width: Int, height: Int) -> CIImage {
        makeFloatImage(width: width, height: height) { x, y in
            let v = 0.03 + 0.88 * Double(x) / Double(width - 1)
            let spatialJitter = (Double((x &* 13 &+ y &* 7) % 11) - 5) * 0.00012
            return (
                v * 1.06 + spatialJitter,
                v * 0.94,
                v * 1.01 - spatialJitter
            )
        }
    }

    private func developed(
        _ image: CIImage,
        base: FilmBase?,
        filmType: FilmType,
        target: DevelopTarget,
        scannerProfileID: String? = nil
    ) -> CIImage {
        var params = DevelopParameters()
        params.filmType = filmType
        params.developTarget = target
        params.scannerProfileID = scannerProfileID
        return ChromabaseEngine().develop(image: image, base: base, params: params)
    }

    private func renderFloat(_ image: CIImage, width: Int, height: Int) -> [Float] {
        let context = CIContext(options: [
            .workingColorSpace: extendedLinear,
            .outputColorSpace: extendedLinear,
        ])
        var pixels = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: extendedLinear
        )
        return pixels
    }

    private func meanLabChroma(_ image: CIImage, width: Int, height: Int) -> Double {
        let pixels = renderFloat(image, width: width, height: height)
        var chromaSum = 0.0
        var count = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[offset])
            let g = Double(pixels[offset + 1])
            let b = Double(pixels[offset + 2])
            guard min(r, min(g, b)) > 0.02, max(r, max(g, b)) < 0.98 else { continue }
            let lab = ScannerTargetGrade.srgbToLab(
                r: ScannerTargetGrade.srgbEncode(r),
                g: ScannerTargetGrade.srgbEncode(g),
                b: ScannerTargetGrade.srgbEncode(b)
            )
            chromaSum += hypot(lab.a, lab.b)
            count += 1
        }
        return count > 0 ? chromaSum / Double(count) : 0
    }
}
