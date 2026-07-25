import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// 격자/규칙 선 구조(보도블럭·벽돌·창틀) 스크래치 오검출 배제 검증 — 합성 픽셀 전용.
//
// 전역 자동 검출(ROI = 전체 프레임)에서만 격자 배제가 켜진다. 검증 축:
//  ① 직교 두 방향 선 격자 → 스크래치 컴포넌트 배제(오검출 제거).
//  ② 고립 단일 스크래치 → 보존.
//  ③ 평행 다발 스크래치(직교 선 없음, 이송 스크래치) → 보존.
//  ④ 가이드(부분 ROI)에서는 격자 배제 미적용(사용자 지목 결함 보존).
final class DefectLineGridRejectionTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    private func gray(_ w: Int, _ h: Int, _ base: Int) -> [UInt8] {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            let o = i * 4; px[o] = UInt8(base); px[o + 1] = UInt8(base); px[o + 2] = UInt8(base)
        }
        return px
    }

    private func hLine(_ px: inout [UInt8], _ w: Int, y: Int, x0: Int, x1: Int, v: Int) {
        for x in x0..<x1 {
            let o = (y * w + x) * 4
            px[o] = UInt8(v); px[o + 1] = UInt8(v); px[o + 2] = UInt8(v)
        }
    }

    private func vLine(_ px: inout [UInt8], _ w: Int, x: Int, y0: Int, y1: Int, v: Int) {
        for y in y0..<y1 {
            let o = (y * w + x) * 4
            px[o] = UInt8(v); px[o + 1] = UInt8(v); px[o + 2] = UInt8(v)
        }
    }

    private func detect(_ px: [UInt8], _ w: Int, _ h: Int, roi: CGRect) -> DefectLabelField {
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        return SoftwareDefectRemoval.detectComponents(
            in: makeRGBA8CIImage(px, w, h, colorSpace: linear), roi: roi, parameters: params)
    }

    private func scratchCount(_ f: DefectLabelField) -> Int {
        f.components.filter { $0.kind == .scratch }.count
    }

    // MARK: ① 격자 배제

    func testPaverGridRejectedInFullFrameAuto() {
        // 균일 배경 위 직교 격자(어두운 홈): 가로 6줄 + 세로 6줄. 전부 구조물이라 스크래치 0이어야.
        let w = 480, h = 480, base = 150, groove = 90
        var px = gray(w, h, base)
        for k in 1...6 { hLine(&px, w, y: k * 64, x0: 20, x1: 460, v: groove) }
        for k in 1...6 { vLine(&px, w, x: k * 64, y0: 20, y1: 460, v: groove) }

        let field = detect(px, w, h, roi: CGRect(x: 0, y: 0, width: w, height: h))
        XCTAssertLessThanOrEqual(scratchCount(field), 2,
                                 "격자 구조는 스크래치로 검출되지 않아야 함 (\(scratchCount(field))개 남음)")
    }

    // MARK: ② 고립 스크래치 보존

    func testIsolatedScratchPreservedInFullFrameAuto() {
        let w = 480, h = 480, base = 150
        var px = gray(w, h, base)
        // 대각 얇은 스크래치 하나(고립).
        for t in 40..<300 {
            let o = ((80 + t) * w + (60 + t)) * 4
            px[o] = 90; px[o + 1] = 90; px[o + 2] = 90
        }
        let field = detect(px, w, h, roi: CGRect(x: 0, y: 0, width: w, height: h))
        XCTAssertGreaterThanOrEqual(scratchCount(field), 1, "고립 스크래치는 보존되어야 함")
    }

    // MARK: ③ 소수 평행 다발(이송 스크래치) 보존 / 규칙 반복 필드 배제

    func testSmallParallelBundlePreservedButRegularFieldRejected() {
        // 소수(3줄) 평행 다발 — 이송 스크래치. 규칙 필드 임계 미만이라 보존.
        let w = 480, h = 480, base = 150, groove = 95
        var small = gray(w, h, base)
        for k in 0..<3 { vLine(&small, w, x: 120 + k * 60, y0: 40, y1: 440, v: groove) }
        let smallField = detect(small, w, h, roi: CGRect(x: 0, y: 0, width: w, height: h))
        XCTAssertGreaterThanOrEqual(scratchCount(smallField), 2,
                                    "소수 평행 다발은 보존 (\(scratchCount(smallField))개)")

        // 규칙적으로 반복되는 평행선 다수(세로 10줄) — 보도블럭/블라인드 류 구조물 → 배제.
        var dense = gray(w, h, base)
        for k in 0..<10 { vLine(&dense, w, x: 40 + k * 42, y0: 40, y1: 440, v: groove) }
        let denseField = detect(dense, w, h, roi: CGRect(x: 0, y: 0, width: w, height: h))
        XCTAssertLessThanOrEqual(scratchCount(denseField), 2,
                                 "규칙 반복 평행선 필드는 배제 (\(scratchCount(denseField))개 남음)")
    }

    // MARK: ④ gridLineDrops 순수 함수 — 격자만 기각, 고립·평행은 보존

    /// 픽셀 리스트로 RawComponent 를 만든다(라벨맵 인덱스 = y*width + x).
    private func line(_ w: Int, x0: Int, y0: Int, dx: Int, dy: Int, len: Int) -> DefectComponentMask.RawComponent {
        var pixels: [Int] = []
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for t in 0..<len {
            let x = x0 + dx * t, y = y0 + dy * t
            pixels.append(y * w + x)
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
        return DefectComponentMask.RawComponent(pixels: pixels, minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    func testGridLineDropsRejectsLatticeKeepsIsolatedAndParallel() {
        let w = 480, h = 480
        // 직교 격자: 가로 5 + 세로 5.
        var grid: [DefectComponentMask.RawComponent] = []
        for k in 0..<5 { grid.append(line(w, x0: 40, y0: 60 + k * 70, dx: 1, dy: 0, len: 380)) }
        for k in 0..<5 { grid.append(line(w, x0: 60 + k * 70, y0: 40, dx: 0, dy: 1, len: 380)) }
        let gridDrop = DefectComponentMask.gridLineDrops(scratch: grid, width: w, height: h)
        XCTAssertGreaterThanOrEqual(gridDrop.count, 8, "격자 선 대부분 기각 (\(gridDrop.count)/10)")

        // 규칙 반복 평행 필드(세로 8줄, 직교 없음) → 규칙 필드 규칙으로 기각.
        var dense: [DefectComponentMask.RawComponent] = []
        for k in 0..<8 { dense.append(line(w, x0: 60 + k * 45, y0: 40, dx: 0, dy: 1, len: 380)) }
        XCTAssertGreaterThanOrEqual(DefectComponentMask.gridLineDrops(scratch: dense, width: w, height: h).count, 6,
                                    "규칙 반복 평행 필드는 기각")

        // 대각 규칙 반복 필드(평행 대각 8줄, 화면 안) → 기각.
        var diagonal: [DefectComponentMask.RawComponent] = []
        for k in 0..<8 { diagonal.append(line(w, x0: 20 + k * 30, y0: 20, dx: 1, dy: 1, len: 160)) }
        XCTAssertGreaterThanOrEqual(DefectComponentMask.gridLineDrops(scratch: diagonal, width: w, height: h).count, 6,
                                    "대각 규칙 반복 필드는 기각")

        // 소수 평행 다발(세로 3줄) — 규칙 필드 미만 → 기각 0(이송 스크래치 보존).
        var few: [DefectComponentMask.RawComponent] = []
        for k in 0..<3 { few.append(line(w, x0: 120 + k * 60, y0: 40, dx: 0, dy: 1, len: 380)) }
        XCTAssertEqual(DefectComponentMask.gridLineDrops(scratch: few, width: w, height: h).count, 0,
                       "소수 평행 다발은 보존")

        // 고립 단일 스크래치 → 기각 0.
        let isolated = [line(w, x0: 60, y0: 80, dx: 1, dy: 1, len: 300)]
        XCTAssertEqual(DefectComponentMask.gridLineDrops(scratch: isolated, width: w, height: h).count, 0,
                       "고립 스크래치는 보존")

        // 단일 X 교차(2선) → 격자·필드 아님, 기각 0.
        let cross = [line(w, x0: 40, y0: 240, dx: 1, dy: 0, len: 380),
                     line(w, x0: 240, y0: 40, dx: 0, dy: 1, len: 380)]
        XCTAssertEqual(DefectComponentMask.gridLineDrops(scratch: cross, width: w, height: h).count, 0,
                       "단일 X 교차는 보존")
    }
}
