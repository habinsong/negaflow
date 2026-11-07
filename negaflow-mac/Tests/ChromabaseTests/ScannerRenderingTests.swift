import CoreImage
import XCTest
@testable import Chromabase

/// 스캐너 렌더링(+Rendering.swift / +Targets.swift)의 계약.
final class ScannerRenderingTests: XCTestCase {
    private let targets: [DevelopTarget] = [.sp3000, .noritsu, .f135, .hr]

    // MARK: 기준 구현 일치

    /// 적합 스크립트의 기준 구현(파이썬, double)이 낸 값. Windows 판도 같은 표를 대조한다 —
    /// 두 플랫폼의 렌더링이 같은 식·같은 표라는 것을 이 값이 고정한다.
    private let goldenInputs: [SIMD3<Double>] =
        [
            SIMD3(0.0, 0.0, 0.0),
            SIMD3(1e-06, 1e-06, 1e-06),
            SIMD3(0.0005, 0.0005, 0.0005),
            SIMD3(0.01, 0.01, 0.01),
            SIMD3(0.05, 0.05, 0.05),
            SIMD3(0.18, 0.18, 0.18),
            SIMD3(0.4, 0.4, 0.4),
            SIMD3(0.7, 0.7, 0.7),
            SIMD3(1.0, 1.0, 1.0),
            SIMD3(2.0, 2.0, 2.0),
            SIMD3(0.18, 0.09, 0.05),
            SIMD3(0.05, 0.12, 0.3),
            SIMD3(0.3, 0.2, 0.1),
            SIMD3(0.6, 0.1, 0.05),
            SIMD3(0.05, 0.5, 0.1),
            SIMD3(0.02, 0.05, 0.6),
            SIMD3(0.9, 0.85, 0.2),
            SIMD3(1.5, 0.2, 0.1),
            SIMD3(-0.05, 0.2, 0.3),
            SIMD3(0.2, 0.2, -0.01),
        ]

