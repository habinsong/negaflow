import CoreImage
import XCTest
@testable import Chromabase

/// 노출 + 쪽 숄더와 어둡게 하는 톤 조정의 계약(2026-10-14 실측 결함의 회귀 가드).
final class ExposureShoulderTests: XCTestCase {

    /// GPU 커널과 CPU 참조(자동 톤 순방향 모델이 쓰는 식)가 같은 값을 내야 한다.
    func testKernelMatchesCPUReference() {
        let values = stride(from: 0.02, through: 0.95, by: 0.0465).map { $0 }
        let width = values.count
        let ramp = SyntheticScan.makeImage(width: width, height: 1) { x, _ in SIMD3(repeating: values[x]) }
        for (stops, filmType) in [(0.25, FilmType.colorNegative), (0.5, .colorNegative), (1.0, .colorNegative),
                                  (2.0, .colorNegative), (1.0, .bwNegative), (1.0, .colorPositive)] {
            let out = render(ToneMapper.applyExposure(to: ramp, stops: stops, filmType: filmType), width: width)
            for (index, value) in values.enumerated() {
                let expected = ExposureShoulder.exposedLuminance(value, stops: stops, filmType: filmType)
                XCTAssertEqual(out[index], expected, accuracy: 2e-4,
                               "\(filmType) \(stops)EV 입력 \(value)")
            }
        }
    }

    /// −EV 는 확산 화이트 위에서도 순수 선형 곱이다(숄더는 + 쪽 전용).
    func testNegativeExposureStaysPureLinearMultiply() {
        let solid = SyntheticScan.makeImage(width: 1, height: 1) { _, _ in SIMD3(repeating: 0.9) }
        let out = render(ToneMapper.applyExposure(to: solid, stops: -1), width: 1)
        XCTAssertEqual(out[0], 0.45, accuracy: 1e-5)
    }

    /// 컬러 네거티브 +1 EV: 하드 클립 없음, 명부 단조 증가, 미드는 정확히 2 배.
    /// 수정 전: 상위 6 패치가 255 로 평탄.
    func testColorNegativePlusOneStopRollsHighlightsWithoutClipping() {
        let wedge = SyntheticScan.negativeWedge()
        let base = SyntheticScan.developedDisplayPatches(wedge)
        let plus = SyntheticScan.developedDisplayPatches(wedge) { $0.exposure = 1 }
        let codes = plus.map { SyntheticScan.code(SyntheticScan.luma($0)) }
        XCTAssertFalse(codes.contains(255), "\(codes)")
        let highlights = plus[13...].map(SyntheticScan.luma)
        for (lower, upper) in zip(highlights, highlights.dropFirst()) {
            XCTAssertGreaterThan(upper, lower, "실수 명부 계조가 평탄해졌습니다")
        }
        XCTAssertEqual(SyntheticScan.luma(plus[8]) / SyntheticScan.luma(base[8]), 2.0, accuracy: 0.02)
    }

    /// 흑백 네거티브(화이트 0.85, 헤드룸 0.23 EV)도 +1 EV 에서 클립되지 않는다. 수정 전: 8 패치 클립.
    func testBWNegativePlusOneStopDoesNotClip() {
        let wedge = SyntheticScan.negativeWedge(base: SyntheticScan.neutralBase)
        let plus = SyntheticScan.developedDisplayPatches(wedge, base: SyntheticScan.neutralBase) {
            $0.filmType = .bwNegative
            $0.exposure = 1
        }
        let codes = plus.map { SyntheticScan.code(SyntheticScan.luma($0)) }
        XCTAssertFalse(codes.contains(255), "\(codes)")
    }

    /// +1 EV 뒤 Highlights −1 로 명부를 눌러도 계조가 남는다. 수정 전: 6 패치가 229 로 동일.
    func testHighlightRecoveryAfterPlusOneStopKeepsGradation() {
        let wedge = SyntheticScan.negativeWedge()
        let recovered = SyntheticScan.developedDisplayPatches(wedge) {
            $0.exposure = 1
            $0.highlight = -1
        }
        let highlights = recovered[13...].map(SyntheticScan.luma)
        for (lower, upper) in zip(highlights, highlights.dropFirst()) {
            XCTAssertGreaterThan(upper, lower)
        }
    }

