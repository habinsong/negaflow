import XCTest
import CoreImage
@testable import Chromabase

/// 흐린/평탄 장면에서 스캐너 채도 개성을 부분 수축하는 게이트 검증.
///
/// 근본 원인: 톤은 sceneToneAnchor(exposureAnchored)로 계조 지지 밖(평탄) 장면을 게이트하지만
/// 채도(chroma 대역·hue 채도 게인)에는 같은 게이트가 없어, base vibrance 부스트와 겹쳐 흐린
/// 풍경에서 FUJI 과채도·NORITSU 과뮤트로 발산했다. 2026-07-23 QA 로 **개성 플로어** 추가:
/// 완전 항등 수렴은 평탄 장면에서 타겟 구분을 없애므로, 수축 weight 를
/// flatSceneChromaGateCeiling(0.65)으로 캡해 log-gain 의 35% 는 항상 남긴다.
/// 이 테스트는 (1) 순수 함수가 weight=0 에서 완전 무회귀·weight=1 에서 gain^0.35 부분
/// 보존·log 역수대칭임을, (2) 엔진 통합에서 풀레인지 장면은 개성 전체를 유지하고 평탄
/// 장면은 발산이 bounded(부분 보존)됨을 수치로 확인한다.
///
/// 특정 컷이 아니라 "계조 폭"이라는 일반 규칙으로 게이트되며, 임계는 발명값이 아니라 톤 게이트가
/// 쓰는 것과 같은 sceneToneAnchor.weight 를 재사용한다.
final class ScannerTargetChromaFlatSceneGateTests: XCTestCase {

    // MARK: 1. 순수 함수 — 무회귀 / 항등 / 역수 대칭

    private func vividSignature() -> ScannerTargetGrade.Signature {
        ScannerTargetGrade.Signature(
            tone: ScannerTargetGrade.designToneXs,
            neutralBins: [ScannerTargetGrade.NeutralBin(luma: 0.5, a: -1.2, b: 0.6)],
            hueAnchors: [
                ScannerTargetGrade.HueAnchor(hueDegrees: 55, chromaGain: 1.5, rotateDegrees: 3.0),
            ],
            chromaBands: [
                ScannerTargetGrade.ChromaBand(luma: 0.165, gain: 1.0),
                ScannerTargetGrade.ChromaBand(luma: 0.495, gain: 1.25),
                ScannerTargetGrade.ChromaBand(luma: 0.83, gain: 1.60),
            ])
    }

    func testFullRangeWeightLeavesSignatureByteIdentical() {
        let sig = vividSignature()
        // weight=0(풀레인지) → 시그니처 자체가 불변이어야 정상 장면 결과가 바이트로 안 바뀐다.
        XCTAssertEqual(ScannerTargetGrade.flatSceneChromaGated(sig, weight: 0.0), sig)
        // 임계 하한(1e-3) 아래도 완전 무회귀.
        XCTAssertEqual(ScannerTargetGrade.flatSceneChromaGated(sig, weight: 1e-4), sig)
    }

    func testFlatWeightRetainsPartialChromaCharacter() {
        let sig = vividSignature()
        let gated = ScannerTargetGrade.flatSceneChromaGated(sig, weight: 1.0)
        // 개성 플로어: weight=1 에서도 gain^(1-ceiling) = gain^0.35 가 남는다(완전 항등 금지).
        let keep = 1.0 - ScannerTargetGrade.flatSceneChromaGateCeiling
        for (index, band) in gated.chromaBands.enumerated() {
            XCTAssertEqual(band.gain, pow(sig.chromaBands[index].gain, keep), accuracy: 1e-12,
                           "평탄 장면에서 대역 채도는 부분 보존(gain^\(keep))이어야 한다")
        }
        // 극단 게인(1.60)도 발산이 bounded: 원래 log-gain 의 keep 비율만 남는다.
        XCTAssertLessThan(gated.chromaBands.last!.gain, 1.20, "평탄 장면 발산은 bounded")
        XCTAssertGreaterThan(gated.chromaBands.last!.gain, 1.10, "평탄 장면에서도 개성이 남아야 한다")
        for (index, anchor) in gated.hueAnchors.enumerated() {
            XCTAssertEqual(anchor.chromaGain, pow(sig.hueAnchors[index].chromaGain, keep),
                           accuracy: 1e-12, "평탄 장면에서 hue 채도 게인은 부분 보존")
        }
        // 채도가 아닌 성분(hue 회전·중립축 드리프트)은 게이트가 건드리지 않는다.
        XCTAssertEqual(gated.hueAnchors.first?.rotateDegrees, 3.0)
        XCTAssertEqual(gated.neutralBins, sig.neutralBins, "중립축 드리프트는 채도 게이트와 무관")
        XCTAssertEqual(gated.tone, sig.tone, "톤은 채도 게이트가 건드리지 않는다")
    }

