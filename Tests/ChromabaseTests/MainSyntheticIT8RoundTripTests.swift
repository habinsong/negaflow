import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

/// MAIN의 결정적 밀도 좌표를 12행 x 22열 전 패치로 검증한다.
///
/// 이 fixture는 `syntheticModel` 증거다. 실제 필름/스캐너 색 정확도를 주장하지 않으며,
/// forward negative 수학과 독립 reference 색을 고정해 MAIN 기본 경로에 숨은 탈색, 톤 커브,
/// 장면 적응, gamut clamp가 다시 들어오는지만 패치별로 검출한다.
final class MainSyntheticIT8RoundTripTests: XCTestCase {
    private let rows = 12
    private let columns = 22
    private let patchSize = 12
    private let baseRGB = SIMD3<Double>(0.84, 0.55, 0.34)
    // 선언된 공개 인화 응답의 계약 상수(구현을 참조하지 않고 픽스처에 고정한 사본).
    // docs/reference/PRINT_RESPONSE.md 의 컬러 앵커와 동일해야 한다.
    private let fixtureDmax = 0.62 * 2.5           // 명목 정규화 범위 1.55
    private let fixtureBaseToe = 0.001
    private let fixtureMidOutput = 0.18
    private let fixtureMidDensity = 0.60
    private let fixtureWhiteOutput = 0.70
    private let fixtureCeiling = 0.90
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    func testPhotometricDensityCPUReferenceRoundTripsAll264IT8StylePatches() {
        var measuredChannelCount = 0
        for row in 0..<rows {
            for column in 0..<columns {
                let code = referenceCode(row: row, column: column)
                let expected = SIMD3(
                    sRGBDecode(code.x),
                    sRGBDecode(code.y),
                    sRGBDecode(code.z)
                )
                for channel in 0..<3 {
                    let transmission = transmission(
                        forLinear: expected[channel],
                        base: baseRGB[channel]
                    )
                    let actual = NegativeInversion.positiveValue(
                        transmission: transmission,
                        dmin: baseRGB[channel],
                        dmaxNorm: fixtureDmax
                    )
                    XCTAssertEqual(
                        actual,
                        expected[channel],
                        accuracy: 1e-9,
                        "\(patchID(row: row, column: column)) channel \(channel)"
                    )
                    measuredChannelCount += 1
                }
            }
        }
        XCTAssertEqual(measuredChannelCount, 264 * 3)
    }

