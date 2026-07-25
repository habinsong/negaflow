import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// 복잡한 구조물(건물 창문 격자, 도로선/파이프 같은 긴 띠, 고리형 결함의 내부)이 결함으로
// 오탐·와이프되지 않는지 검증한다. 가드는 구조적(farTexture 컨텍스트 게이트, 두께 상한,
// hole-fill 컴포넌트 비례 상한)이며 검출 임계·SNR 배수는 불변 — 같은 파일의 recall 테스트
// (RegionDefectHardCases/FaintDefect/ThinScratch)가 저대비 결함 제거 보존을 함께 보증한다.
final class RegionDefectStructureFPTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private func ci(_ px: [UInt8], _ w: Int, _ h: Int) -> CIImage {
        CIImage(bitmapData: Data(px), bytesPerRow: w * 4,
                size: CGSize(width: w, height: h), format: .RGBA8, colorSpace: linear)
    }
    private func bg(_ w: Int, _ h: Int, _ v: Int) -> [UInt8] {
        var p = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) { let o = i * 4; p[o] = UInt8(v); p[o + 1] = UInt8(v); p[o + 2] = UInt8(v) }
        return p
    }
    private func paint(_ px: inout [UInt8], _ w: Int, _ h: Int, _ x: Int, _ y: Int, _ v: Int) {
        guard x >= 0, y >= 0, x < w, y < h else { return }
        let o = (y * w + x) * 4; px[o] = UInt8(v); px[o + 1] = UInt8(v); px[o + 2] = UInt8(v)
    }
    private func coverage(_ mask: [UInt8], _ w: Int, _ pts: [(Int, Int)]) -> Double {
        guard !pts.isEmpty else { return 0 }
        var c = 0
        for (x, y) in pts where mask[(y * w + x) * 4] > 0 { c += 1 }
        return Double(c) / Double(pts.count)
    }

    // 1) 건물 파사드: 어두운 창문 격자(고대비 컴팩트 blob 반복). 각 창문은 strongMag 절대 면제
    //    후보였다 — farTexture 컨텍스트 게이트가 격자(주변에 비슷한 구조 반복)를 기각해야 한다.
    func testFacadeWindowGridNotMassDetected() {
        let w = 360, h = 360, wall = 150, window = 60
        var px = bg(w, h, wall)
        var windowPts: [(Int, Int)] = []
        for gy in stride(from: 30, to: h - 30, by: 36) {
            for gx in stride(from: 30, to: w - 30, by: 36) {
                for y in gy..<(gy + 18) { for x in gx..<(gx + 14) {
                    paint(&px, w, h, x, y, window); windowPts.append((x, y))
                } }
            }
        }
        let img = ci(px, w, h)
        // 슬라이더 상단(민감)에서도 격자가 대량 오탐되면 안 된다.
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 1.0,
                                           scratchSensitivity: 1.0, protectDetail: 0.6)
        let field = SoftwareDefectRemoval.detectComponents(in: img, roi: CGRect(x: 0, y: 0, width: w, height: h),
                                                 parameters: params)
        let mask = DefectComponentMask.renderMask(field, excluded: [], maxHoleArea: w * h, dustDilate: 2)
        let cov = coverage(mask, w, windowPts)
        print(String(format: "[facade] window coverage=%.1f%% comps=%d", cov * 100, field.components.count))
        XCTAssertLessThan(cov, 0.10, "창문 격자가 먼지로 대량 오탐되면 안 된다(커버 \(Int(cov * 100))%)")
    }

    // 2) 긴 고대비 띠(도로 차선/파이프/난간, 폭 16px): top-hat SE(≤12)에 걸리는 폭이라 절대 면제
    //    후보였다 — 띠는 far 박스를 관통해 farTexture 를 스스로 끌어올리므로 컨텍스트 게이트가
    //    기각하고, 두께(16 > 스크래치 상한 12) 게이트가 스크래치 편입도 막아야 한다.
    func testLongThickBandNotDetected() {
        let w = 360, h = 360, base = 120
        var px = bg(w, h, base)
        var bandPts: [(Int, Int)] = []
        for y in 0..<h { for x in 172..<188 { paint(&px, w, h, x, y, 235); bandPts.append((x, y)) } }
        let img = ci(px, w, h)
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 1.0,
                                           scratchSensitivity: 1.0, protectDetail: 0.6)
        let field = SoftwareDefectRemoval.detectComponents(in: img, roi: CGRect(x: 0, y: 0, width: w, height: h),
                                                 parameters: params)
        let mask = DefectComponentMask.renderMask(field, excluded: [], maxHoleArea: w * h, dustDilate: 2)
        let cov = coverage(mask, w, bandPts)
        print(String(format: "[band16] coverage=%.1f%% comps=%d", cov * 100, field.components.count))
        XCTAssertLessThan(cov, 0.10, "폭 16px 긴 구조 띠가 결함으로 오탐되면 안 된다(커버 \(Int(cov * 100))%)")
    }

    func testPartialROILongThickBandNotDetectedByLargeDustPath() {
        let w = 400, h = 400, base = 120
        var px = bg(w, h, base)
        for y in 20..<380 {
            for x in 192..<208 { paint(&px, w, h, x, y, 235) }
        }
        let img = ci(px, w, h)
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 1.0,
                                           scratchSensitivity: 1.0, protectDetail: 0.6)
        let roi = CGRect(x: 20, y: 20, width: 360, height: 360)
        let field = SoftwareDefectRemoval.detectComponents(in: img, roi: roi, parameters: params)
        let mask = DefectComponentMask.renderMask(field, excluded: [], maxHoleArea: 360 * 360, dustDilate: 2)
        var bandPoints: [(Int, Int)] = []
        for y in 0..<360 {
            for x in 172..<188 { bandPoints.append((x, y)) }
        }
        XCTAssertLessThan(
            coverage(mask, 360, bandPoints),
            0.10,
            "부분 ROI의 대형 먼지 경로가 정상 구조 띠를 오검출하면 안 됩니다."
        )
    }

    // 3) 고리(루프) 모양 가는 결함: 고리 자체는 검출·제거하되, 고리 안 정상 이미지는 hole-fill 로
    //    채워져 와이프되면 안 된다(컴포넌트 크기 비례 hole 상한).
    func testHairLoopInteriorPreserved() {
        let w = 240, h = 240, base = 120, cx = 120, cy = 120
        var px = bg(w, h, base)
        var ringPts: [(Int, Int)] = []
        for y in 0..<h {
            for x in 0..<w {
                let dd = Double((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot()
                if dd >= 29, dd <= 31 { paint(&px, w, h, x, y, 245); ringPts.append((x, y)) }
            }
        }
        let img = ci(px, w, h)
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 1.0,
                                           scratchSensitivity: 1.0, protectDetail: 0.6)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let field = SoftwareDefectRemoval.detectComponents(in: img, roi: roi, parameters: params)
        let mask = DefectComponentMask.renderMask(field, excluded: [], maxHoleArea: w * h, dustDilate: 2)
        let ringCov = coverage(mask, w, ringPts)
        // 고리 내부(중앙 20×20)는 마스크가 비어 있어야 한다 — 채워지면 정상 이미지 와이프.
        var interior: [(Int, Int)] = []
        for y in (cy - 10)..<(cy + 10) { for x in (cx - 10)..<(cx + 10) { interior.append((x, y)) } }
        let interiorCov = coverage(mask, w, interior)
        print(String(format: "[loop] ring coverage=%.0f%% interior=%.0f%% comps=%d",
                     ringCov * 100, interiorCov * 100, field.components.count))
        XCTAssertGreaterThanOrEqual(ringCov, 0.7, "고리 결함 자체는 검출돼야 한다")
        XCTAssertLessThan(interiorCov, 0.05, "고리 내부 정상 이미지가 hole-fill 로 와이프되면 안 된다")
    }
}
