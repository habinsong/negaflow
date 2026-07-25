import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

/// NR 축 분리 검증. 3밴드 합성 픽스처(미드톤 grain / 미드톤 색 얼룩 / 암부 노이즈)로
/// 각 축이 자기 대상만 조절하고 다른 축의 대상은 건드리지 않음을 측정한다:
///   (1) luma 축 0 → 휘도 노이즈 보존, chroma는 계속 정리(반대도 성립).
///   (2) dark-tone 축은 암부 잔여 노이즈만 단조 감소시키고 미드톤 chroma에는 중립.
///   (3) detail 축 ↑ → 엣지 보존 ↑, 평탄부 노이즈 제거는 유지.
///   (4) grain 보호 축 ↑ → 미드톤 무채색 grain 보존, 같은 존의 색 얼룩·암부 노이즈는 계속 제거.
final class FilmScanDenoiseAxesTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private let width = 200
    private let height = 128

    // Zones (x ranges) — 밴드 경계에서 8px 안쪽만 측정한다.
    private let grainZone = CGRect(x: 8, y: 8, width: 48, height: 112)    // 미드톤 luma-only grain
    private let mottleZone = CGRect(x: 76, y: 8, width: 48, height: 112)  // 미드톤 chroma mottle
    private let darkZone = CGRect(x: 144, y: 8, width: 48, height: 112)   // 암부 luma+chroma 노이즈
    // detail 축 픽스처 존: 8px 주기 저대비 스트라이프(중간 스케일 실제 질감) / 평탄 암부.
    private let stripeZone = CGRect(x: 8, y: 8, width: 84, height: 112)
    private let stripeDarkZone = CGRect(x: 108, y: 8, width: 84, height: 112)

    // MARK: fixtures

    private func hash(_ x: Int, _ y: Int, _ salt: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: (x &+ salt) &* 374761393 &+ (y &- salt) &* 668265263)
        h = (h ^ (h >> 13)) &* 1274126177
        h = h ^ (h >> 16)
        return Float(h) / Float(UInt32.max)
    }

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
                if x < 68 {
                    // 미드톤 grain 밴드: 무채색(luma-only) 미세 grain — 보존 대상 질감.
                    let v = Float(0.38) + fy * 0.04
                    rgb = SIMD3(v, v, v)
                    if noisy {
                        rgb += SIMD3(repeating: gauss(x, y, 3) * 0.018)
                    }
                } else if x < 136 {
                    // 미드톤 chroma mottle 밴드: 4~5px 색 얼룩 — grain 보호와 무관하게 제거 대상.
                    let v = Float(0.38) + fy * 0.04
                    rgb = SIMD3(v, v, v)
                    if noisy {
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
                    }
                } else {
                    // 암부 밴드: 스캔 노이즈 지배 영역(luma grain + 색 노이즈).
                    let v = Float(0.07) + fy * 0.05
                    rgb = SIMD3(v * 0.98, v, v * 1.03)
                    if noisy {
                        rgb += SIMD3(repeating: gauss(x, y, 11) * 0.020)
                        rgb += SIMD3(gauss(x, y, 23), gauss(x, y, 37), gauss(x, y, 51)) * 0.015
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

    /// detail 축 전용 픽스처. 스트라이프는 구조 가드의 판별 창(detail 1에서는 보호,
    /// detail 0에서는 coring)에 들어오는 진폭·주기로 둔다.
    private func makeStripeFixture(noisy: Bool) -> CIImage {
        var px = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let fy = Float(y) / Float(height - 1)
                var rgb: SIMD3<Float>
                if x < 100 {
                    // 미드톤 + 12px 주기 사인 스트라이프(±0.09) — 지워지면 안 되는 실제 디테일.
                    // 진폭·주기는 detail 축 판별 창 안: detail 1이면 임계가 절반으로 내려가
                    // 질감 계수가 통과하고, detail 0이면 임계가 1.5배로 올라 coring된다.
                    let v = Float(0.40) + 0.09 * sin(Float(x) * .pi / 6)
                    rgb = SIMD3(v, v, v)
                    if noisy {
                        rgb += SIMD3(repeating: gauss(x, y, 3) * 0.015)
                    }
                } else {
                    let v = Float(0.07) + fy * 0.05
                    rgb = SIMD3(v * 0.98, v, v * 1.03)
                    if noisy {
                        rgb += SIMD3(repeating: gauss(x, y, 11) * 0.020)
                        rgb += SIMD3(gauss(x, y, 23), gauss(x, y, 37), gauss(x, y, 51)) * 0.015
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

    private func denoise(_ image: CIImage, axes: FilmScanDenoise.Axes,
                         strength: Double = 0.7) -> [Float] {
        render(FilmScanDenoise.apply(to: image, strength: strength, filmType: .colorNegative, axes: axes))
    }

    // MARK: tests

    func testLumaAxisZeroKeepsLumaNoiseWhileChromaCleans() {
        let clean = makeFixture(noisy: false)
        let noisy = makeFixture(noisy: true)
        let bc = render(clean), bi = render(noisy)
        let bo = denoise(noisy, axes: .init(luma: 0))

        let grainIn = meanLumaError(bi, bc, rect: grainZone)
        let grainOut = meanLumaError(bo, bc, rect: grainZone)
        let darkIn = meanLumaError(bi, bc, rect: darkZone)
        let darkOut = meanLumaError(bo, bc, rect: darkZone)
        let mottleIn = meanChromaError(bi, bc, rect: mottleZone)
        let mottleOut = meanChromaError(bo, bc, rect: mottleZone)
        print(String(format: "[nr-axis-luma0] grain %.4f->%.4f | dark %.4f->%.4f | mottle %.4f->%.4f",
                     grainIn, grainOut, darkIn, darkOut, mottleIn, mottleOut))

        XCTAssertGreaterThan(grainOut, grainIn * 0.85, "luma 축 0에서 미드톤 luma 질감은 보존돼야 한다")
        XCTAssertGreaterThan(darkOut, darkIn * 0.80, "luma 축 0에서 암부 luma 노이즈도 수축하지 않는다")
        XCTAssertLessThan(mottleOut, mottleIn * 0.55, "luma 축 0이어도 chroma 노이즈는 계속 정리된다")
    }

    func testChromaAxisZeroKeepsChromaWhileLumaCleans() {
        let clean = makeFixture(noisy: false)
        let noisy = makeFixture(noisy: true)
        let bc = render(clean), bi = render(noisy)
        let bo = denoise(noisy, axes: .init(chroma: 0))

        let mottleIn = meanChromaError(bi, bc, rect: mottleZone)
        let mottleOut = meanChromaError(bo, bc, rect: mottleZone)
        let darkIn = meanLumaError(bi, bc, rect: darkZone)
        let darkOut = meanLumaError(bo, bc, rect: darkZone)
        print(String(format: "[nr-axis-chroma0] mottle %.4f->%.4f | dark luma %.4f->%.4f",
                     mottleIn, mottleOut, darkIn, darkOut))

        XCTAssertGreaterThan(mottleOut, mottleIn * 0.85, "chroma 축 0에서 색 얼룩은 보존돼야 한다")
        XCTAssertLessThan(darkOut, darkIn * 0.65, "chroma 축 0이어도 luma 노이즈는 계속 정리된다")
    }

    func testLumaAxisScalesResidualMonotonically() {
        let clean = makeFixture(noisy: false)
        let noisy = makeFixture(noisy: true)
        let bc = render(clean)
        func residual(_ axis: Double) -> Double {
            meanLumaError(denoise(noisy, axes: .init(luma: axis)), bc, rect: darkZone)
        }
        let rOff = residual(0)
        let rHalf = residual(0.5)
        let rFull = residual(1.0)
        print(String(format: "[nr-axis-luma-mono] 0 %.4f | 0.5 %.4f | 1.0 %.4f", rOff, rHalf, rFull))

        XCTAssertLessThan(rHalf, rOff, "luma 축을 올리면 암부 luma 잔여 노이즈가 줄어야 한다")
        XCTAssertLessThan(rFull, rHalf * 1.02, "최대 축에서 잔여 노이즈가 다시 늘면 안 된다")
    }

    func testDarkToneAxisControlsShadowStrengthAndStaysNeutralInMidtones() {
        let clean = makeFixture(noisy: false)
        let noisy = makeFixture(noisy: true)
        let bc = render(clean)
        let boLow = denoise(noisy, axes: .init(darkTone: 0))
        let boHigh = denoise(noisy, axes: .init(darkTone: 1))

        let darkLow = meanLumaError(boLow, bc, rect: darkZone) + meanChromaError(boLow, bc, rect: darkZone)
        let darkHigh = meanLumaError(boHigh, bc, rect: darkZone) + meanChromaError(boHigh, bc, rect: darkZone)
        let mottleLow = meanChromaError(boLow, bc, rect: mottleZone)
        let mottleHigh = meanChromaError(boHigh, bc, rect: mottleZone)
        print(String(format: "[nr-axis-dark] dark low %.4f high %.4f | mottle low %.4f high %.4f",
                     darkLow, darkHigh, mottleLow, mottleHigh))

        XCTAssertLessThan(darkHigh, darkLow * 0.92, "dark-tone 축 1은 0보다 암부 잔여 노이즈가 적어야 한다")
        XCTAssertEqual(mottleHigh, mottleLow, accuracy: mottleLow * 0.12,
                       "dark-tone 축은 미드톤 chroma 정리에 사실상 중립이어야 한다")
    }

    func testDetailAxisPreservesFineTextureWithoutDisablingFlatDenoise() {
        let clean = makeStripeFixture(noisy: false)
        let noisy = makeStripeFixture(noisy: true)
        let bc = render(clean), bi = render(noisy)
        let boLow = denoise(noisy, axes: .init(detail: 0), strength: 1.0)
        let boHigh = denoise(noisy, axes: .init(detail: 1), strength: 1.0)

        // 스트라이프 잔차 = 잔여 노이즈 + 질감 손실. detail 1은 질감을 지키므로 잔차가 작아야 한다.
        let stripeLow = meanLumaError(boLow, bc, rect: stripeZone)
        let stripeHigh = meanLumaError(boHigh, bc, rect: stripeZone)
        let stripeIn = meanLumaError(bi, bc, rect: stripeZone)
        let darkHigh = meanLumaError(boHigh, bc, rect: stripeDarkZone)
        let darkIn = meanLumaError(bi, bc, rect: stripeDarkZone)
        print(String(format: "[nr-axis-detail] stripe in %.4f low %.4f high %.4f | dark %.4f->%.4f",
                     stripeIn, stripeLow, stripeHigh, darkIn, darkHigh))

        XCTAssertLessThan(stripeHigh, stripeLow * 0.75, "detail 축 1은 0보다 미세 질감(스트라이프)을 뚜렷하게 더 보존해야 한다")
        XCTAssertLessThan(darkHigh, darkIn * 0.70, "detail 축 1이어도 평탄 암부 노이즈는 계속 정리된다")
    }

    func testGrainProtectKeepsMidtoneGrainWhileCleaningChromaAndShadows() {
        let clean = makeFixture(noisy: false)
        let noisy = makeFixture(noisy: true)
        let bc = render(clean), bi = render(noisy)
        let boProtect = denoise(noisy, axes: .init(grainProtect: 1))
        let boPlain = denoise(noisy, axes: .init(grainProtect: 0))

        let grainIn = meanLumaError(bi, bc, rect: grainZone)
        let grainProtected = meanLumaError(boProtect, bc, rect: grainZone)
        let grainPlain = meanLumaError(boPlain, bc, rect: grainZone)
        let mottleIn = meanChromaError(bi, bc, rect: mottleZone)
        let mottleProtected = meanChromaError(boProtect, bc, rect: mottleZone)
        let darkIn = meanLumaError(bi, bc, rect: darkZone)
        let darkProtected = meanLumaError(boProtect, bc, rect: darkZone)
        print(String(format: "[nr-axis-grain] grain in %.4f protect %.4f plain %.4f | mottle %.4f->%.4f | dark %.4f->%.4f",
                     grainIn, grainProtected, grainPlain, mottleIn, mottleProtected, darkIn, darkProtected))

        XCTAssertGreaterThan(grainProtected, grainIn * 0.75, "grain 보호 1에서 미드톤 grain 질감은 대부분 남아야 한다")
        XCTAssertLessThan(grainPlain, grainIn * 0.60, "grain 보호 0에서는 기존처럼 grain이 수축된다")
        XCTAssertGreaterThan(grainProtected, grainPlain * 1.5, "보호 on/off의 grain 잔존 차이가 뚜렷해야 한다")
        XCTAssertLessThan(mottleProtected, mottleIn * 0.55, "grain 보호 중에도 미드톤 색 얼룩은 계속 제거된다")
        XCTAssertLessThan(darkProtected, darkIn * 0.70, "grain 보호는 미드톤 한정 — 암부 노이즈는 계속 제거된다")
    }
}