    /// MAIN 은 auto 경로의 scene-adaptive 반전(applySceneRanged)만 적용하고 별도 룩(탈색, 톤
    /// 커브, gamut clamp)을 굽지 않는다. scene-adaptive 반전은 필름 염료 밀도 범위를 채널별로
    /// 정규화(= 자동 화이트밸런스)하므로 고정 인화 응답과 절대색이 같지 않다(그게 캐스트/탈채도
    /// 교정의 본질). 따라서 이 테스트는 (1) MAIN == 반전(추가 룩 없음), (2) 중립축이 중립으로
    /// 유지(scene-adaptive 가 회색에 캐스트를 넣지 않음), (3) 유채색이 붕괴(탈채도)되지 않음을
    /// 검증한다. 절대색 라운드트립은 primitive positiveValue 를 쓰는 위 테스트가 담당한다.
    func testMainSyntheticIT8AppliesOnlySceneAdaptiveInversionKeepingNeutralsNeutral() {
        XCTAssertEqual(NegativeInversion.genericDensityEncodingVersion, "shoulder-print-response-v4")
        XCTAssertEqual(NegativeInversion.colorResponse.normalRange, fixtureDmax, accuracy: 1e-12)
        let fixture = makeFixture()
        var params = DevelopParameters()
        params.filmType = .colorNegative
        params.developTarget = .main
        params.baseEstimationMode = .manual
        params.manualBaseRGB = baseRGB

        let output = ChromabaseEngine().developScanner(
            image: fixture.negative,
            base: FilmBase(rgb: baseRGB, source: .manual),
            params: params
        )
        let pixels = render(output)
        let inversion = render(NegativeInversion.applySceneRanged(
            to: fixture.negative,
            base: FilmBase(rgb: baseRGB, source: .manual)
        ))

        var measuredPatchCount = 0
        for row in 0..<rows {
            for column in 0..<columns {
                let measuredRGB = patchMean(pixels, row: row, column: column)
                let inversionRGB = patchMean(inversion, row: row, column: column)
                let id = patchID(row: row, column: column)

                XCTAssertTrue(
                    measuredRGB.x.isFinite && measuredRGB.y.isFinite && measuredRGB.z.isFinite,
                    "\(id): MAIN patch contains a non-finite working value"
                )
                // (1) MAIN 은 반전 외 추가 룩이 없다.
                let lookDelta = ColorTargetColorimetry.deltaE2000(
                    ColorTargetColorimetry.linearSRGBToLabD50(measuredRGB),
                    ColorTargetColorimetry.linearSRGBToLabD50(inversionRGB)
                )
                XCTAssertLessThan(lookDelta, 0.05,
                    "\(id): MAIN 이 scene-adaptive 반전 위에 선언되지 않은 룩을 추가했다(ΔE=\(lookDelta))")

                // (2) 중립축은 중립 유지 — scene-adaptive 가 회색에 캐스트를 넣지 않는다.
                if row == rows - 1 {
                    let lab = ColorTargetColorimetry.linearSRGBToLabD50(measuredRGB)
                    let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
                    XCTAssertLessThan(chroma, 3.0,
                        "\(id): 중립 패치가 scene-adaptive 반전에서 캐스트가 생겼다(chroma=\(chroma))")
                }
                measuredPatchCount += 1
            }
        }

        // (3) 유채색 붕괴(탈채도) 금지 — 유채색 행의 평균 chroma 가 reference 의 절반 이상 유지.
        var refChromaSum = 0.0, outChromaSum = 0.0
        for row in 0..<(rows - 1) {
            for column in 0..<columns {
                let index = row * columns + column
                let ref = fixture.referenceLab[index]
                refChromaSum += (ref.a * ref.a + ref.b * ref.b).squareRoot()
                let outLab = ColorTargetColorimetry.linearSRGBToLabD50(
                    patchMean(pixels, row: row, column: column))
                outChromaSum += (outLab.a * outLab.a + outLab.b * outLab.b).squareRoot()
            }
        }
        XCTAssertGreaterThan(outChromaSum, refChromaSum * 0.5,
            "scene-adaptive 반전이 유채색을 탈채도로 붕괴시키면 안 된다. out=\(outChromaSum) ref=\(refChromaSum)")
        XCTAssertEqual(measuredPatchCount, 264)
    }

    private func makeFixture() -> (negative: CIImage, referenceLab: [ColorTargetLab]) {
        let width = columns * patchSize
        let height = rows * patchSize
        var pixels = [Float](repeating: 1, count: width * height * 4)
        var referenceLab: [ColorTargetLab] = []
        referenceLab.reserveCapacity(rows * columns)

        for row in 0..<rows {
            for column in 0..<columns {
                let code = referenceCode(row: row, column: column)
                let expectedLinear = SIMD3<Double>(
                    sRGBDecode(code.x),
                    sRGBDecode(code.y),
                    sRGBDecode(code.z)
                )
                referenceLab.append(ColorTargetColorimetry.linearSRGBToLabD50(expectedLinear))
                let transmission = SIMD3<Double>(
                    transmission(forLinear: expectedLinear.x, base: baseRGB.x),
                    transmission(forLinear: expectedLinear.y, base: baseRGB.y),
                    transmission(forLinear: expectedLinear.z, base: baseRGB.z)
                )

                for localY in 0..<patchSize {
                    let y = row * patchSize + localY
                    for localX in 0..<patchSize {
                        let x = column * patchSize + localX
                        let offset = (y * width + x) * 4
                        pixels[offset] = Float(transmission.x)
                        pixels[offset + 1] = Float(transmission.y)
                        pixels[offset + 2] = Float(transmission.z)
                    }
                }
            }
        }

        return (
            CIImage(
                bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: linear
            ),
            referenceLab
        )
    }

