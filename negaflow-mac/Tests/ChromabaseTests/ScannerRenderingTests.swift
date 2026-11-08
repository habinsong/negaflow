import CoreImage
import simd
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
                SIMD3(0.000000000, 0.000000000, 0.000000000),
                SIMD3(0.000000000, 0.000000000, 0.000000000),
                SIMD3(0.004128337, 0.004128337, 0.004128337),
                SIMD3(0.020259671, 0.020259671, 0.020259671),
                SIMD3(0.067278092, 0.067278092, 0.067278092),
                SIMD3(0.221615107, 0.221615107, 0.221615107),
                SIMD3(0.490740495, 0.490740495, 0.490740495),
                SIMD3(0.801720967, 0.801720967, 0.801720967),
                SIMD3(0.897270032, 0.897270032, 0.897270032),
                SIMD3(1.000000000, 1.000000000, 1.000000000),
                SIMD3(0.199688675, 0.119930677, 0.077833066),
                SIMD3(0.080097545, 0.152703461, 0.300016617),
                SIMD3(0.339945212, 0.251886263, 0.150875427),
                SIMD3(0.601786255, 0.159892776, 0.095752732),
                SIMD3(0.110141331, 0.593859747, 0.182904366),
                SIMD3(0.043106262, 0.084258222, 0.518771253),
                SIMD3(0.919589137, 0.882512472, 0.311372908),
                SIMD3(1.000000000, 0.462743308, 0.398867826),
                SIMD3(0.000164514, 0.250221456, 0.337758183),
                SIMD3(0.246031487, 0.246031487, 0.000161551),
            ], [
                SIMD3(0.000000000, 0.000000000, 0.000000000),
                SIMD3(0.000000000, 0.000000000, 0.000000000),
                SIMD3(0.004128337, 0.004128337, 0.004128337),
                SIMD3(0.020259671, 0.020259671, 0.020259671),
                SIMD3(0.067278092, 0.067278092, 0.067278092),
                SIMD3(0.221615107, 0.221615107, 0.221615107),
                SIMD3(0.490740495, 0.490740495, 0.490740495),
                SIMD3(0.801720967, 0.801720967, 0.801720967),
                SIMD3(0.897270032, 0.897270032, 0.897270032),
                SIMD3(1.000000000, 1.000000000, 1.000000000),
                SIMD3(0.133847780, 0.133847780, 0.133847780),
                SIMD3(0.147903454, 0.147903454, 0.147903454),
                SIMD3(0.263314613, 0.263314613, 0.263314613),
                SIMD3(0.249208419, 0.249208419, 0.249208419),
                SIMD3(0.461350233, 0.461350233, 0.461350233),
                SIMD3(0.106881157, 0.106881157, 0.106881157),
                SIMD3(0.849158695, 0.849158695, 0.849158695),
                SIMD3(0.572352271, 0.572352271, 0.572352271),
                SIMD3(0.190701948, 0.190701948, 0.190701948),
                SIMD3(0.227409299, 0.227409299, 0.227409299),
            ]),
            (.hr, [
                SIMD3(0.000000000, 0.000000000, 0.000000000),
                SIMD3(0.000000000, 0.000000000, 0.000000000),
                SIMD3(0.000318965, 0.000318965, 0.000318965),
                SIMD3(0.004687174, 0.004687174, 0.004687174),
                SIMD3(0.035101933, 0.035101933, 0.035101933),
                SIMD3(0.167980914, 0.167980914, 0.167980914),
                SIMD3(0.427686654, 0.427686654, 0.427686654),
                SIMD3(0.891841170, 0.891841170, 0.891841170),
                SIMD3(0.947571835, 0.947571835, 0.947571835),
                SIMD3(1.000000000, 1.000000000, 1.000000000),
                SIMD3(0.151496780, 0.075748390, 0.042082439),
                SIMD3(0.043048622, 0.103316692, 0.258291731),
                SIMD3(0.286646784, 0.191370208, 0.095918348),
                SIMD3(0.569169147, 0.095148321, 0.047629751),
                SIMD3(0.058359736, 0.520612675, 0.112774952),
                SIMD3(0.015971491, 0.039928728, 0.479144736),
                SIMD3(1.000000000, 0.957736026, 0.367770850),
                SIMD3(1.000000000, 0.413040618, 0.362046037),
                SIMD3(0.000009192, 0.183843111, 0.275764666),
                SIMD3(0.187548448, 0.187548448, 0.000009388),
            ], [
                SIMD3(0.000000000, 0.000000000, 0.000000000),
                SIMD3(0.000000000, 0.000000000, 0.000000000),
                SIMD3(0.000318965, 0.000318965, 0.000318965),
                SIMD3(0.004687174, 0.004687174, 0.004687174),
                SIMD3(0.035101933, 0.035101933, 0.035101933),
                SIMD3(0.167980914, 0.167980914, 0.167980914),
                SIMD3(0.427686654, 0.427686654, 0.427686654),
                SIMD3(0.891841170, 0.891841170, 0.891841170),
                SIMD3(0.947571835, 0.947571835, 0.947571835),
                SIMD3(1.000000000, 1.000000000, 1.000000000),
                SIMD3(0.089421816, 0.089421816, 0.089421816),
                SIMD3(0.101692898, 0.101692898, 0.101692898),
                SIMD3(0.204734384, 0.204734384, 0.204734384),
                SIMD3(0.192494308, 0.192494308, 0.192494308),
                SIMD3(0.392891817, 0.392891817, 0.392891817),
                SIMD3(0.066546815, 0.066546815, 0.066546815),
                SIMD3(0.924125861, 0.924125861, 0.924125861),
                SIMD3(0.534146374, 0.534146374, 0.534146374),
                SIMD3(0.139917462, 0.139917462, 0.139917462),
                SIMD3(0.173225865, 0.173225865, 0.173225865),
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

    /// F135·HR 은 SP 숫자의 변형이 아니라 각 기종의 문서화된 특성으로 따로 만든 표다(+Targets.swift).
    /// 그 특성을 고정한다. F135: 중간톤이 밝고 평탄하며 암부가 들려 있고 채도가 Noritsu(HS)보다 낮다.
    /// HR: 검정이 가장 깊고, 명부가 SP 처럼 접히지 않고 가파르게 서며, 명부 채도를 올리지 않는다.
    func testF135AndHRCarryTheirDocumentedCharacter() throws {
        func curves(_ target: DevelopTarget) throws -> ScannerTargetGrade.RenderingCurves {
            ScannerTargetGrade.RenderingCurves(try XCTUnwrap(ScannerTargetGrade.rendering(for: target)))
        }
        func localContrast(_ c: ScannerTargetGrade.RenderingCurves, _ a: Double, _ b: Double) -> Double {
            (log2(ScannerTargetGrade.srgbDecode(c.tone.value(at: b)))
                - log2(ScannerTargetGrade.srgbDecode(c.tone.value(at: a)))) / (b - a)
        }
        let sp = try curves(.sp3000), hs = try curves(.noritsu), f135 = try curves(.f135), hr = try curves(.hr)

        XCTAssertLessThan(localContrast(f135, -1, 1), localContrast(sp, -1, 1) * 0.85, "F135 중간톤이 SP 만큼 가파르다")
        XCTAssertLessThan(localContrast(f135, -1, 1), localContrast(hr, -1, 1), "F135 중간톤이 HR 보다 가파르다")
        XCTAssertGreaterThan(f135.tone.value(at: -6), sp.tone.value(at: -6) + 0.01, "F135 암부가 들리지 않았다")
        XCTAssertGreaterThan(ScannerTargetGrade.srgbDecode(f135.tone.value(at: 0)) / 0.18, pow(2, 0.2),
                             "F135 중간톤이 소비자 인화처럼 밝지 않다")
        for stop in stride(from: -5.0, through: 2.0, by: 0.5) {
            XCTAssertLessThan(f135.chromaGain.value(at: stop), hs.chromaGain.value(at: stop),
                              "F135 채도가 HS 보다 높다 at \(stop)")
        }

        for other in [sp, hs, f135] {
            XCTAssertLessThan(hr.tone.value(at: -8), other.tone.value(at: -8) - 0.015, "HR 검정이 가장 깊지 않다")
        }
        XCTAssertGreaterThan(localContrast(hr, 1, 2), localContrast(sp, 1, 2) * 1.2, "HR 명부가 SP 처럼 접힌다")
        XCTAssertLessThanOrEqual(hr.chromaGain.value(at: 2), 1.0, "HR 이 명부 채도를 올린다")
    }

    /// 네 타깃(과 MAIN)은 서로 눈에 띄게 다르다. 합성 차트(ColorChecker 18색 × 5 노출)에서 쌍마다
    /// 평균 ΔE76 를 잰다 — 실측으로 만든 SP↔HS 가 6.3, 가장 가까운 쌍은 HS↔HR 4.5 다(2026-11-07).
    /// 예전 F135·HR 은 SP 숫자에서 출발해 SP 와 1.7 안팎이었다.
    func testFourTargetsAreMutuallyDistinct() throws {
        let checker: [(Double, Double, Double)] = [
            (115, 82, 68), (194, 150, 130), (98, 122, 157), (87, 108, 67), (133, 128, 177), (103, 189, 170),
            (214, 126, 44), (80, 91, 166), (193, 90, 99), (94, 60, 108), (157, 188, 64), (224, 163, 46),
            (56, 61, 150), (70, 148, 73), (175, 54, 60), (231, 199, 31), (187, 86, 149), (8, 133, 161),
        ]
        var chart: [SIMD3<Double>] = []
        for (r, g, b) in checker {
            let linear = SIMD3(ScannerTargetGrade.srgbDecode(r / 255), ScannerTargetGrade.srgbDecode(g / 255),
                               ScannerTargetGrade.srgbDecode(b / 255))
            let luma = (linear * SIMD3(0.2126, 0.7152, 0.0722)).sum()
            for stop in [-3.0, -1.5, 0, 1, 1.8] { chart.append(linear * (0.18 * pow(2, stop) / luma)) }
        }
        func lab(_ v: SIMD3<Double>) -> SIMD3<Double> {
            let c = SIMD3(min(max(v.x, 0), 1), min(max(v.y, 0), 1), min(max(v.z, 0), 1))
            let l = ScannerTargetGrade.srgbToLab(r: ScannerTargetGrade.srgbEncode(c.x),
                                                 g: ScannerTargetGrade.srgbEncode(c.y),
                                                 b: ScannerTargetGrade.srgbEncode(c.z))
            return SIMD3(l.l, l.a, l.b)
        }
        var rendered: [String: [SIMD3<Double>]] = ["MAIN": chart.map(lab)]
        for target in targets {
            let curves = ScannerTargetGrade.RenderingCurves(try XCTUnwrap(ScannerTargetGrade.rendering(for: target)))
            rendered[target.displayName] = chart.map {
                lab(ScannerTargetGrade.renderLinear($0, curves: curves, monochrome: false))
            }
        }
        let names = rendered.keys.sorted()
        for (i, a) in names.enumerated() {
            for b in names[(i + 1)...] {
                let mean = zip(rendered[a]!, rendered[b]!).map { simd_length($0 - $1) }.reduce(0, +) / Double(chart.count)
                XCTAssertGreaterThan(mean, 4.0, "\(a)↔\(b) 평균 ΔE76 \(mean)")
            }
        }
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

    /// 타깃 렌더링은 화이트 밸런스·노출·기본 톤 **뒤**에 걸린다 — 같은 슬라이더를 준 MAIN 결과에
    /// 렌더링만 얹은 값과 같다. 예전에는 렌더링이 반전 직후에 있어, 흰색을 0.95 근처까지 그린 출력
    /// 위에서 MAIN 의 여유(흰색 0.70)를 전제로 만든 슬라이더가 돌았다(흰색 계열 +0.5 의 클리핑이
    /// MAIN 0%·SP 20.7%, 2026-11-07 실측). 슬라이더가 모두 0 이면 앞 단계가 항등이라 이 순서는
    /// 기본 그림을 바꾸지 않는다(골든이 지킨다).
    func testSceneSlidersActBeforeTheScannerRendering() throws {
        let wedge = SyntheticScan.negativeWedge()
        func patches(_ target: DevelopTarget) -> [SIMD3<Double>] {
            var params = DevelopParameters()
            params.baseEstimationMode = .manual
            params.manualBaseRGB = SyntheticScan.colorBase
            params.developTarget = target
            params.exposure = 0.4
            params.whites = 0.5
            params.highlight = 0.3
            params.warmth = 0.3
            let developed = ChromabaseEngine().developScanner(
                image: wedge.image, base: FilmBase(rgb: SyntheticScan.colorBase, source: .manual), params: params
            )
            return SyntheticScan.patchMeans(developed, wedge: wedge)
        }
        let main = patches(.main)
        for target in [DevelopTarget.sp3000, .f135, .hr] {
            let curves = ScannerTargetGrade.RenderingCurves(try XCTUnwrap(ScannerTargetGrade.rendering(for: target)))
            let rendered = patches(target)
            for (index, (m, r)) in zip(main, rendered).enumerated() {
                let expected = ScannerTargetGrade.renderLinear(m, curves: curves, monochrome: false)
                for c in 0..<3 {
                    XCTAssertEqual(r[c], expected[c], accuracy: 2e-3, "\(target.displayName) 패치 \(index) 채널 \(c)")
                }
            }
            // 장면 흰색(가장 짙은 패치)은 슬라이더를 올려도 순백에 붙지 않는다.
            XCTAssertLessThan(SyntheticScan.code(SyntheticScan.luma(rendered.last!)), 252, "\(target.displayName)")
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