    private let goldenOutputs: [(DevelopTarget, [SIMD3<Double>], [SIMD3<Double>])] = [
            (.sp3000, [
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.003077398, 0.003077398, 0.003077398),
                SIMD3(0.009874576, 0.009874576, 0.009874576),
                SIMD3(0.038835673, 0.038835673, 0.038835673),
                SIMD3(0.18484298, 0.18484298, 0.18484298),
                SIMD3(0.527002073, 0.527002073, 0.527002073),
                SIMD3(0.88962959, 0.88962959, 0.88962959),
                SIMD3(0.948009224, 0.948009224, 0.948009224),
                SIMD3(1.0, 1.0, 1.0),
                SIMD3(0.167872384, 0.079947559, 0.042618936),
                SIMD3(0.042558472, 0.109996501, 0.297167332),
                SIMD3(0.345269853, 0.215223019, 0.095935079),
                SIMD3(0.707538922, 0.088863754, 0.039825418),
                SIMD3(0.036818102, 0.668358195, 0.088113503),
                SIMD3(0.015744717, 0.04082582, 0.540912902),
                SIMD3(1.0, 0.949530839, 0.41669206),
                SIMD3(1.0, 0.519818167, 0.497384586),
                SIMD3(2.736e-06, 0.199118249, 0.314897082),
                SIMD3(0.207233137, 0.207233137, 2.442e-06),
            ], [
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.003077398, 0.003077398, 0.003077398),
                SIMD3(0.009874576, 0.009874576, 0.009874576),
                SIMD3(0.038835673, 0.038835673, 0.038835673),
                SIMD3(0.18484298, 0.18484298, 0.18484298),
                SIMD3(0.527002073, 0.527002073, 0.527002073),
                SIMD3(0.88962959, 0.88962959, 0.88962959),
                SIMD3(0.948009224, 0.948009224, 0.948009224),
                SIMD3(1.0, 1.0, 1.0),
                SIMD3(0.09594525, 0.09594525, 0.09594525),
                SIMD3(0.10917291, 0.10917291, 0.10917291),
                SIMD3(0.234258387, 0.234258387, 0.234258387),
                SIMD3(0.216853527, 0.216853527, 0.216853527),
                SIMD3(0.492199105, 0.492199105, 0.492199105),
                SIMD3(0.071599864, 0.071599864, 0.071599864),
                SIMD3(0.921789623, 0.921789623, 0.921789623),
                SIMD3(0.62028512, 0.62028512, 0.62028512),
                SIMD3(0.151826065, 0.151826065, 0.151826065),
                SIMD3(0.191288477, 0.191288477, 0.191288477),
            ]),
            (.noritsu, [
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.003441977, 0.003282575, 0.003348449),
                SIMD3(0.010066629, 0.009600432, 0.009793092),
                SIMD3(0.033811913, 0.034628369, 0.03406877),
                SIMD3(0.136824079, 0.146747329, 0.142889845),
                SIMD3(0.441281422, 0.486056674, 0.471569752),
                SIMD3(0.837352542, 0.942752985, 0.912036812),
                SIMD3(0.872718562, 0.983743762, 0.951553836),
                SIMD3(1.0, 1.0, 1.0),
                SIMD3(0.1241933, 0.068193066, 0.03827506),
                SIMD3(0.036979125, 0.090172461, 0.210773412),
                SIMD3(0.246657457, 0.175533638, 0.083930386),
                SIMD3(0.495497603, 0.08605125, 0.041350238),
                SIMD3(0.041273376, 0.580296467, 0.094816761),
                SIMD3(0.01661838, 0.040153677, 0.380541719),
                SIMD3(0.958946444, 1.0, 0.308551287),
                SIMD3(1.0, 0.504135407, 0.469454865),
                SIMD3(7.803e-06, 0.157324181, 0.229307338),
                SIMD3(0.153223092, 0.164490917, 7.423e-06),
            ], [
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.00332122, 0.00332122, 0.00332122),
                SIMD3(0.009713455, 0.009713455, 0.009713455),
                SIMD3(0.034414387, 0.034414387, 0.034414387),
                SIMD3(0.144359136, 0.144359136, 0.144359136),
                SIMD3(0.4754915, 0.4754915, 0.4754915),
                SIMD3(0.918127143, 0.918127143, 0.918127143),
                SIMD3(0.957815692, 0.957815692, 0.957815692),
                SIMD3(1.0, 1.0, 1.0),
                SIMD3(0.077938636, 0.077938636, 0.077938636),
                SIMD3(0.087570947, 0.087570947, 0.087570947),
                SIMD3(0.184040807, 0.184040807, 0.184040807),
                SIMD3(0.169872131, 0.169872131, 0.169872131),
                SIMD3(0.430648523, 0.430648523, 0.430648523),
                SIMD3(0.05972609, 0.05972609, 0.05972609),
                SIMD3(0.941349417, 0.941349417, 0.941349417),
                SIMD3(0.607052284, 0.607052284, 0.607052284),
                SIMD3(0.118971257, 0.118971257, 0.118971257),
                SIMD3(0.149442429, 0.149442429, 0.149442429),
            ]),
            (.f135, [
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.001582971, 0.001582971, 0.001582971),
                SIMD3(0.00528569, 0.00528569, 0.00528569),
                SIMD3(0.024296108, 0.024296108, 0.024296108),
                SIMD3(0.18484298, 0.18484298, 0.18484298),
                SIMD3(0.527002073, 0.527002073, 0.527002073),
                SIMD3(0.88962959, 0.88962959, 0.88962959),
                SIMD3(0.948009224, 0.948009224, 0.948009224),
                SIMD3(1.0, 1.0, 1.0),
                SIMD3(0.143060362, 0.068131079, 0.036319735),
                SIMD3(0.037794049, 0.097682386, 0.263899432),
                SIMD3(0.349846259, 0.218075709, 0.097206658),
                SIMD3(0.715637034, 0.089880841, 0.040281239),
                SIMD3(0.036818102, 0.668358195, 0.088113503),
                SIMD3(0.012249464, 0.03176268, 0.420832781),
                SIMD3(1.0, 0.949530839, 0.41669206),
                SIMD3(1.0, 0.519818167, 0.497384586),
                SIMD3(0.000002692, 0.195932387, 0.309858777),
                SIMD3(0.208082007, 0.208082007, 0.000002452),
            ], [
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.001582971, 0.001582971, 0.001582971),
                SIMD3(0.00528569, 0.00528569, 0.00528569),
                SIMD3(0.024296108, 0.024296108, 0.024296108),
                SIMD3(0.18484298, 0.18484298, 0.18484298),
                SIMD3(0.527002073, 0.527002073, 0.527002073),
                SIMD3(0.88962959, 0.88962959, 0.88962959),
                SIMD3(0.948009224, 0.948009224, 0.948009224),
                SIMD3(1.0, 1.0, 1.0),
                SIMD3(0.081764266, 0.081764266, 0.081764266),
                SIMD3(0.096950997, 0.096950997, 0.096950997),
                SIMD3(0.237363382, 0.237363382, 0.237363382),
                SIMD3(0.219335516, 0.219335516, 0.219335516),
                SIMD3(0.492199105, 0.492199105, 0.492199105),
                SIMD3(0.055705031, 0.055705031, 0.055705031),
                SIMD3(0.921789623, 0.921789623, 0.921789623),
                SIMD3(0.62028512, 0.62028512, 0.62028512),
                SIMD3(0.147070855, 0.147070855, 0.147070855),
                SIMD3(0.191980983, 0.191980983, 0.191980983),
            ]),
            (.hr, [
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.003077398, 0.003077398, 0.003077398),
                SIMD3(0.00988133, 0.00988133, 0.00988133),
                SIMD3(0.033350736, 0.033350736, 0.033350736),
                SIMD3(0.18484298, 0.18484298, 0.18484298),
                SIMD3(0.527002073, 0.527002073, 0.527002073),
                SIMD3(0.88962959, 0.88962959, 0.88962959),
                SIMD3(0.948009224, 0.948009224, 0.948009224),
                SIMD3(1.0, 1.0, 1.0),
                SIMD3(0.134008042, 0.067723286, 0.037966259),
                SIMD3(0.040098626, 0.096055037, 0.239663171),
                SIMD3(0.34014396, 0.220202164, 0.104711758),
                SIMD3(0.677447508, 0.100453205, 0.048006155),
                SIMD3(0.046133951, 0.664090038, 0.10296165),
                SIMD3(0.015058062, 0.036179231, 0.389816905),
                SIMD3(1.0, 0.950992111, 0.40221696),
                SIMD3(1.0, 0.520210741, 0.49349582),
                SIMD3(0.000006615, 0.196512917, 0.299583092),
                SIMD3(0.208081724, 0.208081724, 0.000006082),
            ], [
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.0, 0.0, 0.0),
                SIMD3(0.003077398, 0.003077398, 0.003077398),
                SIMD3(0.00988133, 0.00988133, 0.00988133),
                SIMD3(0.033350736, 0.033350736, 0.033350736),
                SIMD3(0.18484298, 0.18484298, 0.18484298),
                SIMD3(0.527002073, 0.527002073, 0.527002073),
                SIMD3(0.88962959, 0.88962959, 0.88962959),
                SIMD3(0.948009224, 0.948009224, 0.948009224),
                SIMD3(1.0, 1.0, 1.0),
                SIMD3(0.079666968, 0.079666968, 0.079666968),
                SIMD3(0.094527211, 0.094527211, 0.094527211),
                SIMD3(0.237363382, 0.237363382, 0.237363382),
                SIMD3(0.219335516, 0.219335516, 0.219335516),
                SIMD3(0.492199105, 0.492199105, 0.492199105),
                SIMD3(0.057221511, 0.057221511, 0.057221511),
                SIMD3(0.921789623, 0.921789623, 0.921789623),
                SIMD3(0.62028512, 0.62028512, 0.62028512),
                SIMD3(0.146232898, 0.146232898, 0.146232898),
                SIMD3(0.191980983, 0.191980983, 0.191980983),
            ]),
    ]

    /// 깊은 암부가 한 값으로 뭉치지 않는다. 예전 F135·HR 토우는 −8~−6 스탑이 거의 평평해 파란
    /// 암부가 스탑당 8비트 0~1 코드밖에 움직이지 않았다. 측정된 SP 의 로그 기울기(출력 스탑 /
    /// 입력 스탑)를 기준으로 삼는다.
    func testDeepShadowsKeepSeparationLikeTheMeasuredScanner() throws {
        func outputStops(_ target: DevelopTarget, _ rgb: SIMD3<Double>, at stop: Double) throws -> Double {
            let rendering = try XCTUnwrap(ScannerTargetGrade.rendering(for: target))
            let curves = ScannerTargetGrade.RenderingCurves(rendering)
            let luma = (rgb * SIMD3(0.2126, 0.7152, 0.0722)).sum()
            let input = rgb * (0.18 * pow(2, stop) / luma)
            let out = ScannerTargetGrade.renderLinear(input, curves: curves, monochrome: false)
            return log2(max(out.z, 1e-9))
        }
        let deepBlue = SIMD3<Double>(0.06, 0.16, 1.0)
        for stop in stride(from: -9.0, through: -4.0, by: 1.0) {
            let sp = try outputStops(.sp3000, deepBlue, at: stop + 1) - outputStops(.sp3000, deepBlue, at: stop)
            for target in [DevelopTarget.f135, .hr] {
                let step = try outputStops(target, deepBlue, at: stop + 1) - outputStops(target, deepBlue, at: stop)
                XCTAssertGreaterThan(step, sp * 0.9, "\(target.displayName) \(stop) 스탑")
            }
        }
    }

    /// F135 와 HR 은 같은 렌더링이 아니다: F135 는 암부가 더 깊고, HR 은 암부를 열어 두고 채도가 낮다.
    func testF135AndHRRenderDifferently() throws {
        let f135 = ScannerTargetGrade.RenderingCurves(try XCTUnwrap(ScannerTargetGrade.rendering(for: .f135)))
        let hr = ScannerTargetGrade.RenderingCurves(try XCTUnwrap(ScannerTargetGrade.rendering(for: .hr)))
        let shadow = SIMD3<Double>(repeating: 0.18 * pow(2, -3))
        XCTAssertLessThan(
            ScannerTargetGrade.renderLinear(shadow, curves: f135, monochrome: false).y,
            ScannerTargetGrade.renderLinear(shadow, curves: hr, monochrome: false).y * 0.8
        )
        let red = SIMD3<Double>(0.6, 0.1, 0.05)
        let f135Red = ScannerTargetGrade.renderLinear(red, curves: f135, monochrome: false)
        let hrRed = ScannerTargetGrade.renderLinear(red, curves: hr, monochrome: false)
        XCTAssertGreaterThan(f135Red.x / f135Red.y, hrRed.x / hrRed.y)
    }

    /// 암부에서 중간톤으로 올라가는 동안 국부 대비(출력 스탑 / 입력 스탑)가 꺼지지 않는다 —
    /// 특성곡선 토우는 위로 갈수록 감마가 커진다. 예전 HR 은 SP 암부와 인화지 −1 스탑 앵커를 그냥
    /// 이어 −1.6 스탑에서 그때까지 최고치의 69% 로 꺼졌다가 튀었다. 실측 SP·HS 는 98% 이상이다.
    func testToeContrastDoesNotDipBelowTheMidtones() throws {
        func linear(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        for target in targets {
            let tone = ScannerTargetGrade.RenderingCurves(try XCTUnwrap(ScannerTargetGrade.rendering(for: target))).tone
            var peak = 0.0
            for step in 0..<170 {
                let x = -4.0 + Double(step) * 0.02
                let contrast = (log2(linear(tone.value(at: x + 0.02))) - log2(linear(tone.value(at: x)))) / 0.02
                peak = max(peak, contrast)
                XCTAssertGreaterThanOrEqual(contrast, peak * 0.9, "\(target.displayName) \(x) 스탑")
            }
        }
    }

    func testCPUReferenceMatchesFittingScriptGolden() throws {
        for (target, color, mono) in goldenOutputs {
            let rendering = try XCTUnwrap(ScannerTargetGrade.rendering(for: target))
            let curves = ScannerTargetGrade.RenderingCurves(rendering)
            for (index, input) in goldenInputs.enumerated() {
                let got = ScannerTargetGrade.renderLinear(input, curves: curves, monochrome: false)
                for c in 0..<3 {
                    XCTAssertEqual(got[c], color[index][c], accuracy: 1e-7,
                                   "\(target.displayName) 입력 \(input) 채널 \(c)")
                }
                let gray = (input * SIMD3(0.2126, 0.7152, 0.0722)).sum()
                let gotMono = ScannerTargetGrade.renderLinear(SIMD3(repeating: gray), curves: curves,
                                                              monochrome: true)
                for c in 0..<3 {
                    XCTAssertEqual(gotMono[c], mono[index][c], accuracy: 1e-7,
                                   "\(target.displayName) 흑백 입력 \(input) 채널 \(c)")
                }
            }
        }
    }

    func testMetalKernelMatchesCPUReference() throws {
        let width = goldenInputs.count
        var pixels = [Float](repeating: 1, count: width * 4)
        for (i, v) in goldenInputs.enumerated() {
            pixels[i * 4] = Float(v.x); pixels[i * 4 + 1] = Float(v.y); pixels[i * 4 + 2] = Float(v.z)
        }
        let linear = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        let image = CIImage(bitmapData: Data(bytes: pixels, count: pixels.count * 4),
                            bytesPerRow: width * 16,
                            size: CGSize(width: width, height: 1),
                            format: .RGBAf, colorSpace: linear)
        let context = CIContext(options: [.workingColorSpace: linear, .cacheIntermediates: false])
        for target in targets {
            let rendering = try XCTUnwrap(ScannerTargetGrade.rendering(for: target))
            let out = ScannerTargetGrade.applyRendering(to: image, rendering: rendering,
                                                        monochrome: false, strength: 1.0)
            var result = [Float](repeating: 0, count: width * 4)
            context.render(out, toBitmap: &result, rowBytes: width * 16,
                           bounds: CGRect(x: 0, y: 0, width: width, height: 1),
                           format: .RGBAf, colorSpace: linear)
            let curves = ScannerTargetGrade.RenderingCurves(rendering)
            for (i, v) in goldenInputs.enumerated() {
                let expected = ScannerTargetGrade.renderLinear(v, curves: curves, monochrome: false)
                for c in 0..<3 {
                    XCTAssertEqual(Double(result[i * 4 + c]), expected[c], accuracy: 2e-4,
                                   "\(target.displayName) GPU 입력 \(v) 채널 \(c)")
                }
            }
        }
    }

    // MARK: 곡선 형태

    /// 톤 곡선은 단조 증가하고, 기울기가 knot 에서 끊기지 않으며(이전 판의 꺾임 결함),
    /// 최상단도 순백에 닿지 않는다(화이트홀 금지). 18% 회색은 MAIN 근처에 둔다 — 노출은
    /// 반전과 자동 톤 몫이다.
    func testToneCurvesAreSmoothMonotoneAndBounded() throws {
        for target in targets {
            let r = try XCTUnwrap(ScannerTargetGrade.rendering(for: target))
            let curve = ScannerTargetGrade.RenderingCurve(xs: ScannerTargetGrade.renderingToneStops, ys: r.tone)
            var previous = curve.value(at: -10)
            var previousSlope = (curve.value(at: -9.99) - previous) / 0.01
            var maxSlopeJump = 0.0
            for i in 1...1300 {
                let y = -10 + Double(i) * 0.01
                let value = curve.value(at: y)
                XCTAssertGreaterThan(value, previous, "\(target.displayName) 톤 역전 at \(y)")
                let slope = (value - previous) / 0.01
                maxSlopeJump = max(maxSlopeJump, abs(slope - previousSlope))
                previous = value
                previousSlope = slope
            }
            XCTAssertLessThan(maxSlopeJump, 0.02, "\(target.displayName) 톤 기울기 불연속")
            XCTAssertLessThan(curve.value(at: 2.5), 0.99, "\(target.displayName) 최상단 순백")
            let midStops = log2(ScannerTargetGrade.srgbDecode(curve.value(at: 0)) / 0.18)
            XCTAssertLessThan(abs(midStops), 0.35, "\(target.displayName) 18% 회색 \(midStops) 스탑")
        }
    }

    // MARK: 화소 계약

    /// 회색은 회색으로 남는다. HS 만 같은 롤 실측 차이만큼(a* 초록 쪽, 밝을수록 크게) 기운다.
    func testNeutralInputStaysNeutralExceptMeasuredBalance() throws {
        for target in targets {
            let curves = ScannerTargetGrade.RenderingCurves(try XCTUnwrap(ScannerTargetGrade.rendering(for: target)))
            for stops in stride(from: -6.0, through: 2.0, by: 0.5) {
                let v = 0.18 * pow(2.0, stops)
                let out = ScannerTargetGrade.renderLinear(SIMD3(repeating: v), curves: curves, monochrome: false)
                let enc = SIMD3(ScannerTargetGrade.srgbEncode(out.x), ScannerTargetGrade.srgbEncode(out.y),
                                ScannerTargetGrade.srgbEncode(out.z))
                let lab = ScannerTargetGrade.srgbToLab(r: enc.x, g: enc.y, b: enc.z)
                if target == .noritsu {
                    XCTAssertLessThan(lab.a, 0.6, "HS 회색 a* \(lab.a) at \(stops)")
                    XCTAssertGreaterThan(lab.a, -5.0, "HS 회색 a* \(lab.a) at \(stops)")
                    XCTAssertLessThan(abs(lab.b), 1.5, "HS 회색 b* \(lab.b) at \(stops)")
                } else {
                    XCTAssertLessThan(hypot(lab.a, lab.b), 0.05, "\(target.displayName) 회색 캐스트 at \(stops)")
                }
            }
        }
    }

    /// 0·음수·1 초과·아주 큰 값 모두 유한하고 [0, 1] 안이다.
    func testExtremeInputsStayFiniteAndInRange() throws {
        let inputs: [SIMD3<Double>] = [
            SIMD3(0, 0, 0), SIMD3(-1, -1, -1), SIMD3(1e-9, 1, 1e-9), SIMD3(100, 100, 100),
            SIMD3(50, 0, 0), SIMD3(0, 0, 50), SIMD3(-0.3, 2, 0.5), SIMD3(1, 1, 1),
        ]
        for target in targets {
            let curves = ScannerTargetGrade.RenderingCurves(try XCTUnwrap(ScannerTargetGrade.rendering(for: target)))
            for input in inputs {
                for mono in [false, true] {
                    let out = ScannerTargetGrade.renderLinear(input, curves: curves, monochrome: mono)
                    for c in 0..<3 {
                        XCTAssertTrue(out[c].isFinite, "\(target.displayName) \(input)")
                        XCTAssertGreaterThanOrEqual(out[c], 0)
                        XCTAssertLessThanOrEqual(out[c], 1.0 + 1e-12)
                    }
                }
            }
        }
    }

    /// 밝기가 오르는 램프는 회색·원색 어느 쪽이든 출력 휘도가 역전되지 않는다(밴딩·솔라리제이션 방지).
    func testLuminanceRampsNeverReverse() throws {
        let hues: [SIMD3<Double>] = [
            SIMD3(1, 1, 1), SIMD3(1, 0.05, 0.02), SIMD3(0.05, 1, 0.05), SIMD3(0.02, 0.08, 1),
            SIMD3(1, 0.8, 0.05), SIMD3(0.1, 0.9, 1), SIMD3(0.9, 0.1, 0.9), SIMD3(0.9, 0.6, 0.45),
        ]
        for target in targets {
            let curves = ScannerTargetGrade.RenderingCurves(try XCTUnwrap(ScannerTargetGrade.rendering(for: target)))
            for hue in hues {
                var previous = -1.0
                for i in 0...400 {
                    let scale = 1e-4 * pow(2.0, Double(i) * 0.04)
                    let out = ScannerTargetGrade.renderLinear(hue * scale, curves: curves, monochrome: false)
                    let y = (out * SIMD3(0.2126, 0.7152, 0.0722)).sum()
                    XCTAssertGreaterThanOrEqual(y, previous - 1e-9,
                                                "\(target.displayName) 휘도 역전 hue \(hue) step \(i)")
                    previous = y
                }
            }
        }
    }

    /// 타깃은 장면을 읽지 않는다: 같은 화소는 주변 장면과 무관하게 같은 값이다.
    func testRenderingIsSceneIndependent() throws {
        let linear = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        func image(_ fill: Float) -> CIImage {
            var px = [Float](repeating: fill, count: 64 * 64 * 4)
            for y in 28..<36 { for x in 28..<36 {
                let i = (y * 64 + x) * 4
                px[i] = 0.22; px[i + 1] = 0.15; px[i + 2] = 0.09
            } }
            for i in stride(from: 3, to: px.count, by: 4) { px[i] = 1 }
            return CIImage(bitmapData: Data(bytes: px, count: px.count * 4), bytesPerRow: 64 * 16,
                           size: CGSize(width: 64, height: 64), format: .RGBAf, colorSpace: linear)
        }
        let context = CIContext(options: [.workingColorSpace: linear])
        for target in targets {
            var params = DevelopParameters()
            params.developTarget = target
            var centers: [[Float]] = []
            for fill in [Float(0.01), 0.7] {
                let out = ScannerTargetGrade.apply(to: image(fill), target: target, params: params)
                var px = [Float](repeating: 0, count: 4)
                context.render(out, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 32, y: 32, width: 1, height: 1),
                               format: .RGBAf, colorSpace: linear)
                centers.append(px)
            }
            // HS 는 끝에 공간 샤픈이 있어 이웃 영향을 받으므로 패치 한가운데(이웃도 같은 값)만 본다.
            for c in 0..<3 {
                XCTAssertEqual(centers[0][c], centers[1][c], accuracy: 1e-5, "\(target.displayName) 장면 의존")
            }
        }
    }

    /// 슬라이드는 같은 렌더링을 절반만 싣는다.
    func testPositiveAppliesHalfStrength() throws {
        let linear = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        let input = SIMD3<Double>(0.30, 0.20, 0.10)
        var px: [Float] = [Float(input.x), Float(input.y), Float(input.z), 1]
        let image = CIImage(bitmapData: Data(bytes: &px, count: 16), bytesPerRow: 16,
                            size: CGSize(width: 1, height: 1), format: .RGBAf, colorSpace: linear)
        let context = CIContext(options: [.workingColorSpace: linear])
        let rendering = try XCTUnwrap(ScannerTargetGrade.rendering(for: .sp3000))
        let full = ScannerTargetGrade.renderLinear(input, curves: .init(rendering), monochrome: false)
        let out = ScannerTargetGrade.applyRendering(to: image, rendering: rendering, monochrome: false,
                                                    strength: ScannerTargetGrade.renderingPositiveStrength)
        var result = [Float](repeating: 0, count: 4)
        context.render(out, toBitmap: &result, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: linear)
        for c in 0..<3 {
            XCTAssertEqual(Double(result[c]), input[c] + (full[c] - input[c]) * 0.5, accuracy: 2e-4)
        }
    }

    /// HS 샤픈 반경은 실기 출력 해상도 기준으로 늘고 준다.
    func testNoritsuSharpenSigmaScalesWithResolution() {
        let reference = ScannerTargetGrade.noritsuReferenceLongEdge
        XCTAssertEqual(ScannerTargetGrade.noritsuSharpenSigma(for: CGRect(x: 0, y: 0, width: reference, height: 2048)),
                       ScannerTargetGrade.noritsuSharpenRadius, accuracy: 1e-12)
        XCTAssertEqual(ScannerTargetGrade.noritsuSharpenSigma(for: CGRect(x: 0, y: 0, width: 1500, height: reference * 2)),
                       ScannerTargetGrade.noritsuSharpenRadius * 2, accuracy: 1e-12)
        XCTAssertEqual(ScannerTargetGrade.noritsuSharpenSigma(for: CGRect(x: 0, y: 0, width: reference / 2, height: 100)),
                       ScannerTargetGrade.noritsuSharpenRadius / 2, accuracy: 1e-12)
    }

    func testOnlyScannerTargetsHaveRendering() {
        for target in DevelopTarget.allCases {
            XCTAssertEqual(ScannerTargetGrade.rendering(for: target) != nil, target.isScannerEmulation,
                           "\(target.displayName)")
        }
    }
}
