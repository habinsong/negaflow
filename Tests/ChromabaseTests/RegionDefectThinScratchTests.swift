import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// 매우 얇은 스크래치(대각선·초저대비 장선) 검출 회귀 가드.
//
//  1) 대각선: 스크래치 형태 게이트가 축 정렬 bbox aspect 만 쓰면 45° 얇은 선의 bbox 가
//     정사각형(aspect≈1)이라 대비와 무관하게 기각된다 — 회전 불변 신장도(LSD 의 임의 각도
//     직사각형 근사와 같은 정신)로 판정해야 한다.
//  2) 초저대비 장선: strong 코어가 없는 균일 weak 레벨 스크래치도, 충분히 길고 가늘면
//     기하 증거만으로 채택한다(LSD/a-contrario NFA: 정렬 픽셀이 L px 연결될 확률은 L 에
//     지수적으로 감소). 짧은 weak-only 는 그레인과 구분 불가라 기존대로 기각한다.
final class RegionDefectThinScratchTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private func ci(_ px: [UInt8], _ w: Int, _ h: Int) -> CIImage {
        CIImage(bitmapData: Data(px), bytesPerRow: w * 4,
                size: CGSize(width: w, height: h), format: .RGBA8, colorSpace: linear)
    }
    private func render(_ img: CIImage, _ w: Int, _ h: Int) -> [UInt8] {
        var o = [UInt8](repeating: 0, count: w * h * 4)
        CIContext(options: [.workingColorSpace: linear]).render(
            img, toBitmap: &o, rowBytes: w * 4,
            bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8, colorSpace: linear)
        return o
    }
    private func lum(_ a: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> Int { Int(a[(y * w + x) * 4]) }
    private func bg(_ w: Int, _ h: Int, _ v: Int) -> [UInt8] {
        var p = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) { let o = i * 4; p[o] = UInt8(v); p[o + 1] = UInt8(v); p[o + 2] = UInt8(v) }
        return p
    }
    private let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 1.0,
                                               scratchSensitivity: 1.0, protectDetail: 0.6)

    /// 시작점에서 (dx,dy) 단위 방향으로 length 픽셀의 얇은 선을 그린다(Bresenham 정신).
    private func drawLine(_ px: inout [UInt8], w: Int, h: Int, x0: Double, y0: Double,
                          dx: Double, dy: Double, length: Int, delta: Int) -> [(Int, Int)] {
        var pts: [(Int, Int)] = []
        var seen = Set<Int>()
        for t in 0..<length {
            let x = Int((x0 + dx * Double(t)).rounded())
            let y = Int((y0 + dy * Double(t)).rounded())
            guard x >= 0, y >= 0, x < w, y < h, seen.insert(y * 100000 + x).inserted else { continue }
            let o = (y * w + x) * 4
            let v = UInt8(max(0, min(255, Int(px[o]) + delta)))
            px[o] = v; px[o + 1] = v; px[o + 2] = v
            pts.append((x, y))
        }
        return pts
    }

    private func detectAndMeasure(_ px: [UInt8], w: Int, h: Int,
                                  defect: [(Int, Int)]) -> (coverage: Double, comps: Int, out: [UInt8]) {
        let img = ci(px, w, h)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let field = SoftwareDefectRemoval.detectComponents(in: img, roi: roi, parameters: params)
        let mask = DefectComponentMask.renderMask(field, excluded: [], maxHoleArea: w * h, dustDilate: 2)
        var covered = 0
        for (x, y) in defect where mask[(y * w + x) * 4] > 0 { covered += 1 }
        let coverage = defect.isEmpty ? 0 : Double(covered) / Double(defect.count)
        let out = render(SoftwareDefectRemoval.repair(image: img, roi: roi, mask: ci(mask, w, h)), w, h)
        return (coverage, field.components.count, out)
    }

    // 1) 저대비 45° 대각선 얇은 스크래치: dust 경로 임계(0.06 gamma) 아래라 ridge 경로만 후보를
    //    내는 대비인데, bbox aspect 게이트가 대각선을 기각하면 완전히 미검출된다.
    func testFaintDiagonal45ThinScratchDetected() {
        let w = 240, h = 240, base = 120, delta = 16
        var px = bg(w, h, base)
        let pts = drawLine(&px, w: w, h: h, x0: 40, y0: 40,
                           dx: 0.7071, dy: 0.7071, length: 230, delta: delta)
        let (coverage, comps, out) = detectAndMeasure(px, w: w, h: h, defect: pts)
        var resid = 0
        for (x, y) in pts { resid += abs(lum(out, w, x, y) - base) }
        let avgResid = Double(resid) / Double(pts.count)
        print(String(format: "[diag45] coverage=%.0f%% comps=%d residual=%.1f (delta=%d)",
                     coverage * 100, comps, avgResid, delta))
        XCTAssertGreaterThanOrEqual(coverage, 0.6, "저대비 45° 얇은 스크래치가 검출되어야 한다(대각선 기각 회귀)")
        XCTAssertLessThan(avgResid, 8.0, "검출된 대각선 스크래치는 복원으로 제거되어야 한다")
    }

    // 2) 저대비 30°(축에서 벗어난) 대각선 — bbox aspect ≈ tan 게이트 경계 바깥의 각도.
    func testFaintDiagonal30ThinScratchDetected() {
        let w = 240, h = 240, base = 120, delta = 16
        var px = bg(w, h, base)
        // 수직에서 30° 기울어진 선: (dx, dy) = (sin30, cos30)
        let pts = drawLine(&px, w: w, h: h, x0: 70, y0: 30,
                           dx: 0.5, dy: 0.866, length: 220, delta: delta)
        let (coverage, comps, out) = detectAndMeasure(px, w: w, h: h, defect: pts)
        var resid = 0
        for (x, y) in pts { resid += abs(lum(out, w, x, y) - base) }
        let avgResid = Double(resid) / Double(pts.count)
        print(String(format: "[diag30] coverage=%.0f%% comps=%d residual=%.1f (delta=%d)",
                     coverage * 100, comps, avgResid, delta))
        XCTAssertGreaterThanOrEqual(coverage, 0.6, "저대비 30° 얇은 스크래치가 검출되어야 한다")
        XCTAssertLessThan(avgResid, 8.0, "검출된 30° 스크래치는 복원으로 제거되어야 한다")
    }

    // 3) strong 코어가 전혀 없는 초저대비(균일 weak 레벨) "매우 길고 가는" 스크래치:
    //    길이·가늘기 기하 증거로 채택되어야 한다(사용자 요구 — 매우매우 얇고 긴 스크래치).
    func testUniformVeryFaintLongThinScratchDetected() {
        let w = 240, h = 240, base = 120, delta = 6   // gamma ≈0.015 — strong(0.020) 미만, weak(0.010) 초과
        var px = bg(w, h, base)
        let pts = drawLine(&px, w: w, h: h, x0: 120, y0: 30, dx: 0, dy: 1, length: 180, delta: delta)
        let (coverage, comps, _) = detectAndMeasure(px, w: w, h: h, defect: pts)
        print(String(format: "[weak-long] coverage=%.0f%% comps=%d (delta=%d)", coverage * 100, comps, delta))
        XCTAssertGreaterThanOrEqual(coverage, 0.6, "매우 길고 가는 초저대비 스크래치는 기하 증거로 검출되어야 한다")
    }

    // 4) 그레인 안전 경계 유지: 같은 초저대비라도 "짧은" weak-only 선(40px)은 그레인과 구분
    //    불가하므로 여전히 기각되어야 한다(길이만이 안전한 증거).
    func testShortWeakOnlyLineStillRejected() {
        let w = 240, h = 240, base = 120, delta = 6
        var px = bg(w, h, base)
        let pts = drawLine(&px, w: w, h: h, x0: 120, y0: 100, dx: 0, dy: 1, length: 40, delta: delta)
        let (coverage, comps, _) = detectAndMeasure(px, w: w, h: h, defect: pts)
        print(String(format: "[weak-short] coverage=%.0f%% comps=%d (delta=%d)", coverage * 100, comps, delta))
        XCTAssertLessThan(coverage, 0.3, "짧은 weak-only 선은 그레인 안전을 위해 여전히 기각되어야 한다")
    }
}
