import CoreGraphics
import CoreImage
import Foundation
import XCTest
import simd
@testable import Chromabase

/// 채도·색 깊이·톤 슬라이더가 [0,1] 경계 근처에서 색을 다루는 방식에 대한 합성 계약.
///
/// 입력은 채널 값 6단계의 모든 조합(216색)이다. 한 채널이 0 이거나 0.95 인 원색·2차색까지
/// 들어 있어서, 채널 하나가 먼저 경계에 닿는 경우를 빠짐없이 지나간다. 실사진은 쓰지 않는다.
/// 렌더는 float(RGBAf)로 해서 범위 밖 값을 그대로 읽는다.
final class ColorModelGamutBehaviorTests: XCTestCase {
    private typealias RGB = SIMD3<Double>

    private static let levels: [Double] = [0, 0.05, 0.15, 0.4, 0.7, 0.95]
    private static let lumaWeights = RGB(0.2126, 0.7152, 0.0722)
    private static let tolerance = 2e-5

    private static var grid: [RGB] {
        var pixels: [RGB] = []
        for r in levels { for g in levels { for b in levels { pixels.append(RGB(r, g, b)) } } }
        return pixels
    }

    // MARK: 채도·색 깊이

    /// 키우는 슬라이더가 [0,1] 안의 색을 범위 밖으로 밀지 않고, 휘도는 그대로다.
    func testBoundedChromaScaleNeverLeavesTheRangeAndKeepsLuma() {
        let inputs = Self.grid
        for (name, edit) in Self.boostingEdits {
            var params = DevelopParameters()
            edit(&params)
            let outputs = Self.render(inputs) { ColorModel.apply(to: $0, params: params) }
            for (input, output) in zip(inputs, outputs) {
                XCTAssertTrue(Self.isInRange(output), "\(name): \(input) → \(output) 가 범위 밖")
                XCTAssertEqual(Self.luma(output), Self.luma(input), accuracy: Self.tolerance,
                               "\(name): \(input) 의 휘도가 바뀜")
            }
        }
    }

    /// 접히기 시작하는 배율(knee) 안쪽에서는 이전 선형 법칙과 같다 — 기존 편집이 흔들리지 않는다.
    func testChromaScaleIsLinearInsideTheKnee() {
        let inputs = Self.grid
        for amount in [0.1, 0.3, 1.0] {
            var params = DevelopParameters()
            params.saturation = amount
            let factor = 1.0 + amount * 0.6
            let outputs = Self.render(inputs) { ColorModel.apply(to: $0, params: params) }
            var checked = 0
            for (input, output) in zip(inputs, outputs) {
                let limit = max(Self.headroom(input), 1)
                let knee = 1 + Double(BoundedChromaScale.kneeFraction) * (limit - 1)
                guard factor <= knee else { continue }
                let y = Self.luma(input)
                let expected = RGB(repeating: y) + (input - RGB(repeating: y)) * factor
                for channel in 0..<3 {
                    XCTAssertEqual(output[channel], expected[channel], accuracy: Self.tolerance,
                                   "채도 \(amount): \(input) 가 선형 법칙과 다름")
                }
                checked += 1
            }
            XCTAssertGreaterThan(checked, 20, "채도 \(amount): 선형 구간을 확인한 색이 너무 적다")
        }
    }