    func testPartialWeightIsLogSymmetricAcrossReciprocalTargets() {
        // FUJI(부스트)와 그 reciprocal(NORITSU 방향)이 같은 weight 로 수축해도 곱이 1(역수 대칭).
        let weight = 0.5
        let fuji = ScannerTargetGrade.Signature(
            tone: ScannerTargetGrade.designToneXs, neutralBins: [], hueAnchors: [],
            chromaBands: [ScannerTargetGrade.ChromaBand(luma: 0.495, gain: 1.6)])
        let noritsu = ScannerTargetGrade.Signature(
            tone: ScannerTargetGrade.designToneXs, neutralBins: [], hueAnchors: [],
            chromaBands: [ScannerTargetGrade.ChromaBand(luma: 0.495, gain: 1.0 / 1.6)])
        let gFuji = ScannerTargetGrade.flatSceneChromaGated(fuji, weight: weight).chromaBands[0].gain
        let gNor = ScannerTargetGrade.flatSceneChromaGated(noritsu, weight: weight).chromaBands[0].gain
        XCTAssertEqual(gFuji, pow(1.6, 0.5), accuracy: 1e-12)
        XCTAssertEqual(gFuji * gNor, 1.0, accuracy: 1e-12, "log 도메인 수축은 역수 대칭을 보존해야 한다")
        // 수축 방향: 1.6 → 항등(1.0) 쪽으로 줄어든다.
        XCTAssertLessThan(gFuji, 1.6)
        XCTAssertGreaterThan(gFuji, 1.0)
    }

    // MARK: 2. 엔진 통합 — 풀레인지는 개성 유지, 평탄은 수렴

    /// 프레임 내부(보더 제외) 평균 Lab chroma. GUI 와 같은 sRGB 출력 도메인에서 측정한다.
    private func meanInnerChroma(_ px: [UInt8], width: Int, height: Int) -> Double {
        let bx = Int(Double(width) * 0.10), by = Int(Double(height) * 0.10)
        var sum = 0.0
        var n = 0.0
        for y in by..<(height - by) {
            for x in bx..<(width - bx) {
                let i = (y * width + x) * 4
                let lab = ScannerTargetGrade.srgbToLab(
                    r: Double(px[i]) / 255.0,
                    g: Double(px[i + 1]) / 255.0,
                    b: Double(px[i + 2]) / 255.0)
                sum += (lab.a * lab.a + lab.b * lab.b).squareRoot()
                n += 1
            }
        }
        return sum / max(n, 1)
    }

