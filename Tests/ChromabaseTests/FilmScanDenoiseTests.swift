import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

/// Multi-scale shrinkage NR 검증. clean/noisy 쌍 픽스처로 측정한다:
///   (1) 암부 grain·임펄스와 중간톤 색 얼룩(mottle)을 실제로 줄인다.
///   (2) 저채도 실색(warm patch)·고채도 실색(red patch)의 평균 채도를 보존한다(탈색 금지).
///   (3) 강한 엣지와 깨끗한 평탄 영역은 그대로 둔다(블러/뭉갬 금지).
///   (4) 필름 타입별: 흑백은 chroma 불변, 슬라이드는 암부, 네거티브는 클리핑부 chroma까지.
final class FilmScanDenoiseTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private let width = 200
    private let height = 128

    // Zones (x ranges)
    private let shadowZone = CGRect(x: 6, y: 6, width: 44, height: 116)      // grain + salt + chroma noise
    private let midZone = CGRect(x: 62, y: 6, width: 40, height: 116)        // chroma mottle
    // 색 보존 존은 패치 내부(경계로부터 ≥10px)를 잰다 — 경계 자체는 edgeBand 검사가 담당.
    private let weakSatZone = CGRect(x: 118, y: 6, width: 12, height: 116)   // CLEAN weak-sat warm
    private let edgeBand = CGRect(x: 137, y: 6, width: 2, height: 116)       // weakSat ↔ red edge
    private let redZone = CGRect(x: 148, y: 6, width: 12, height: 116)       // CLEAN saturated red
    private let clipZone = CGRect(x: 172, y: 6, width: 24, height: 116)      // near-clip + chroma speckle

    // MARK: fixtures

    private func hash(_ x: Int, _ y: Int, _ salt: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: (x &+ salt) &* 374761393 &+ (y &- salt) &* 668265263)
        h = (h ^ (h >> 13)) &* 1274126177
        h = h ^ (h >> 16)
        return Float(h) / Float(UInt32.max)
    }

    /// 대략적 가우시안(두 uniform 합) zero-mean 노이즈.
    private func gauss(_ x: Int, _ y: Int, _ salt: Int) -> Float {
        hash(x, y, salt) + hash(x &+ 101, y &+ 57, salt &+ 7) - 1
    }

    private func makeFixture(noisy: Bool) -> CIImage {
        var px = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let fy = Float(y) / Float(height - 1)
                var rgb: SIMD3<Float>
                if x < 56 {
                    let v = Float(0.07) + fy * 0.05
                    rgb = SIMD3(v * 0.98, v, v * 1.03)
                    if noisy {
                        rgb += SIMD3(repeating: gauss(x, y, 3) * 0.020)
                        rgb += SIMD3(gauss(x, y, 11), gauss(x, y, 23), gauss(x, y, 37)) * 0.015
                        if hash(x, y, 51) > 0.94 { rgb += SIMD3(repeating: 0.13) }  // salt impulse
                    }
                } else if x < 108 {
                    let v = Float(0.36) + fy * 0.06
                    rgb = SIMD3(v, v, v)
                    if noisy {
                        // 4~5px 색 얼룩(mottle) + 미세 grain.
                        let block = ((x / 4) + (y / 5) * 2) % 5
                        let mottle: SIMD3<Float>
                        switch block {
                        case 0: mottle = SIMD3(1.00, -0.42, -0.58)
                        case 1: mottle = SIMD3(-0.50, 0.96, -0.46)
                        case 2: mottle = SIMD3(-0.34, -0.54, 0.88)
                        case 3: mottle = SIMD3(0.55, -0.78, 0.23)
                        default: mottle = SIMD3(-0.24, 0.18, 0.06)
                        }
                        rgb += mottle * 0.045
                        rgb += SIMD3(repeating: gauss(x, y, 5) * 0.012)
                    }
                } else if x < 138 {
                    rgb = SIMD3(0.47, 0.43, 0.375)  // CLEAN 저채도 warm — 탈색 회귀 감시
                } else if x < 168 {
                    rgb = SIMD3(0.68, 0.14, 0.12)   // CLEAN 고채도 red
                } else {
                    rgb = SIMD3(repeating: 0.90)
                    if noisy {
                        // 클리핑 직전 마젠타/시안 speckle(반전된 네거티브 명부 노이즈).
                        let block = ((x / 3) + (y / 4) * 3) % 4
                        if block == 0 { rgb += SIMD3(0.055, -0.03, 0.05) }
                        if block == 2 { rgb += SIMD3(-0.045, 0.03, -0.04) }
                        rgb += SIMD3(repeating: gauss(x, y, 9) * 0.008)
                    }
                }
                px[i] = min(max(rgb.x, 0), 1)
                px[i + 1] = min(max(rgb.y, 0), 1)
                px[i + 2] = min(max(rgb.z, 0), 1)
                px[i + 3] = 1
            }
        }
        let data = Data(bytes: px, count: px.count * MemoryLayout<Float>.size)
        return CIImage(bitmapData: data, bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                       size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: linear)
    }

    private func render(_ image: CIImage) -> [Float] {
        var bm = [Float](repeating: 0, count: width * height * 4)
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        ctx.render(image, toBitmap: &bm, rowBytes: width * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: linear)
        return bm
    }

    // MARK: metrics

    private func luma(_ a: [Float], _ x: Int, _ y: Int) -> Double {
        let i = (y * width + x) * 4
        return 0.2126 * Double(a[i]) + 0.7152 * Double(a[i + 1]) + 0.0722 * Double(a[i + 2])
    }

    private func meanLumaError(_ a: [Float], _ b: [Float], rect: CGRect) -> Double {
        var sum = 0.0; var n = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                sum += abs(luma(a, x, y) - luma(b, x, y)); n += 1
            }
        }
        return sum / Double(max(1, n))
    }

    private func meanChromaError(_ a: [Float], _ b: [Float], rect: CGRect) -> Double {
        var sum = 0.0; var n = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let i = (y * width + x) * 4
                let ay = luma(a, x, y), by = luma(b, x, y)
                let dr = (Double(a[i]) - ay) - (Double(b[i]) - by)
                let dg = (Double(a[i + 1]) - ay) - (Double(b[i + 1]) - by)
                let db = (Double(a[i + 2]) - ay) - (Double(b[i + 2]) - by)
                sum += (dr * dr + dg * dg + db * db).squareRoot(); n += 1
            }
        }
        return sum / Double(max(1, n))
    }

    private func meanChroma(_ a: [Float], rect: CGRect) -> Double {
        var sum = 0.0; var n = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let i = (y * width + x) * 4
                let yy = luma(a, x, y)
                let r = Double(a[i]) - yy, g = Double(a[i + 1]) - yy, b = Double(a[i + 2]) - yy
                sum += (r * r + g * g + b * b).squareRoot(); n += 1
            }
        }
        return sum / Double(max(1, n))
    }

    private func meanEdge(_ a: [Float], rect: CGRect) -> Double {
        var sum = 0.0; var n = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                sum += abs(luma(a, x + 1, y) - luma(a, x - 1, y)); n += 1
            }
        }
        return sum / Double(max(1, n))
    }

    // MARK: tests

    func testStrengthZeroReturnsInputUnchanged() {
        let input = makeFixture(noisy: true)
        let out = FilmScanDenoise.apply(to: input, strength: 0, filmType: .colorNegative)
        let bi = render(input), bo = render(out)
        for i in stride(from: 0, to: bi.count, by: 17) {
            XCTAssertEqual(bo[i], bi[i], accuracy: 0.000001)
        }
    }

    func testReducesShadowGrainMidtoneMottleAndClipChromaSpeckle() {
        let clean = makeFixture(noisy: false)
        let noisy = makeFixture(noisy: true)
        let out = FilmScanDenoise.apply(to: noisy, strength: 0.7, filmType: .colorNegative)
        let bc = render(clean), bi = render(noisy), bo = render(out)

        let shadowIn = meanLumaError(bi, bc, rect: shadowZone)
        let shadowOut = meanLumaError(bo, bc, rect: shadowZone)
        let shadowChromaIn = meanChromaError(bi, bc, rect: shadowZone)
        let shadowChromaOut = meanChromaError(bo, bc, rect: shadowZone)
        let midIn = meanChromaError(bi, bc, rect: midZone)
        let midOut = meanChromaError(bo, bc, rect: midZone)
        let clipIn = meanChromaError(bi, bc, rect: clipZone)
        let clipOut = meanChromaError(bo, bc, rect: clipZone)
        print(String(format: "[nr] shadow luma %.4f->%.4f | shadow chroma %.4f->%.4f | mid chroma %.4f->%.4f | clip chroma %.4f->%.4f",
                     shadowIn, shadowOut, shadowChromaIn, shadowChromaOut, midIn, midOut, clipIn, clipOut))

        XCTAssertLessThan(shadowOut, shadowIn * 0.60, "암부 grain+임펄스는 기본 강도(0.7)에서 40% 이상 줄어야 한다")
        XCTAssertLessThan(shadowChromaOut, shadowChromaIn * 0.55, "암부 컬러 노이즈는 45% 이상 줄어야 한다")
        XCTAssertLessThan(midOut, midIn * 0.50, "중간톤 색 얼룩(mottle)은 50% 이상 줄어야 한다")
        XCTAssertLessThan(clipOut, clipIn * 0.65, "네거티브 클리핑 직전 chroma speckle도 줄어야 한다")
    }

    func testDoesNotDesaturateRealColorOrEraseEdgeAtFullStrength() {
        let clean = makeFixture(noisy: false)
        let noisy = makeFixture(noisy: true)
        let out = FilmScanDenoise.apply(to: noisy, strength: 1.0, filmType: .colorNegative)
        let bc = render(clean), bo = render(out)

        let weakIn = meanChroma(bc, rect: weakSatZone)
        let weakOut = meanChroma(bo, rect: weakSatZone)
        let redIn = meanChroma(bc, rect: redZone)
        let redOut = meanChroma(bo, rect: redZone)
        let edgeIn = meanEdge(bc, rect: edgeBand)
        let edgeOut = meanEdge(bo, rect: edgeBand)
        let cleanChange = meanLumaError(bo, bc, rect: weakSatZone)
        print(String(format: "[nr-preserve] weakSat %.4f->%.4f | red %.4f->%.4f | edge %.4f->%.4f | clean-change %.5f",
                     weakIn, weakOut, redIn, redOut, edgeIn, edgeOut, cleanChange))

        XCTAssertGreaterThan(weakOut, weakIn * 0.94, "최대 강도에서도 저채도 실색(warm patch)은 탈색되면 안 된다")
        XCTAssertGreaterThan(redOut, redIn * 0.94, "최대 강도에서도 고채도 실색은 탈색되면 안 된다")
        XCTAssertGreaterThan(edgeOut, edgeIn * 0.88, "강한 엣지는 유지돼야 한다(뭉갬 금지)")
        XCTAssertLessThan(cleanChange, 0.004, "깨끗한 평탄 영역은 사실상 그대로여야 한다")
    }

    func testStrengthScalesResidualNoiseMonotonically() {
        let clean = makeFixture(noisy: false)
        let noisy = makeFixture(noisy: true)
        let bc = render(clean)
        func residual(_ s: Double) -> Double {
            let out = FilmScanDenoise.apply(to: noisy, strength: s, filmType: .colorNegative)
            let bo = render(out)
            return meanLumaError(bo, bc, rect: shadowZone) + meanChromaError(bo, bc, rect: midZone)
        }
        let r0 = meanLumaError(render(noisy), bc, rect: shadowZone) + meanChromaError(render(noisy), bc, rect: midZone)
        let rWeak = residual(0.25)
        let rMid = residual(0.6)
        let rFull = residual(1.0)
        print(String(format: "[nr-strength] none %.4f | 0.25 %.4f | 0.6 %.4f | 1.0 %.4f", r0, rWeak, rMid, rFull))

        XCTAssertLessThan(rWeak, r0, "약한 강도도 노이즈를 줄여야 한다")
        XCTAssertLessThan(rMid, rWeak, "강도를 올리면 잔여 노이즈가 줄어야 한다")
        XCTAssertLessThan(rFull, rMid * 1.02, "최대 강도에서 잔여 노이즈가 다시 늘면 안 된다")
    }

    func testBWFilmDenoisesLumaOnlyAndLeavesChromaUntouched() {
        let clean = makeFixture(noisy: false)
        let noisy = makeFixture(noisy: true)
        let out = FilmScanDenoise.apply(to: noisy, strength: 0.8, filmType: .bwNegative)
        let bc = render(clean), bi = render(noisy), bo = render(out)

        let shadowIn = meanLumaError(bi, bc, rect: shadowZone)
        let shadowOut = meanLumaError(bo, bc, rect: shadowZone)
        // 흑백은 chroma를 건드리지 않는다: 노이즈 입력 대비 chroma 변화가 없어야 한다.
        let chromaDrift = meanChromaError(bo, bi, rect: midZone)
        print(String(format: "[nr-bw] shadow %.4f->%.4f | chroma drift %.5f", shadowIn, shadowOut, chromaDrift))

        XCTAssertLessThan(shadowOut, shadowIn * 0.65, "흑백 필름도 luma 노이즈는 줄어야 한다")
        XCTAssertLessThan(chromaDrift, 0.006, "흑백 필름에서 chroma는 건드리지 않는다(그레이스케일 변환이 담당)")
    }

    func testSlideFilmReducesShadowNoiseStrongly() {
        let clean = makeFixture(noisy: false)
        let noisy = makeFixture(noisy: true)
        let out = FilmScanDenoise.apply(to: noisy, strength: 0.7, filmType: .colorPositive)
        let bc = render(clean), bi = render(noisy), bo = render(out)

        let shadowIn = meanLumaError(bi, bc, rect: shadowZone)
        let shadowOut = meanLumaError(bo, bc, rect: shadowZone)
        let redIn = meanChroma(bc, rect: redZone)
        let redOut = meanChroma(bo, rect: redZone)
        print(String(format: "[nr-slide] shadow %.4f->%.4f | red %.4f->%.4f", shadowIn, shadowOut, redIn, redOut))

        XCTAssertLessThan(shadowOut, shadowIn * 0.60, "슬라이드는 암부(필름 고농도부) 노이즈를 강하게 줄여야 한다")
        XCTAssertGreaterThan(redOut, redIn * 0.94, "슬라이드에서도 실색은 보존돼야 한다")
    }
}