    /// 어둡게 하는 톤 조정(대비 +, 블랙 −, 커브 다크/섀도 −)은 암부의 색비를 지킨다.
    /// 수정 전: R/B 1.2 가 대비 +1 에서 131, 블랙 −1 에서 559 로 폭주.
    func testDarkeningToneControlsPreserveShadowChroma() {
        let tones: [Double] = [0.005, 0.02, 0.05, 0.10, 0.18]
        let width = tones.count
        let warm = SyntheticScan.makeImage(width: width, height: 4) { x, _ in
            SIMD3(1.10, 1.0, 1.10 / 1.20) * tones[x]
        }
        let settings: [(String, (inout DevelopParameters) -> Void)] = [
            ("contrast +1", { $0.contrast = 1 }),
            ("blacks -1", { $0.blacks = -1 }),
            ("blacks -2", { $0.blacks = -2 }),
            ("curve darks -1", { $0.curveDarks = -1 }),
            ("curve shadows -1", { $0.curveShadows = -1 }),
        ]
        for (label, configure) in settings {
            var params = DevelopParameters()
            configure(&params)
            let out = renderRGB(ToneMapper.applyToneCurves(to: warm, params: params), width: width, height: 4)
            for (index, pixel) in out.enumerated() where pixel.z > 1e-5 {
                XCTAssertEqual(pixel.x / pixel.z, 1.20, accuracy: 0.02, "\(label) 입력 \(tones[index])")
            }
        }
    }

    /// 공유 CIContext 에서 톤 그래프를 바꿔 그려도 매번 새 그래프의 결과가 나와야 한다.
    /// 수정 전: 한 Metal 라이브러리의 stitchable 커널들이 컴파일 프로그램을 공유해
    /// basicTone → parametricToneCurve 전환 시 직전 결과가 그대로 나왔다.
    func testSharedContextRendersEachToneGraphFreshly() {
        let wedge = SyntheticScan.negativeWedge()
        let fresh = CIContext(options: [.workingColorSpace: SyntheticScan.linear, .cacheIntermediates: false])
        let pairs: [(String, (inout DevelopParameters) -> Void, (inout DevelopParameters) -> Void)] = [
            ("highlight → curve lights", { $0.highlight = -0.5 }, { $0.curveLights = 0.5 }),
            ("contrast → curve darks", { $0.contrast = 0.5 }, { $0.curveDarks = -0.5 }),
            ("highlight → exposure +1", { $0.highlight = -0.5 }, { $0.exposure = 1 }),
            ("exposure +1 → +2", { $0.exposure = 1 }, { $0.exposure = 2 }),
        ]
        for (label, first, second) in pairs {
            _ = SyntheticScan.developedDisplayPatches(wedge, first)
            let shared = SyntheticScan.developedDisplayPatches(wedge, second)
            let expected = SyntheticScan.developedDisplayPatches(wedge, context: fresh, second)
            for (s, e) in zip(shared, expected) {
                XCTAssertEqual(SyntheticScan.luma(s), SyntheticScan.luma(e), accuracy: 1e-5, label)
            }
        }
    }

    // MARK: 렌더 헬퍼

    private func render(_ image: CIImage, width: Int) -> [Double] {
        renderRGB(image, width: width, height: 1).map { $0.x }
    }

    private func renderRGB(_ image: CIImage, width: Int, height: Int) -> [SIMD3<Double>] {
        var bmp = [Float](repeating: 0, count: width * height * 4)
        CIContext(options: [.workingColorSpace: SyntheticScan.linear]).render(
            image, toBitmap: &bmp, rowBytes: width * 16,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf, colorSpace: SyntheticScan.linear
        )
        let row = height / 2
        return (0..<width).map { x in
            let i = (row * width + x) * 4
            return SIMD3(Double(bmp[i]), Double(bmp[i + 1]), Double(bmp[i + 2]))
        }
    }
}
