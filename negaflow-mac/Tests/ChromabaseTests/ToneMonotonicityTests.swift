import CoreImage
import XCTest
@testable import Chromabase

/// 기본 톤과 파라메트릭 커브는 전역 톤 곡선이라 어떤 슬라이더 조합에서도 단조여야 한다(톤 역전 = 솔라리제이션).
/// 2026-11-08 사용자 카탈로그 실측에서 두 곡선 모두 마스크 × 고정 덧셈 구조 때문에 ±1 에서 뒤집혔다.
final class ToneMonotonicityTests: XCTestCase {
    private struct LCG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func uniform(_ range: ClosedRange<Double>) -> Double {
            range.lowerBound + next() * (range.upperBound - range.lowerBound)
        }
    }

    private let grid: [Double] = (0...2048).map { (step: Int) -> Double in Double(step) / 2048 }

    private func assertMonotone(_ f: (Double) -> Double, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        var previous = -Double.infinity
        for g in grid {
            let v = f(g)
            XCTAssertGreaterThanOrEqual(v, previous - 1e-12, "\(label) 가 g=\(g) 에서 뒤집힌다", file: file, line: line)
            previous = max(previous, v)
        }
    }

    // MARK: 파라메트릭 커브

    func testParametricCurveIsMonotoneForEverySliderCombinationAndScene() {
        var rng = LCG(state: 7)
        // 장면: 무작위 백분위 + 극단(전부 같은 값, 거의 검정, 거의 흰색, 측정 실패).
        var scenes: [[Double]?] = [nil, [0.5, 0.5, 0.5, 0.5], [0, 0, 0.0001, 0.0002], [0.97, 0.98, 0.99, 1]]
        for _ in 0..<40 {
            var p: [Double] = []
            for _ in 0..<4 { p.append(pow(rng.next(), 2.2)) }
            p.sort()
            scenes.append(p)
        }
        for scene in scenes {
            for _ in 0..<30 {
                var a: [Double] = []
                for _ in 0..<4 { a.append(rng.uniform(-1...1)) }
                let curve = ParametricToneCurve(percentiles: scene, highlights: a[0], lights: a[1], darks: a[2], shadows: a[3])
                assertMonotone(curve.value, "커브 \(a) 장면 \(String(describing: scene))")
                XCTAssertEqual(curve.value(0), 0, accuracy: 1e-12, "검정은 고정")
                XCTAssertEqual(curve.value(1), 1, accuracy: 1e-12, "흰색은 고정")
            }
        }
    }

    /// 매듭은 양 끝·서로 0.10 이상 떨어지므로 어떤 장면에서도 ±1 이 자기 매듭을 0.045 이상 움직인다.
    func testEverySliderMovesItsKnotByAtLeastTheFloor() {
        let scenes: [[Double]?] = [nil, [0.5, 0.5, 0.5, 0.5], [0, 0, 0, 0], [1, 1, 1, 1], [0.1, 0.35, 0.65, 0.9]]
        for scene in scenes {
            for (k, name) in ["shadows", "darks", "lights", "highlights"].enumerated() {
                for sign in [-1.0, 1.0] {
                    var a = [0.0, 0.0, 0.0, 0.0]
                    a[k] = sign
                    let curve = ParametricToneCurve(percentiles: scene, highlights: a[3], lights: a[2], darks: a[1], shadows: a[0])
                    let moved = (curve.y[k + 1] - curve.x[k + 1]) * sign
                    XCTAssertGreaterThanOrEqual(moved, 0.045 - 1e-9, "\(name) \(sign) 장면 \(String(describing: scene))")
                }
            }
        }
    }

    func testParametricKernelMatchesTheCPUModel() throws {
        let image = ramp()
        var params = DevelopParameters()
        params.curveHighlights = -0.8; params.curveLights = 0.6; params.curveDarks = -0.7; params.curveShadows = 1
        let percentiles = try XCTUnwrap(ToneMapper.sampleLumaPercentiles(from: image))
        let curve = ParametricToneCurve(percentiles: percentiles, highlights: params.curveHighlights,
                                        lights: params.curveLights, darks: params.curveDarks, shadows: params.curveShadows)
        let output = render(ToneMapper.applyToneCurves(to: image, params: params))
        for (i, v) in rampValues.enumerated() {
            let expected = AutoAdjust.srgbDecode(min(max(curve.value(AutoAdjust.srgbEncode(v)), 0), 1))
            XCTAssertEqual(output[i], expected, accuracy: 2e-4, "램프 \(i)")
        }
    }

    // MARK: 기본 톤

    func testBasicToneIsMonotoneForEverySliderCombination() {
        var rng = LCG(state: 11)
        let singles: [(String, (Double) -> Double)] = [
            ("암부 −1", { BasicToneModel.apply($0, shadow: -1) }), ("암부 +1", { BasicToneModel.apply($0, shadow: 1) }),
            ("흰색 −2", { BasicToneModel.apply($0, whites: -2) }), ("흰색 +2", { BasicToneModel.apply($0, whites: 2) }),
            ("검정 −2", { BasicToneModel.apply($0, blacks: -2) }), ("검정 −0.4", { BasicToneModel.apply($0, blacks: -0.4) }),
            ("검정 +2", { BasicToneModel.apply($0, blacks: 2) }),
            ("농도 −1 + 명부 −1", { BasicToneModel.apply($0, density: -1, highlight: -1) }),
            ("대비 +1 + 흰색 −1", { BasicToneModel.apply($0, contrast: 1, whites: -1) }),
        ]
        for (label, f) in singles { assertMonotone(f, label) }
        for _ in 0..<300 {
            let c = rng.uniform(-1...1), d = rng.uniform(-1...1), h = rng.uniform(-1...1)
            let s = rng.uniform(-1...1), w = rng.uniform(-2...2), b = rng.uniform(-2...2)
            assertMonotone({ BasicToneModel.apply($0, contrast: c, density: d, highlight: h, shadow: s, whites: w, blacks: b) },
                           "c\(c) d\(d) h\(h) s\(s) w\(w) b\(b)")
        }
    }

    func testBasicToneKernelMatchesTheCPUModel() {
        let image = ramp()
        let combos: [(Double, Double, Double, Double, Double, Double)] = [
            (0.55, -0.4, -1, 0.8, -1, -1), (-1, 1, 1, -1, 2, 2), (0.3, -1, -1, 1, -2, -2), (0, 0, 0, -1, 0, -0.4),
        ]
        for (c, d, h, s, w, b) in combos {
            var params = DevelopParameters()
            params.contrast = c; params.density = d; params.highlight = h
            params.shadow = s; params.whites = w; params.blacks = b
            let output = render(ToneMapper.applyToneCurves(to: image, params: params))
            for (i, v) in rampValues.enumerated() {
                let expected = AutoAdjust.srgbDecode(BasicToneModel.apply(
                    AutoAdjust.srgbEncode(v), contrast: c, density: d, highlight: h, shadow: s, whites: w, blacks: b))
                XCTAssertEqual(output[i], expected, accuracy: 2e-4, "조합 \((c, d, h, s, w, b)) 램프 \(i)")
            }
        }
    }

    // MARK: 도우미

    /// 인코딩 0~1 을 고르게 덮는 회색 램프(선형 값).
    private var rampValues: [Double] { (0..<256).map { (code: Int) -> Double in AutoAdjust.srgbDecode(Double(code) / 255) } }

    private func ramp() -> CIImage {
        let values = rampValues
        return SyntheticScan.makeImage(width: values.count, height: 16) { x, _ in SIMD3(repeating: values[x]) }
    }

    /// 램프 가운데 행의 선형 휘도.
    private func render(_ image: CIImage) -> [Double] {
        let width = rampValues.count
        var px = [Float](repeating: 0, count: width * 4)
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        ChromabaseEngine.sharedLinearRenderContext.render(
            image, toBitmap: &px, rowBytes: width * 16, bounds: CGRect(x: 0, y: 8, width: width, height: 1),
            format: .RGBAf, colorSpace: linear)
        var luma = [Double](repeating: 0, count: width)
        for x in 0..<width {
            let r = Double(px[x * 4]), g = Double(px[x * 4 + 1]), b = Double(px[x * 4 + 2])
            luma[x] = 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        return luma
    }
}