    /// 이전 구현(CIColorControls 채도)과의 호환: knee 안쪽의 결과는 선형값 2e-4 안에서 같다. 차이의
    /// 원인은 CIColorControls 의 휘도 가중치가 Rec.709 와 소수 넷째 자리에서 다른 것뿐이다.
    func testChromaScaleMatchesTheFormerCoreImageSaturationInsideTheKnee() {
        let inputs = Self.grid
        let factor = 1.0 + 0.3 * 0.6
        var params = DevelopParameters()
        params.saturation = 0.3
        let outputs = Self.render(inputs) { ColorModel.apply(to: $0, params: params) }
        let former = Self.render(inputs) {
            $0.applyingFilter("CIColorControls", parameters: [
                "inputSaturation": factor, "inputContrast": 1.0, "inputBrightness": 0.0,
            ])
        }
        var checked = 0
        for index in inputs.indices {
            let limit = max(Self.headroom(inputs[index]), 1)
            guard factor <= 1 + Double(BoundedChromaScale.kneeFraction) * (limit - 1) else { continue }
            for channel in 0..<3 {
                XCTAssertEqual(outputs[index][channel], former[index][channel], accuracy: 2e-4,
                               "\(inputs[index]) 가 이전 결과와 다름")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 20)
    }

    /// 줄이는 쪽은 경계 안에서 안전하므로 이전과 같은 선형 법칙이다.
    func testDesaturationFollowsTheLinearLaw() {
        let inputs = Self.grid
        for amount in [-0.5, -1.0] {
            var params = DevelopParameters()
            params.saturation = amount
            let factor = 1.0 + amount * 0.6
            let outputs = Self.render(inputs) { ColorModel.apply(to: $0, params: params) }
            for (input, output) in zip(inputs, outputs) {
                let y = Self.luma(input)
                let expected = RGB(repeating: y) + (input - RGB(repeating: y)) * factor
                for channel in 0..<3 {
                    XCTAssertEqual(output[channel], expected[channel], accuracy: Self.tolerance,
                                   "채도 \(amount): \(input)")
                }
            }
        }
    }

    /// 슬라이더를 올릴수록 chroma 는 줄지 않는다. 접힌 뒤에도 평평해질 뿐 뒤집히지 않는다.
    func testChromaGrowsMonotonicallyWithTheSlider() {
        let inputs = Self.grid
        let amounts = stride(from: 0.0, through: 1.0, by: 0.1).map { $0 }
        let renders = amounts.map { amount -> [RGB] in
            var params = DevelopParameters()
            params.saturation = amount
            return Self.render(inputs) { ColorModel.apply(to: $0, params: params) }
        }
        for index in inputs.indices {
            var previous = Self.chromaNorm(renders[0][index])
            for step in 1..<amounts.count {
                let current = Self.chromaNorm(renders[step][index])
                XCTAssertGreaterThanOrEqual(current, previous - Self.tolerance,
                                            "\(inputs[index]) 의 chroma 가 \(amounts[step]) 에서 줄었다")
                previous = current
            }
            let input = inputs[index]
            if Self.headroom(input) > 1.5, Self.chromaNorm(input) > 0.02 {
                XCTAssertGreaterThan(previous, Self.chromaNorm(input) + 1e-3,
                                     "\(input): 여유가 있는데 +1 에서도 커지지 않았다")
            }
        }
    }

    /// 이미 범위 밖인 화소는 더 키우지 않는다(키우면 뒤에서 채널별로 잘린다).
    func testPixelsAlreadyOutsideTheRangeAreNotAmplified() {
        let inputs: [RGB] = [RGB(1.2, 0.3, 0.1), RGB(-0.1, 0.5, 0.4), RGB(1.5, 1.4, 0.2)]
        var params = DevelopParameters()
        params.saturation = 1
        let outputs = Self.render(inputs) { ColorModel.apply(to: $0, params: params) }
        for (input, output) in zip(inputs, outputs) {
            XCTAssertEqual(Self.chromaNorm(output), Self.chromaNorm(input), accuracy: 1e-4,
                           "\(input) 의 chroma 가 더 커졌다")
            XCTAssertEqual(Self.luma(output), Self.luma(input), accuracy: 1e-4)
        }
    }

    /// 알파가 있는 화소도 색만 접히고 알파는 그대로다(곱해진 알파를 풀어서 계산한다).
    func testAlphaIsPreservedAndColorIsComputedUnpremultiplied() {
        let opaque = RGB(0.8, 0.25, 0.05)
        let alpha = 0.5
        var params = DevelopParameters()
        params.saturation = 1
        let reference = Self.render([opaque]) { ColorModel.apply(to: $0, params: params) }[0]
        let premultiplied = Self.renderRGBA(
            [SIMD4<Double>(opaque.x * alpha, opaque.y * alpha, opaque.z * alpha, alpha)]
        ) { ColorModel.apply(to: $0, params: params) }[0]
        XCTAssertEqual(premultiplied.w, alpha, accuracy: Self.tolerance)
        for channel in 0..<3 {
            XCTAssertEqual(premultiplied[channel] / alpha, reference[channel], accuracy: 1e-4)
        }
    }

    // MARK: 톤 — 밝히는 쪽

    /// 밝혀서 한 채널이 1 을 넘을 화소도 목표 휘도에 도달하고 범위 안에 있다. 목표 휘도는
    /// 같은 휘도의 무채색이 정한다(무채색은 잘리지 않는다).
    func testBrightenedPixelsReachTheTargetLumaInsideTheRange() {
        let inputs = Self.grid
        for (name, edit) in Self.brighteningToneEdits {
            var params = DevelopParameters()
            edit(&params)
            let outputs = Self.render(inputs) { ToneMapper.applyToneCurves(to: $0, params: params) }
            let grays = inputs.map { RGB(repeating: Self.luma($0)) }
            let targets = Self.render(grays) { ToneMapper.applyToneCurves(to: $0, params: params) }
            for index in inputs.indices {
                let output = outputs[index]
                XCTAssertTrue(Self.isInRange(output), "\(name): \(inputs[index]) → \(output) 가 범위 밖")
                XCTAssertEqual(Self.luma(output), Self.luma(targets[index]), accuracy: 1e-4,
                               "\(name): \(inputs[index]) 가 목표 휘도에 못 미침")
            }
        }
    }

    /// 접힌 화소의 chroma 는 입력과 같은 방향이다(선형광 색조 보존) — 줄어들 뿐 돌지 않는다.
    func testBrightenedPixelsKeepTheirLinearHue() {
        let inputs = Self.grid
        for (name, edit) in Self.brighteningToneEdits {
            var params = DevelopParameters()
            edit(&params)
            let outputs = Self.render(inputs) { ToneMapper.applyToneCurves(to: $0, params: params) }
            for (input, output) in zip(inputs, outputs) {
                let before = input - RGB(repeating: Self.luma(input))
                let after = output - RGB(repeating: Self.luma(output))
                let beforeNorm = simd_length(before)
                guard beforeNorm > 0.05, Self.luma(output) >= Self.luma(input) else { continue }
                let scale = simd_dot(after, before) / (beforeNorm * beforeNorm)
                XCTAssertGreaterThanOrEqual(scale, -1e-4, "\(name): \(input) 의 chroma 가 뒤집힘")
                XCTAssertLessThanOrEqual(scale, 1 + 1e-3, "\(name): \(input) 의 chroma 가 커짐")
                let residual = simd_length(after - before * scale)
                XCTAssertLessThan(residual, 2e-4, "\(name): \(input) 의 chroma 방향이 돌아감")
            }
        }
    }

    /// 더해도 범위 안에 머무는 화소는 이전처럼 같은 값을 더한 결과다(끝점 앵커·옅은 리프트 질감).
    func testLiftThatStaysInsideTheRangeIsAdditive() {
        let input = RGB(0.55, 0.50, 0.40)
        var params = DevelopParameters()
        params.whites = 0.5
        let output = Self.render([input]) { ToneMapper.applyToneCurves(to: $0, params: params) }[0]
        let gray = Self.render([RGB(repeating: Self.luma(input))]) {
            ToneMapper.applyToneCurves(to: $0, params: params)
        }[0]
        let delta = Self.luma(gray) - Self.luma(input)
        XCTAssertGreaterThan(delta, 0.01, "시험 화소가 화이트 마스크에 들어가지 않았다")
        for channel in 0..<3 {
            XCTAssertEqual(output[channel], input[channel] + delta, accuracy: 1e-4)
        }
    }

    // MARK: 톤 — 어둡히는 쪽

    /// 어둡힐 때는 채널 비율을 보존한다(이전과 같다).
    func testDarkeningKeepsChannelRatios() {
        let inputs = Self.grid.filter { Self.luma($0) > 0.1 }
        var params = DevelopParameters()
        params.contrast = -1
        let outputs = Self.render(inputs) { ToneMapper.applyToneCurves(to: $0, params: params) }
        var darkened = 0
        for (input, output) in zip(inputs, outputs) {
            let ratio = Self.luma(output) / Self.luma(input)
            guard ratio < 0.98 else { continue }
            darkened += 1
            for channel in 0..<3 {
                XCTAssertEqual(output[channel], input[channel] * ratio, accuracy: 1e-4)
            }
        }
        XCTAssertGreaterThan(darkened, 10)
    }

    // MARK: 픽스처

    private static var boostingEdits: [(String, (inout DevelopParameters) -> Void)] {
        [
            ("채도 +0.3", { $0.saturation = 0.3 }),
            ("채도 +1", { $0.saturation = 1 }),
            ("색 깊이 +1", { $0.colorDepth = 1 }),
            ("채도+색 깊이 +1", { $0.saturation = 1; $0.colorDepth = 1 }),
        ]
    }

    private static var brighteningToneEdits: [(String, (inout DevelopParameters) -> Void)] {
        [
            ("하이라이트 +1", { $0.highlight = 1 }),
            ("화이트 +1", { $0.whites = 1 }),
            ("화이트 +2", { $0.whites = 2 }),
            ("하이라이트+화이트 +1", { $0.highlight = 1; $0.whites = 1 }),
            ("대비 +1", { $0.contrast = 1 }),
            ("섀도 +1", { $0.shadow = 1 }),
        ]
    }

    private static func luma(_ rgb: RGB) -> Double { simd_dot(rgb, lumaWeights) }

    private static func chromaNorm(_ rgb: RGB) -> Double {
        simd_length(rgb - RGB(repeating: luma(rgb)))
    }

    private static func isInRange(_ rgb: RGB) -> Bool {
        (0..<3).allSatisfy { rgb[$0] >= -tolerance && rgb[$0] <= 1 + tolerance }
    }

    /// 휘도를 고정한 채 chroma 를 몇 배까지 키울 수 있는지 — 커널 `chromaScaleHeadroom` 과 같은
    /// 정의를 따로 적은 것이다(커널을 호출하지 않고 기대값을 만든다).
    private static func headroom(_ rgb: RGB) -> Double {
        let y = luma(rgb)
        guard y > 0, y < 1 else { return 0 }
        var limit = 1e9
        for channel in 0..<3 {
            let chroma = rgb[channel] - y
            if chroma > 1e-5 { limit = min(limit, (1 - y) / chroma) }
            else if chroma < -1e-5 { limit = min(limit, -y / chroma) }
        }
        return limit
    }

    private static func render(_ pixels: [RGB], _ transform: (CIImage) -> CIImage) -> [RGB] {
        renderRGBA(pixels.map { SIMD4($0.x, $0.y, $0.z, 1) }, transform).map { RGB($0.x, $0.y, $0.z) }
    }

    private static func renderRGBA(_ pixels: [SIMD4<Double>], _ transform: (CIImage) -> CIImage) -> [SIMD4<Double>] {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var data = [Float]()
        for pixel in pixels { data += [Float(pixel.x), Float(pixel.y), Float(pixel.z), Float(pixel.w)] }
        let image = CIImage(
            bitmapData: data.withUnsafeBufferPointer { Data(buffer: $0) },
            bytesPerRow: pixels.count * 16,
            size: CGSize(width: pixels.count, height: 1),
            format: .RGBAf,
            colorSpace: linear
        )
        let context = CIContext(options: [.workingColorSpace: linear, .workingFormat: CIFormat.RGBAf])
        var out = [Float](repeating: 0, count: pixels.count * 4)
        out.withUnsafeMutableBytes {
            context.render(transform(image), toBitmap: $0.baseAddress!, rowBytes: pixels.count * 16,
                           bounds: CGRect(x: 0, y: 0, width: pixels.count, height: 1),
                           format: .RGBAf, colorSpace: linear)
        }
        return (0..<pixels.count).map {
            SIMD4(Double(out[$0 * 4]), Double(out[$0 * 4 + 1]), Double(out[$0 * 4 + 2]), Double(out[$0 * 4 + 3]))
        }
    }
}