    /// 반전 뒤 작업공간(linear) positive 를 직접 만든다. 게이트는 ScannerTargetGrade.apply 가
    /// **입력 이미지의** sceneToneAnchor 로 구동되므로, 계조 폭(=weight)을 여기서 직접 제어하면
    /// 반전/Dmax 정규화 레이어의 교란 없이 게이트 자체를 정확히 검증할 수 있다.
    private func makePositive(
        width: Int, height: Int, pixel: (Double, Double) -> SIMD3<Double>
    ) -> CIImage {
        var floats = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let p = pixel(Double(x) / Double(max(width - 1, 1)),
                              Double(y) / Double(max(height - 1, 1)))
                floats[i] = Float(max(p.x, 0)); floats[i + 1] = Float(max(p.y, 0))
                floats[i + 2] = Float(max(p.z, 0)); floats[i + 3] = 1
            }
        }
        return CIImage(
            bitmapData: Data(bytes: floats, count: floats.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
    }

    private func renderSRGB8(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        let ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
        var px = [UInt8](repeating: 0, count: width * height * 4)
        ctx.render(image, toBitmap: &px, rowBytes: width * 4,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height),
                   format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return px
    }

    /// MAIN 대비 스캐너 그레이드의 순수 효과: 같은 입력 positive 에 ScannerTargetGrade 만 얹어
    /// 렌더한 평균 inner chroma. target=nil 이면 MAIN 등가(그레이드 없이 입력 그대로 렌더).
    private func gradedChroma(
        _ image: CIImage, target: DevelopTarget?, width: Int, height: Int
    ) -> Double {
        let out: CIImage
        if let target {
            var params = DevelopParameters()
            params.filmType = .colorNegative
            params.developTarget = target
            out = ScannerTargetGrade.apply(to: image, target: target, params: params)
        } else {
            out = image
        }
        return meanInnerChroma(renderSRGB8(out, width: width, height: height),
                               width: width, height: height)
    }

    func testFlatSceneConvergesScannerChromaWhileFullRangeKeepsCharacter() {
        let width = 240, height = 160

        // 풀레인지: 암부·명부 앵커 블록 + 사이 램프 → p05~p95 계조 폭이 넓어 weight≈0(게이트 off).
        // 채도 있는 색을 얹어 실측 방향(FUJI↑/NORITSU↓) 검증이 가능하게 한다.
        let fullRange = makePositive(width: width, height: height) { u, v in
            let level = u < 0.12 ? 0.006 : (u > 0.88 ? 0.985 : 0.02 + (u - 0.12) * 1.2)
            let hue = 2.0 * u + v
            let warm = 0.45 * cos(2.0 * .pi * hue)
            let cool = 0.45 * cos(2.0 * .pi * hue + 2.0)
            return SIMD3(level * (1.0 + warm), level, level * (1.0 + cool))
        }

        // 평탄/흐린: 좁은 계조(밝기 거의 고정 → weight≈1) + **뮤트하지만 색이 있는** 풍경.
        // 채도가 있으므로 게이트가 없으면 FUJI 가 ×1.6 로 밀어 발산한다 — 수렴이 비자명하다.
        let flat = makePositive(width: width, height: height) { u, _ in
            let level = 0.30 + 0.10 * u                          // linear 0.30~0.40(좁은 계조)
            let warm = 0.18 * cos(2.0 * .pi * u)                 // 밝기 ~고정, 뮤트한 hue 회전
            let cool = 0.18 * cos(2.0 * .pi * u + 2.0)
            return SIMD3(level * (1.0 + warm), level, level * (1.0 + cool))
        }

        // 인과 사슬 1/2 — flatness 신호: apply 가 내부에서 쓰는 바로 그 sceneToneAnchor.weight.
        let fullWeight = ScannerTargetGrade.sceneToneAnchor(for: fullRange).weight
        let flatWeight = ScannerTargetGrade.sceneToneAnchor(for: flat).weight
        print(String(format: "[chroma-gate] weight full=%.3f flat=%.3f", fullWeight, flatWeight))
        XCTAssertLessThan(fullWeight, 0.2, "풀레인지 장면은 게이트가 거의 off(개성 유지)여야 한다")
        XCTAssertGreaterThan(flatWeight, 0.9, "평탄 장면은 게이트가 거의 완전히 켜져야 한다")

        // 인과 사슬 2/2 — 그레이드 채도. MAIN 등가(입력)를 기준으로 FUJI/NORITSU 발산을 잰다.
        let baseFull = gradedChroma(fullRange, target: nil, width: width, height: height)
        let norFull = gradedChroma(fullRange, target: .noritsu, width: width, height: height)
        let spFull = gradedChroma(fullRange, target: .sp3000, width: width, height: height)
        let baseFlat = gradedChroma(flat, target: nil, width: width, height: height)
        let norFlat = gradedChroma(flat, target: .noritsu, width: width, height: height)
        let spFlat = gradedChroma(flat, target: .sp3000, width: width, height: height)
        print(String(format: "[chroma-gate] FULL base=%.2f nor=%.2f sp=%.2f | FLAT base=%.2f nor=%.2f sp=%.2f",
                     baseFull, norFull, spFull, baseFlat, norFlat, spFlat))

        // (a) 풀레인지(게이트 off): 실측 방향(FUJI 채도↑ > MAIN > NORITSU 채도↓)이 살아 있다.
        XCTAssertGreaterThan(spFull, baseFull * 1.05, "풀레인지에서 FUJI 채도 개성이 살아야 한다")
        XCTAssertLessThan(norFull, baseFull * 0.97, "풀레인지에서 NORITSU 뮤트 개성이 살아야 한다")
        let fullSpread = spFull - norFull

        // (b) 평탄(게이트 on, 2026-07-23 개성 플로어): 발산은 크게 줄되 완전 수렴은 금지 —
        //     FUJI 는 잔존 채도 개성(> MAIN)을 유지하고, 발산 크기는 풀레인지의 절반 미만으로
        //     bounded(원래 문제였던 vibrance 스택 과채도 재발 방지).
        let flatSpread = spFlat - norFlat
        XCTAssertLessThan(flatSpread, fullSpread * 0.45,
                          "평탄 장면의 FUJI↔NORITSU 채도 발산은 bounded 여야 한다")
        XCTAssertGreaterThan(spFlat, baseFlat * 1.05, "평탄 FUJI 도 잔존 채도 개성이 남아야 한다")
        // 실측 +22%(documented×measured 합성 잔존). 게이트 전 발산(밴드 ×1.6 스택)보다
        // 뚜렷이 작아야 하며, 30% 를 넘으면 vibrance 스택 과채도 재발 위험.
        XCTAssertLessThan(spFlat, baseFlat * 1.30, "평탄 FUJI 과채도 재발 금지(bounded)")
        XCTAssertLessThan(norFlat, spFlat, "평탄에서도 FUJI 리치 > NORITSU 뮤트 방향 유지")
        XCTAssertGreaterThan(norFlat, baseFlat * 0.85, "평탄 NORITSU 과뮤트 재발 금지(bounded)")
    }
}
