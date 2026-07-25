import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// 브러시 Heal(Lightroom 모델) 검증 — 칠한 영역을 이웃 실제 픽셀로 복제 + 저주파 톤 매칭.
// 픽셀 동일성이 아니라 "지각 동일성"이 계약이다: 결함 소멸, 텍스처 통계(채널/크로마 std) 보존,
// 저주파 톤 연속(그라데이션 추종), 칠 밖 무변화, 교차 구조 보존(직교 변위의 자기 매핑).
final class DefectHealBrushTests: XCTestCase {
    private let cs = CGColorSpace(name: CGColorSpace.sRGB)!

    private func ci(_ px: [UInt8], _ w: Int, _ h: Int) -> CIImage {
        CIImage(bitmapData: Data(px), bytesPerRow: w * 4,
                size: CGSize(width: w, height: h), format: .RGBA8, colorSpace: cs)
    }
    private func render(_ img: CIImage, _ w: Int, _ h: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        CIContext(options: [.workingColorSpace: cs]).render(
            img, toBitmap: &out, rowBytes: w * 4,
            bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8, colorSpace: cs)
        return out
    }
    private func lum(_ a: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> Int { Int(a[(y * w + x) * 4]) }

    /// 가로 그라데이션 + 크로마 그레인. 반환: (픽셀, 그레인 없는 기준 밝기 함수)
    private func gradientGrainScene(w: Int, h: Int, amp: Int, seed: UInt64) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        var s = seed
        for y in 0..<h {
            for x in 0..<w {
                let base = 70 + 100 * x / w
                let o = (y * w + x) * 4
                for c in 0..<3 {
                    s = s &* 6364136223846793005 &+ 1442695040888963407
                    let n = Int(s >> 40) % (2 * amp + 1) - amp
                    px[o + c] = UInt8(max(0, min(255, base + n)))
                }
                px[o + 3] = 255
            }
        }
        return px
    }

