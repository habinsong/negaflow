import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

/// 자동 밸런스 OFF 의 고정 반전이 채널 밀도 범위비(ρ) ≠ 1 인 필름에서 회색을 기울이는지와, 롤 교정
/// (`channelRange`)이 그것을 지우는지를 합성 네거티브로 확인한다. 기존 합성 픽스처는 세 채널이 같은
/// 밀도 응답(ρ = 1)을 써서 이 오차를 만들 수 없었다. 실제 필름·스캐너 정확도를 주장하는 시험이 아니다.
final class ChannelRangeCalibrationTests: XCTestCase {
    private let baseRGB = SIMD3<Double>(0.84, 0.55, 0.34)
    private let columns = 24
    private let patchSize = 10
    private let rows = 8
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    /// 채널 밀도 배율: B/R = ρ (G 는 ρ^(1/6) 로 둬 세 채널이 모두 다르다).
    private func filmScale(_ ratio: Double) -> SIMD3<Double> {
        SIMD3(pow(ratio, -1.0 / 3), pow(ratio, 1.0 / 6), pow(ratio, 2.0 / 3))
    }

    private func grayLevel(_ column: Int) -> Double { 0.04 + 0.86 * Double(column) / Double(columns - 1) }

    /// 회색 계단(밝기 0.04…0.90)을 필름 앞면 직선 응답으로 찍은 네거티브.
    private func grayNegative(ratio: Double, stray: SIMD3<Double> = .zero) -> CIImage {
        let scale = filmScale(ratio)
        let width = columns * patchSize, height = rows * patchSize
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for column in 0..<columns {
            let level = grayLevel(column)
            var transmission = SIMD3<Double>(repeating: 0)
            for channel in 0..<3 {
                let density = (0.60 + 0.62 * log10(level / 0.18)) * scale[channel]
                // 가산 미광은 필름을 통과한 빛에 더해진다(홀더 반사·플레어).
                transmission[channel] = baseRGB[channel] * pow(10, -max(density, 0)) + stray[channel]
            }
            for y in 0..<height {
                for x in (column * patchSize)..<((column + 1) * patchSize) {
                    let offset = (y * width + x) * 4
                    pixels[offset] = Float(transmission.x)
                    pixels[offset + 1] = Float(transmission.y)
                    pixels[offset + 2] = Float(transmission.z)
                }
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf, colorSpace: linear)
    }

    private func develop(_ negative: CIImage, autoBalance: Bool, channelRange: SIMD3<Double>?) -> [Float] {
        var params = DevelopParameters()
        params.filmType = .colorNegative
        params.developTarget = .main
        params.baseEstimationMode = .manual
        params.manualBaseRGB = baseRGB
        params.autoBalance = autoBalance
        params.channelRange = channelRange
        let output = ChromabaseEngine().developScanner(
            image: negative, base: FilmBase(rgb: baseRGB, source: .manual), params: params)
        let width = columns * patchSize, height = rows * patchSize
        let context = CIContext(options: [
            .workingColorSpace: linear, .outputColorSpace: linear, .workingFormat: CIFormat.RGBAf,
        ])
        var pixels = [Float](repeating: 0, count: width * height * 4)
        context.render(output, toBitmap: &pixels, rowBytes: width * 4 * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBAf, colorSpace: linear)
        return pixels
    }

    private func patch(_ pixels: [Float], column: Int) -> SIMD3<Double> {
        let width = columns * patchSize
        let inset = patchSize / 4
        var sum = SIMD3<Double>(repeating: 0)
        var count = 0.0
        for y in (rows * patchSize / 2 - 5)..<(rows * patchSize / 2 + 5) {
            for x in (column * patchSize + inset)..<((column + 1) * patchSize - inset) {
                let offset = (y * width + x) * 4
                sum += SIMD3(Double(pixels[offset]), Double(pixels[offset + 1]), Double(pixels[offset + 2]))
                count += 1
            }
        }
        return sum / count
    }

    /// 중간톤 회색 패치들의 ln(B/R) 절댓값 평균. 0 이면 중립이다.
    private func neutralCast(_ pixels: [Float]) -> Double {
        let mid = (4...16).map { patch(pixels, column: $0) }
        return mid.map { abs(log($0.z / $0.x)) }.reduce(0, +) / Double(mid.count)
    }

    func testFixedRangeLeansBlueWhenChannelRangeRatioExceedsOneAndCalibrationRemovesIt() throws {
        for ratio in [1.0, 1.23, 1.5, 1.86] {
            let negative = grayNegative(ratio: ratio)
            let plain = neutralCast(develop(negative, autoBalance: false, channelRange: nil))
            let shape = try XCTUnwrap(
                ChannelRangeCalibration.measure(in: negative, base: FilmBase(rgb: baseRGB, source: .manual)),
                "ρ=\(ratio): 회색 계단에서 채널 범위 모양을 못 쟀다")
            // 측정이 심은 비율을 되찾는다(두 채널 비의 ln 오차 3% 이내).
            XCTAssertEqual(log(shape.z / shape.x), log(ratio), accuracy: 0.03, "ρ=\(ratio) 측정 오차")
            let calibrated = neutralCast(develop(negative, autoBalance: false, channelRange: shape))
            if ratio == 1.0 {
                XCTAssertLessThan(plain, 0.01, "ρ=1 에서는 고정 범위가 이미 중립이어야 한다")
            } else {
                XCTAssertGreaterThan(plain, 0.5 * log(ratio),
                    "ρ=\(ratio): 교정 없는 OFF 가 기울지 않으면 이 시험이 아무것도 못 잡는다")
            }
            XCTAssertLessThan(calibrated, 0.03, "ρ=\(ratio): 교정 뒤 회색 캐스트 ln(B/R)=\(calibrated)")
            XCTAssertLessThan(calibrated, max(plain, 0.01), "ρ=\(ratio): 교정이 캐스트를 키웠다")
        }
    }

    func testChannelRangeIsIgnoredWhenAutoBalanceMeasuresTheScene() {
        let negative = grayNegative(ratio: 1.5)
        let wrong = SIMD3<Double>(1.4, 1.0, 0.7)
        let withRange = develop(negative, autoBalance: true, channelRange: wrong)
        let without = develop(negative, autoBalance: true, channelRange: nil)
        XCTAssertEqual(withRange, without, "ON 은 장면 측정이 범위를 정하므로 교정값이 화소를 바꾸면 안 된다")
    }

    func testMissingChannelRangeKeepsTheEqualRangeBehaviour() {
        let negative = grayNegative(ratio: 1.5)
        XCTAssertEqual(
            develop(negative, autoBalance: false, channelRange: nil),
            develop(negative, autoBalance: false, channelRange: SIMD3(repeating: 1)),
            "교정이 없는 것과 세 채널 같은 범위는 같은 그림이어야 한다")
    }

    func testMeasureRejectsFramesWhoseRangeIsClippedAtTheDensityLimit() {
        // 세 채널 모두 1.8D 상한을 넘는 아주 짙은 네거티브: 모양이 상한에 잘려 [1,1,1] 로 보인다.
        let scale = SIMD3<Double>(repeating: 3.0)
        let negative = grayNegativeScaled(scale)
        XCTAssertNil(ChannelRangeCalibration.measure(
            in: negative, base: FilmBase(rgb: baseRGB, source: .manual)))
    }

    private func grayNegativeScaled(_ scale: SIMD3<Double>) -> CIImage {
        let width = columns * patchSize, height = rows * patchSize
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for column in 0..<columns {
            let level = grayLevel(column)
            for y in 0..<height {
                for x in (column * patchSize)..<((column + 1) * patchSize) {
                    let offset = (y * width + x) * 4
                    for channel in 0..<3 {
                        let density = (0.60 + 0.62 * log10(level / 0.18)) * scale[channel]
                        pixels[offset + channel] = Float(baseRGB[channel] * pow(10, -max(density, 0)))
                    }
                }
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf, colorSpace: linear)
    }

    // MARK: 합치기 규칙

    func testCombineNeedsThreeFramesAndTakesTheMedianPerChannel() {
        let shape = SIMD3(0.85, 0.97, 1.21)
        XCTAssertNil(ChannelRangeCalibration.combine([shape, shape]))
        // 한 프레임(하늘 독점 장면)이 크게 벗어나도 중앙값은 움직이지 않는다.
        let outlier = SIMD3(1.3, 1.0, 0.77)
        let combined = ChannelRangeCalibration.combine([shape, shape, outlier, shape, shape])
        XCTAssertNotNil(combined)
        XCTAssertEqual(combined!.x, ChannelRangeCalibration.sanitized(shape)!.x, accuracy: 1e-9)
        XCTAssertEqual(combined!.z, ChannelRangeCalibration.sanitized(shape)!.z, accuracy: 1e-9)
        XCTAssertEqual(combined!.x * combined!.y * combined!.z, 1.0, accuracy: 1e-9)
    }

    func testCombineRefusesMixedStocksAndInvalidMeasurements() {
        // 서로 다른 두 필름이 반반 섞인 묶음은 흩어짐이 허용치를 넘는다.
        let a = SIMD3(0.80, 0.98, 1.28), b = SIMD3(1.05, 1.0, 0.95)
        XCTAssertNil(ChannelRangeCalibration.combine([a, b, a, b, a, b]))
        // 비정상(음수·NaN·범위 밖)은 표본으로 세지 않는다.
        let bad: [SIMD3<Double>] = [SIMD3(-1, 1, 1), SIMD3(.nan, 1, 1), SIMD3(0.1, 1, 9)]
        XCTAssertNil(ChannelRangeCalibration.combine(bad + [SIMD3(0.9, 1, 1.1), SIMD3(0.9, 1, 1.1)]))
    }

    func testSanitizedNormalizesToUnitGeometricMeanAndRejectsOutOfRange() throws {
        let normalized = try XCTUnwrap(ChannelRangeCalibration.sanitized(SIMD3(2, 2, 2)))
        XCTAssertEqual(normalized, SIMD3(repeating: 1), accuracy: 1e-12)
        XCTAssertNil(ChannelRangeCalibration.sanitized(SIMD3(0.2, 1, 1)))
        XCTAssertNil(ChannelRangeCalibration.sanitized(SIMD3(1, 1, 0)))
    }

    // MARK: 저장 형식

    func testChannelRangeRoundTripsAndOldPayloadsDecodeToNil() throws {
        var params = DevelopParameters()
        params.channelRange = SIMD3(0.9, 1.0, 1.0 / 0.9)
        let decoded = try JSONDecoder().decode(DevelopParameters.self, from: JSONEncoder().encode(params))
        XCTAssertEqual(decoded.channelRange, params.channelRange)

        // 없으면 키가 쓰이지 않아 옛 레시피 해시와 같다.
        let plain = try JSONEncoder().encode(DevelopParameters())
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("channelRange"))
        XCTAssertNil(try JSONDecoder().decode(DevelopParameters.self, from: plain).channelRange)

        // 허용 범위 밖 값은 읽을 때 버린다.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        json["channelRange"] = [9.0, 1.0, 0.1]
        let tampered = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONDecoder().decode(DevelopParameters.self, from: tampered).channelRange)
    }

    func testPresetApplicationKeepsChannelRange() throws {
        var overrides = DevelopParameters()
        overrides.channelRange = SIMD3(0.9, 1.0, 1.0 / 0.9)
        let preset = try XCTUnwrap(PresetRegistry.load(named: "neutral"))
        XCTAssertEqual(DevelopParameters(preset: preset, overrides: overrides).channelRange, overrides.channelRange)
    }
}

private func XCTAssertEqual(
    _ a: SIMD3<Double>, _ b: SIMD3<Double>, accuracy: Double,
    file: StaticString = #filePath, line: UInt = #line
) {
    for index in 0..<3 {
        XCTAssertEqual(a[index], b[index], accuracy: accuracy, file: file, line: line)
    }
}
