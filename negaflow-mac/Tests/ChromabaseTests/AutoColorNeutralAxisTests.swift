import CoreImage
import XCTest
@testable import Chromabase

/// 자동 색상(NeutralBalance v2)의 계약. 2026-10-14 실측 결함: 균일 캐스트를 감마로 고쳐 암부 과보정
/// (+0.30 스톱)·명부 미보정(−0.49 스톱), 0·1 고정 감마가 화이트(0.70) 중립을 깸(1.000→1.028).
final class AutoColorNeutralAxisTests: XCTestCase {
    /// 로그 간격 톤 14 개(0.005…0.70) — 휘도대가 여럿 생긴다.
    private let tones: [Double] = (0..<14).map { 0.005 * pow(0.70 / 0.005, Double($0) / 13) }

    private func wedge(_ channel: (Double) -> SIMD3<Double>) -> CIImage {
        SyntheticScan.makeImage(width: tones.count * 16, height: 16) { x, _ in channel(self.tones[x / 16]) }
    }

    private func samples(_ image: CIImage) -> [SIMD3<Double>] {
        let w = tones.count * 16, h = 16
        var bmp = [Float](repeating: 0, count: w * h * 4)
        CIContext(options: [.workingColorSpace: SyntheticScan.linear]).render(
            image, toBitmap: &bmp, rowBytes: w * 16, bounds: CGRect(x: 0, y: 0, width: w, height: h),
            format: .RGBAf, colorSpace: SyntheticScan.linear)
        return tones.indices.map { k in
            let i = ((h / 2) * w + k * 16 + 8) * 4
            return SIMD3(Double(bmp[i]), Double(bmp[i + 1]), Double(bmp[i + 2]))
        }
    }

    private func balanced(_ image: CIImage) -> [SIMD3<Double>] {
        samples(NeutralBalance.apply(to: image, sampleColorSpace: SyntheticScan.linear))
    }

    /// 균일 캐스트(광원·WB 성분)는 모든 톤에서 걷혀야 한다.
    func testUniformCastIsRemovedAtEveryTone() {
        let out = balanced(wedge { SIMD3(0.80, 1.0, 1.20) * $0 })
        for (k, p) in out.enumerated() where tones[k] >= 0.02 {
            XCTAssertEqual(log2(p.x / p.z), 0, accuracy: 0.05, "tone \(tones[k])")
            XCTAssertEqual(log2(p.y / (p.x * p.z).squareRoot()), 0, accuracy: 0.05, "tone \(tones[k])")
        }
    }

    /// 끝점이 중립이고 미드만 휜 캐스트는 미드를 고치되 화이트(0.70) 중립을 깨지 않는다.
    func testMidtoneBowIsRemovedWithoutBreakingWhite() {
        let out = balanced(wedge { SIMD3(0.70 * pow($0 / 0.70, 1.12), $0, $0) })
        XCTAssertEqual(out.last!.x / out.last!.z, 1, accuracy: 0.01, "화이트 중립이 깨졌다")
        for (k, p) in out.enumerated() where tones[k] >= 0.05 {
            XCTAssertEqual(log2(p.x / p.z), 0, accuracy: 0.03, "tone \(tones[k])")
        }
    }

    /// 이미 중립인 장면은 건드리지 않는다.
    func testNeutralSceneIsUntouched() {
        let input = wedge { SIMD3(repeating: $0) }
        let out = balanced(input)
        for (p, q) in zip(out, samples(input)) {
            XCTAssertEqual(p.x, q.x, accuracy: 1e-6)
            XCTAssertEqual(p.z, q.z, accuracy: 1e-6)
        }
    }

    /// 지배색(숲 초록 70%) 장면에서도 중립 패치는 중립으로 남고 초록은 회색으로 끌리지 않는다.
    func testDominantFoliageDoesNotPullTheNeutralAxis() {
        let width = tones.count * 16, height = 40
        let image = SyntheticScan.makeImage(width: width, height: height) { x, y in
            let t = self.tones[x / 16]
            return y < 28 ? SIMD3(0.35, 1.0, 0.28) * t : SIMD3(repeating: t)
        }
        let corrected = NeutralBalance.apply(to: image, sampleColorSpace: SyntheticScan.linear)
        var bmp = [Float](repeating: 0, count: width * height * 4)
        CIContext(options: [.workingColorSpace: SyntheticScan.linear]).render(
            corrected, toBitmap: &bmp, rowBytes: width * 16,
            bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: SyntheticScan.linear)
        // bitmap 행 0 = 위 = 입력 y 0(초록) — 아래쪽 행이 중립 띠다.
        for k in tones.indices where tones[k] >= 0.02 {
            let neutral = (36 * width + k * 16 + 8) * 4, foliage = (10 * width + k * 16 + 8) * 4
            XCTAssertEqual(log2(Double(bmp[neutral]) / Double(bmp[neutral + 2])), 0, accuracy: 0.05)
            XCTAssertEqual(log2(Double(bmp[foliage + 1]) / Double(bmp[foliage])), log2(1 / 0.35), accuracy: 0.1)
        }
    }
}
