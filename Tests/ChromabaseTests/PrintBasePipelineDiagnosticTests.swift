import XCTest
import CoreImage
import CoreGraphics
import simd
@testable import Chromabase

/// main+Auto 기본 경로의 톤/색 특성을 **합성 네거티브**(실제 스캔 아님, 코드 생성)로 측정한다.
/// 특정 이미지에 의존하지 않고, 파이프라인의 수학적 특성(전역 게인·명부 클리핑·주황 hue)만
/// 검증하므로 오버핏이 불가능하다. 밀도 d 네거티브 픽셀 = base_ch × 10^(-d).
final class PrintBasePipelineDiagnosticTests: XCTestCase {
    private let baseRGB = SIMD3<Double>(0.90, 0.57, 0.38)   // 전형적 C-41 오렌지 베이스

    private func tx(_ d: Double, _ ch: Double) -> UInt8 {
        UInt8(min(255.0, max(0.0, ch * pow(10.0, -d) * 255.0)).rounded())
    }

    private func makeNeg(_ bytes: [UInt8], _ w: Int, _ h: Int) -> CIImage {
        var m = bytes
        let cg = CGContext(data: &m, width: w, height: h, bitsPerComponent: 8,
                           bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        return CIImage(cgImage: cg)
    }

    private func render(_ img: CIImage, _ w: Int, _ h: Int) -> [UInt8] {
        let ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
        var out = [UInt8](repeating: 0, count: w * h * 4)
        ctx.render(img, toBitmap: &out, rowBytes: w * 4,
                   bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8,
                   colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return out
    }

    private func develop(_ neg: CIImage) -> [UInt8] {
        let engine = ChromabaseEngine()
        let p = DevelopParameters()   // main 타겟, auto base, 모든 슬라이더 0 = 사용자 기본값
        let dev = engine.develop(image: neg, base: FilmBase(rgb: baseRGB, source: .border), params: p)
        let ext = neg.extent
        return render(dev, Int(ext.width), Int(ext.height))
    }

    /// 사용자 증상 1 재현: "밝은 이미지"(어두운 부분이 적어 장면 최대밀도 densest 가 낮은 장면)에서
    /// dmaxNorm 이 densest 에 맞춰져 명부가 dn≈1.0 으로 몰리는지(plateau) 측정한다.
    /// normal(어두운 부분 있음) vs bright(어두운 부분 거의 없음) 의 명부 계조를 비교한다.
    func testBrightImageHighlightPlateau() {
        let w = 120, h = 16
        for (name, dHi) in [("normal", 2.6), ("bright", 1.7)] {
            let dLo = 0.4
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            for x in 0..<w {
                let d = dLo + Double(x) / Double(w - 1) * (dHi - dLo)
                let r = tx(d, baseRGB.x), g = tx(d, baseRGB.y), b = tx(d, baseRGB.z)
                for y in 0..<h {
                    let i = (y * w + x) * 4
                    bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = 255
                }
            }
            let out = develop(makeNeg(bytes, w, h))
            // 명부 영역(밝은 positive = 고밀도 끝 30%)의 계조/클립.
            let x0 = Int(Double(w) * 0.70)
            var hi: [Int] = []
            for x in x0..<w {
                let i = (h / 2 * w + x) * 4
                hi.append((Int(out[i]) * 2126 + Int(out[i + 1]) * 7152 + Int(out[i + 2]) * 722) / 10000)
            }
            let distinct = Set(hi).count
            let clip = hi.filter { $0 >= 254 }.count
            print("[\(name) dHi=\(dHi)] highlight distinct=\(distinct)/\(hi.count) clip255=\(clip) range=[\(hi.min()!)..\(hi.max()!)]")
        }
    }

    /// 다양한 색(빨강/녹색/파랑/청록/마젠타)을 그레이 배경에 삽입해 hue·채도 보존을 스캔한다.
    /// 특히 mainTargetGrade 커널이 shadowMid 의 빨강 chroma 를 62% 깎으므로 어두운 빨강의 탈색을 본다.
    func testColorPatchHuePreservation() {
        let w = 120, h = 40
        let dLo = 0.30, dHi = 2.40
        // positive 색 = 중립 midD 에 채널별 밀도 offset. dR↑ = positive R 밝음.
        let colors: [(name: String, dr: Double, dg: Double, db: Double)] = [
            ("red    ", 0.42, -0.22, -0.22),
            ("green  ", -0.22, 0.42, -0.22),
            ("blue   ", -0.22, -0.22, 0.42),
            ("cyan   ", -0.30, 0.22, 0.22),
            ("magenta", 0.26, -0.30, 0.26),
        ]
        var hiRedSat = 0, hiGreenSat = 0
        for midD in [0.80, 1.40] {
            for c in colors {
                var bytes = [UInt8](repeating: 0, count: w * h * 4)
                for x in 0..<w {
                    let d = dLo + Double(x) / Double(w - 1) * (dHi - dLo)
                    let r = tx(d, baseRGB.x), g = tx(d, baseRGB.y), b = tx(d, baseRGB.z)
                    for y in 0..<h { let i = (y * w + x) * 4; bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = 255 }
                }
                let pr = tx(midD + c.dr, baseRGB.x), pg = tx(midD + c.dg, baseRGB.y), pb = tx(midD + c.db, baseRGB.z)
                let x0 = w * 2 / 5, x1 = w * 3 / 5, y0 = h * 2 / 5, y1 = h * 3 / 5
                for y in y0..<y1 { for x in x0..<x1 { let i = (y * w + x) * 4; bytes[i] = pr; bytes[i + 1] = pg; bytes[i + 2] = pb; bytes[i + 3] = 255 } }
                let out = develop(makeNeg(bytes, w, h))
                let i = ((y0 + y1) / 2 * w + (x0 + x1) / 2) * 4
                let (R, G, B) = (Int(out[i]), Int(out[i + 1]), Int(out[i + 2]))
                let sat = max(R, max(G, B)) - min(R, min(G, B))
                print("[\(c.name) midD=\(midD)] R=\(R) G=\(G) B=\(B) sat=\(sat)")
                if midD == 1.40, c.name.contains("red") { hiRedSat = sat }
                if midD == 1.40, c.name.contains("green") { hiGreenSat = sat }
            }
        }
        // 회귀: 명부 빨강이 다른 유채색 대비 과도 탈색되면 안 된다(절반 이상). mainTargetGrade 가
        // 명부 빨강까지 억제하던 문제(sat 26 = green 의 42%)가 재발하지 않게 고정. 현재 red≈47/green≈62.
        XCTAssertGreaterThan(hiRedSat * 2, hiGreenSat,
            "명부 빨강이 과도 탈색되면 안 된다(다른 유채색의 절반 이상). red=\(hiRedSat) green=\(hiGreenSat)")
    }

    /// OutputDither 단위 검증: 8bit 양자화 경계에 놓인 단일 톤이 dithering으로 인접 스텝(N, N+1)에
    /// 확률적으로 분산되고(=banding이 stipple로) 평균 톤은 보존되는지(편향 없음) 측정한다.
    func testOutputDitherDistributesQuantizationBoundary() {
        let w = 48, h = 48
        let lin = CGColorSpace(name: CGColorSpace.linearSRGB)!
        // sRGB 8bit 경계 중간값(200.5/255)에 해당하는 linear. dithering 없으면 전부 200 또는 201 단일.
        let srgbMid = 200.5 / 255.0
        let linV = srgbMid <= 0.04045 ? srgbMid / 12.92 : pow((srgbMid + 0.055) / 1.055, 2.4)
        let img = CIImage(color: CIColor(red: linV, green: linV, blue: linV, colorSpace: lin)!)
            .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        let out = render(OutputDither.apply(to: img), w, h)
        var vals = Set<Int>(); var sum = 0
        for i in stride(from: 0, to: out.count, by: 4) { vals.insert(Int(out[i])); sum += Int(out[i]) }
        let mean = Double(sum) / Double(w * h)
        print("[dither] single-tone sRGB200.5 → distinct=\(vals.sorted()) mean=\(String(format: "%.2f", mean))")
        XCTAssertGreaterThanOrEqual(vals.count, 2,
            "dithering이 양자화 경계를 인접 스텝으로 분산해야 banding이 사라진다. got=\(vals.sorted())")
        XCTAssertEqual(mean, 200.5, accuracy: 0.8, "평균 톤은 보존돼야 한다(노이즈 편향 없음)")
    }

    /// 중립 그레이 램프를 통과시켜 전역 게인·명부 클리핑을 측정.
    /// 네거티브 밀도 d 작음 = 미노광(positive 암부), d 큼 = 노광 많음(positive 명부).
    func testGrayRampToneResponse() {
        let w = 96, h = 16
        let dLo = 0.30, dHi = 2.80
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for x in 0..<w {
            let d = dLo + Double(x) / Double(w - 1) * (dHi - dLo)
            let r = tx(d, baseRGB.x), g = tx(d, baseRGB.y), b = tx(d, baseRGB.z)
            for y in 0..<h {
                let i = (y * w + x) * 4
                bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = 255
            }
        }
        let out = develop(makeNeg(bytes, w, h))
        func px(_ x: Int) -> (Int, Int, Int) {
            let i = (h / 2 * w + x) * 4
            return (Int(out[i]), Int(out[i + 1]), Int(out[i + 2]))
        }
        print("=== GRAY RAMP: neg density 0.25(left/bright) → 1.70(right/dark) ===")
        for x in stride(from: 0, to: w, by: 6) {
            let d = dLo + Double(x) / Double(w - 1) * (dHi - dLo)
            let (r, g, b) = px(x)
            let y = (r * 2126 + g * 7152 + b * 722) / 10000
            print(String(format: "x=%2d negD=%.2f  out R=%3d G=%3d B=%3d  Y=%3d", x, d, r, g, b, y))
        }
        // 명부 클리핑 진단: 가장 밝은(고밀도, 오른쪽 끝) 6개 위치의 luma 차이(클립이면 평탄).
        let ys = ((w - 6)..<w).map { x -> Int in let (r, g, b) = px(x); return (r + g + b) / 3 }
        print("highlight-end luma:", ys, " spread:", ys.max()! - ys.min()!)
        // 미드그레이(램프 중앙 d≈1.55) 출력 = 전역 밝기 지표.
        let (mr, mg, mb) = px(w / 2)
        print(String(format: "mid(d≈1.55) Y=%d (R=%d G=%d B=%d)", (mr + mg + mb) / 3, mr, mg, mb))
        // 적정 미드그레이에 해당하는 d≈0.95 지점도 측정.
        let q = Int(Double(w - 1) * (0.95 - dLo) / (dHi - dLo))
        let (qr, qg, qb) = px(q); print(String(format: "lowmid(d≈0.95) Y=%d", (qr + qg + qb) / 3))

        // 회귀 불변식: 중립 그레이 램프의 **미드톤**은 캐스트 없이 R≈G≈B를 유지해야 한다
        // (채도/감마 수정이 중립 장면을 탈색·착색시키지 않는지 검증).
        // 명부(밝은 영역)는 약한 따뜻함(R>B, 측정 R-B≈10~13)이 남아 있다 — 톤 영역별 잔류 캐스트로,
        // 채도 부스트 제거로 완화됐으나 완전 중립화는 명부 톤곡선 재설계(향후 작업) 영역이라 여기선
        // 관찰(아래 STAGE print)만 한다. 미드톤 중립은 강한 불변식으로 고정.
        for x in stride(from: 18, to: w / 2, by: 6) {
            let (r, g, b) = px(x)
            XCTAssertLessThan(abs(r - b), 8, "중립 미드톤이 캐스트되면 안 된다 x=\(x) R=\(r) G=\(g) B=\(b)")
        }
        // 명부(밝은 영역) R-B 따뜻함 측정(옵션 C 효과). 중립 램프이므로 R≈B여야 한다.
        var hiRB: [Int] = []
        for x in stride(from: w / 2 + 4, to: w - 4, by: 6) {
            let (r, _, b) = px(x); hiRB.append(r - b)
        }
        print("highlight R-B (neutral ramp, 옵션 C 목표 ≈0):", hiRB, " max:", hiRB.map { abs($0) }.max() ?? 0)
        // 회귀 불변식(옵션 C): 중립 램프의 명부 따뜻함이 완화돼야 한다. 옵션 C 미적용 시 max≈13.
        XCTAssertLessThan(hiRB.map { abs($0) }.max() ?? 0, 10,
                          "중립 명부 따뜻함(R-B)이 옵션 C로 완화돼야 한다. hiRB=\(hiRB)")

        // 명부 클립이 어느 단계에서 발생하는지 격리(debug stages). 향후 명부 톤곡선 재설계 시 측정 도구.
        let engine = ChromabaseEngine()
        let frames = engine.developDebugFramesScanner(
            image: makeNeg(bytes, w, h),
            base: FilmBase(rgb: baseRGB, source: .border),
            params: DevelopParameters())
        for f in frames {
            let r = render(f.image, w, h)
            let end = ((w - 8)..<w).map { x -> Int in
                let i = (h / 2 * w + x) * 4; return (Int(r[i]) + Int(r[i + 1]) + Int(r[i + 2])) / 3
            }
            print("STAGE \(f.stage.rawValue): highlight-end \(end) spread=\(end.max()! - end.min()!)")
        }
    }

    /// 주황 피사체(positive R>G>B)를 **중립 그레이 램프 배경에 삽입**해 통과시킨다.
    /// 단일 색 이미지는 NeutralBalance/AutoLevels 통계를 왜곡하므로, 실제 사진처럼 중립+컬러를
    /// 섞어 현실적 통계로 주황→노랑 hue shift를 측정한다.
    func testOrangeSubjectHue() {
        let w = 120, h = 40
        let dLo = 0.30, dHi = 2.40
        // 중립 midD 대비 R 밀도↑, B 밀도↓ → positive에서 R>G>B(주황). 두 밝기 측정.
        // hi-orange: 밝은 명부 영역의 채도 높은 주황(노을 등). 옵션 C 의 명부 desat 이 의도된 색을
        // 탈색하지 않고 R>G>B 단조를 유지해야 한다(lowChromaBias 보호 검증).
        let cases: [(name: String, midD: Double)] = [("bright-orange", 0.70), ("mid-orange", 1.20), ("hi-orange", 1.70)]
        for c in cases {
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            // 배경: 중립 그레이 램프(다양한 밀도 → 정상 히스토그램).
            for x in 0..<w {
                let d = dLo + Double(x) / Double(w - 1) * (dHi - dLo)
                let r = tx(d, baseRGB.x), g = tx(d, baseRGB.y), b = tx(d, baseRGB.z)
                for y in 0..<h {
                    let i = (y * w + x) * 4
                    bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = 255
                }
            }
            // 주황 피사체 패치(중앙 블록).
            let dR = c.midD + 0.32, dG = c.midD, dB = c.midD - 0.32
            let pr = tx(dR, baseRGB.x), pg = tx(dG, baseRGB.y), pb = tx(dB, baseRGB.z)
            let x0 = w * 2 / 5, x1 = w * 3 / 5, y0 = h * 2 / 5, y1 = h * 3 / 5
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let i = (y * w + x) * 4
                    bytes[i] = pr; bytes[i + 1] = pg; bytes[i + 2] = pb; bytes[i + 3] = 255
                }
            }
            let out = develop(makeNeg(bytes, w, h))
            let i = ((y0 + y1) / 2 * w + (x0 + x1) / 2) * 4
            let (R, G, B) = (Int(out[i]), Int(out[i + 1]), Int(out[i + 2]))
            // 주황이면 R>G>B 단조이고 (R-G)와 (G-B)가 균형. 노랑이면 B가 과도히 죽어 G-B ≫ R-G.
            print(String(format: "[%@] out R=%3d G=%3d B=%3d  (R-G)=%+d (G-B)=%+d  yellowness(G-B)-(R-G)=%+d",
                         c.name, R, G, B, R - G, G - B, (G - B) - (R - G)))
            // 회귀 불변식(문제 3): 주황은 R>G>B 단조를 유지해야 하고, B가 0으로 크러시되어
            // 노랑(R≈G, B≈0)으로 뒤집히면 안 된다. 과거 채도 과부스트가 B를 0으로 짓이겼다.
            XCTAssertGreaterThan(R, G, "[\(c.name)] 주황은 R>G여야 한다(노랑이면 R≈G). R=\(R) G=\(G) B=\(B)")
            XCTAssertGreaterThan(G, B, "[\(c.name)] 주황은 G>B 단조여야 한다. R=\(R) G=\(G) B=\(B)")
            XCTAssertGreaterThan(B, 35, "[\(c.name)] 주황의 B가 크러시되면 노랑이 된다. B=\(B)")
        }
    }
}