    private func band(w: Int, h: Int, x0: Int, x1: Int) -> CIImage {
        var bp = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in x0..<x1 {
                let o = (y * w + x) * 4
                bp[o] = 255; bp[o + 1] = 255; bp[o + 2] = 255; bp[o + 3] = 255
            }
        }
        return ci(bp, w, h)
    }

    private func columnStd(_ a: [UInt8], _ w: Int, x: Int, y0: Int, y1: Int) -> Double {
        var vals = [Double]()
        for y in y0..<y1 { vals.append(Double(lum(a, w, x, y))) }
        let m = vals.reduce(0, +) / Double(vals.count)
        return (vals.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(vals.count)).squareRoot()
    }
    private func columnMean(_ a: [UInt8], _ w: Int, x: Int, y0: Int, y1: Int) -> Double {
        var sum = 0.0
        for y in y0..<y1 { sum += Double(lum(a, w, x, y)) }
        return sum / Double(y1 - y0)
    }
    private func chromaStd(_ a: [UInt8], _ w: Int, x0: Int, x1: Int, y0: Int, y1: Int) -> Double {
        var vals = [Double]()
        for y in y0..<y1 {
            for x in x0..<x1 {
                let o = (y * w + x) * 4
                vals.append(Double(a[o]) - Double(a[o + 1]))
            }
        }
        let m = vals.reduce(0, +) / Double(vals.count)
        return (vals.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(vals.count)).squareRoot()
    }

    /// 세로 스크래치 + 세로 스트로크: 결함 소멸 + 텍스처 통계 보존 + 그라데이션 톤 추종 + 칠 밖 무변화.
    func testHealRemovesScratchPreservesTextureAndTone() {
        let w = 400, h = 300
        var px = gradientGrainScene(w: w, h: h, amp: 8, seed: 0x11EA)
        let clean = px
        for y in 0..<h {                       // 세로 스크래치(x=200, 2px, +55)
            for x in 200...201 {
                let o = (y * w + x) * 4
                let v = UInt8(min(255, Int(px[o]) + 55))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
        let img = ci(px, w, h)
        let brush = band(w: w, h: h, x0: 188, x1: 213)
        guard let out = DefectHealBrush.heal(to: img, brush: brush,
                                          repairExtent: CGRect(x: 0, y: 0, width: w, height: h),
                                          preferredAngle: 90, strength: 1.0) else {
            return XCTFail("heal 이 유효 소스를 찾지 못함")
        }
        let after = render(out, w, h)
        // (a) 스크래치 소멸: 결함 컬럼 평균이 그레인 없는 기준(±그레인)으로 복귀.
        let scratchMean = columnMean(after, w, x: 200, y0: 20, y1: 280)
        let refMean = columnMean(clean, w, x: 200, y0: 20, y1: 280)
        XCTAssertLessThan(abs(scratchMean - refMean), 6, "스크래치가 heal 로 제거되어야 한다")
        // (b) 텍스처 통계 보존: 칠 안 컬럼 std ≈ 칠 밖 컬럼 std.
        let inStd = columnStd(after, w, x: 196, y0: 20, y1: 280)
        let outStd = columnStd(after, w, x: 240, y0: 20, y1: 280)
        XCTAssertGreaterThan(inStd, outStd * 0.62, "heal 영역 그레인이 뭉개지면 안 된다(std \(inStd) vs \(outStd))")
        XCTAssertLessThan(inStd, outStd * 1.5, "heal 영역 노이즈 과다")
        // (c) 크로마 그레인 보존(채널 독립성).
        let inChroma = chromaStd(after, w, x0: 190, x1: 199, y0: 20, y1: 280)
        let outChroma = chromaStd(after, w, x0: 230, x1: 239, y0: 20, y1: 280)
        XCTAssertGreaterThan(inChroma, outChroma * 0.6, "heal 영역 크로마 그레인이 탈색되면 안 된다")
        // (d) 톤 연속(그라데이션 추종): 칠 안 컬럼 평균이 기준 그라데이션과 일치(소스는 30px+ 밖).
        for x in [190, 205, 210] {
            let m = columnMean(after, w, x: x, y0: 20, y1: 280)
            let r = columnMean(clean, w, x: x, y0: 20, y1: 280)
            XCTAssertLessThan(abs(m - r), 5, "heal 톤이 그라데이션을 따라야 한다(x=\(x): \(m) vs \(r))")
        }
        // (e) 칠 밖(페더 밖) 무변화.
        var outsideDiff = 0
        for y in 20..<280 { outsideDiff += abs(lum(after, w, 180, y) - lum(px, w, 180, y)) }
        XCTAssertLessThan(Double(outsideDiff) / 260, 1.0, "칠 밖은 변하면 안 된다")
    }

    /// 세로 스트로크를 가로지르는 어두운 가로 구조선: 직교(가로) 변위가 선을 자기 자신 위로
    /// 매핑해 보존한다 — heal 이 교차 구조를 끊지 않는지 확인.
    func testHealPreservesCrossingStructure() {
        let w = 400, h = 300
        var px = gradientGrainScene(w: w, h: h, amp: 6, seed: 0xC805)
        for y in 148...151 {                    // 가로 어두운 구조선
            for x in 0..<w {
                let o = (y * w + x) * 4
                let v = UInt8(max(0, Int(px[o]) - 70))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
        let clean = px
        for y in 0..<h {                        // 세로 스크래치
            for x in 200...201 {
                let o = (y * w + x) * 4
                let v = UInt8(min(255, Int(px[o]) + 55))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
        let img = ci(px, w, h)
        let brush = band(w: w, h: h, x0: 188, x1: 213)
        guard let out = DefectHealBrush.heal(to: img, brush: brush,
                                          repairExtent: CGRect(x: 0, y: 0, width: w, height: h),
                                          preferredAngle: 90, strength: 1.0) else {
            return XCTFail("heal 이 유효 소스를 찾지 못함")
        }
        let after = render(out, w, h)
        // 교차선이 칠 안에서도 어두운 선으로 이어져야 한다(±25).
        for x in [192, 200, 208] {
            let crossing = lum(after, w, x, 149)
            let reference = lum(clean, w, x, 149)
            XCTAssertLessThan(abs(crossing - reference), 25,
                              "교차 구조선이 heal 로 끊기면 안 된다(x=\(x): \(crossing) vs \(reference))")
        }
    }

    /// 강도 0.5: 결함 잔존이 절반 수준(블렌드 비례).
    func testHealStrengthScalesBlend() {
        let w = 300, h = 200
        var px = gradientGrainScene(w: w, h: h, amp: 5, seed: 0x51)
        let clean = px
        for y in 0..<h {
            for x in 150...151 {
                let o = (y * w + x) * 4
                let v = UInt8(min(255, Int(px[o]) + 56))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
        let img = ci(px, w, h)
        let brush = band(w: w, h: h, x0: 140, x1: 162)
        guard let out = DefectHealBrush.heal(to: img, brush: brush,
                                          repairExtent: CGRect(x: 0, y: 0, width: w, height: h),
                                          preferredAngle: 90, strength: 0.5) else {
            return XCTFail("heal 이 유효 소스를 찾지 못함")
        }
        let after = render(out, w, h)
        let residual = columnMean(after, w, x: 150, y0: 10, y1: 190)
            - columnMean(clean, w, x: 150, y0: 10, y1: 190)
        XCTAssertGreaterThan(residual, 15, "50%는 결함이 절반쯤 남아야 한다(residual \(residual))")
        XCTAssertLessThan(residual, 45, "50%가 100%처럼 다 지우면 안 된다(residual \(residual))")
    }

    /// 칠이 이미지 전체를 덮으면(유효 소스 없음) nil — 호출측 검출 기반 폴백 계약.
    func testHealReturnsNilWithoutValidSource() {
        let w = 200, h = 150
        let px = gradientGrainScene(w: w, h: h, amp: 5, seed: 0x99)
        let img = ci(px, w, h)
        let brush = band(w: w, h: h, x0: 0, x1: w)
        XCTAssertNil(DefectHealBrush.heal(to: img, brush: brush,
                                       repairExtent: CGRect(x: 0, y: 0, width: w, height: h),
                                       preferredAngle: 90, strength: 1.0),
                     "유효 소스가 없으면 nil 로 폴백을 알려야 한다")
    }
}