    /// 고정 인화 응답으로 역부호화 가능한 IT8형 hue/lightness/chroma sweep.
    private func referenceCode(row: Int, column: Int) -> SIMD3<Double> {
        if row == rows - 1 {
            let neutral = 0.03 + 0.87 * Double(column) / Double(columns - 1)
            return SIMD3(repeating: neutral)
        }

        let lightness = 0.06 + 0.82 * Double(column) / Double(columns - 1)
        let chromaWave = 0.35 + 0.60 * (0.5 + 0.5 * sin(Double(column) * 0.71))
        let hue = (Double(row) / Double(rows - 1) + Double(column) * 0.017)
            .truncatingRemainder(dividingBy: 1)
        let rgb = hslToRGB(hue: hue, saturation: chromaWave, lightness: lightness)
        return SIMD3(
            min(max(rgb.x, 0.03), 0.90),
            min(max(rgb.y, 0.03), 0.90),
            min(max(rgb.z, 0.03), 0.90)
        )
    }

    private func hslToRGB(hue: Double, saturation: Double, lightness: Double) -> SIMD3<Double> {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue * 6
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let prime: SIMD3<Double>
        switch Int(floor(sector)) % 6 {
        case 0: prime = SIMD3(chroma, x, 0)
        case 1: prime = SIMD3(x, chroma, 0)
        case 2: prime = SIMD3(0, chroma, x)
        case 3: prime = SIMD3(0, x, chroma)
        case 4: prime = SIMD3(x, 0, chroma)
        default: prime = SIMD3(chroma, 0, x)
        }
        return prime + SIMD3(repeating: lightness - chroma / 2)
    }

    private func sRGBDecode(_ value: Double) -> Double {
        value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    /// `NegativeInversion` 구현을 호출하지 않고 고정한 공개 인화 응답의 역함수를 적는다.
    /// 응답: log10(P) = yCeil − amplitude·exp(−(rate·d)^shape), 계수는 앵커에서 닫힌형 유도.
    private func transmission(forLinear value: Double, base: Double) -> Double {
        let yCeil = log10(fixtureCeiling)
        let amplitude = yCeil - log10(fixtureBaseToe)
        let rMid = log(amplitude / (yCeil - log10(fixtureMidOutput)))
        let rWhite = log(amplitude / (yCeil - log10(fixtureWhiteOutput)))
        let midFraction = fixtureMidDensity / fixtureDmax
        let shape = log(rWhite / rMid) / log(1.0 / midFraction)
        let rate = pow(rWhite, 1.0 / shape)
        let bounded = min(max(value, fixtureBaseToe), fixtureCeiling - 1e-9)
        let normalized = pow(log(amplitude / (yCeil - log10(bounded))), 1.0 / shape) / rate
        return base * pow(10.0, -normalized * fixtureDmax)
    }

    private func patchMean(_ pixels: [Float], row: Int, column: Int) -> SIMD3<Double> {
        let width = columns * patchSize
        let inset = patchSize / 4
        var sum = SIMD3<Double>(repeating: 0)
        var count = 0.0
        for localY in inset..<(patchSize - inset) {
            let y = row * patchSize + localY
            for localX in inset..<(patchSize - inset) {
                let x = column * patchSize + localX
                let offset = (y * width + x) * 4
                sum += SIMD3(
                    Double(pixels[offset]),
                    Double(pixels[offset + 1]),
                    Double(pixels[offset + 2])
                )
                count += 1
            }
        }
        return sum / count
    }

    private func render(_ image: CIImage) -> [Float] {
        let width = columns * patchSize
        let height = rows * patchSize
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

    private func patchID(row: Int, column: Int) -> String {
        String(UnicodeScalar(65 + row)!) + String(column + 1)
    }
}
