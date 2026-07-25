import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// 자동(전체 프레임) 모드의 가로/세로/대각 스크래치 검출률 회귀 가드 — 합성 픽셀 전용.
//
// 자동에만 켜지는 구조선 배제(gridLineDrops)는 "주변에 선이 많다"는 이유로 스크래치를 버렸다.
// 실사진에는 잔선이 늘 있으므로 자동에서만 스크래치가 대량 누락됐다(가이드는 이 배제를 쓰지 않아
// 잘 잡혔다). 이제 구조 텍스처 표는 **길이가 비슷한 선**끼리만 던지므로, 주변 잔선보다 훨씬 긴
// 스크래치는 살아남는다. 격자·규칙 반복 구조 배제는 그대로다(DefectLineGridRejectionTests).
//
// 한계: 저대비로 짧게 끊긴 조각이 주변 잔선과 길이까지 비슷하면 여전히 구조로 몰릴 수 있다 —
// 그 경우는 가이드로 범위를 지정하는 쪽이 확실하다.
final class AutomaticScratchRecallTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    /// 완만한 톤 + 약한 그레인 배경(결함 없는 상태).
    private func background(_ w: Int, _ h: Int) -> [UInt8] {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        var state: UInt64 = 0x9E3779B97F4A7C15
        for y in 0..<h {
            for x in 0..<w {
                state ^= state << 13; state ^= state >> 7; state ^= state << 17
                let grain = Double(state % 1_000) / 1_000.0 - 0.5
                let base = 120.0 + 40.0 * Double(y) / Double(h) + grain * 8.0
                let value = UInt8(max(0, min(255, base)))
                let o = (y * w + x) * 4
                px[o] = value; px[o + 1] = value; px[o + 2] = value
            }
        }
        return px
    }

    /// (dx,dy) 방향 얇은 선을 그리고 그 픽셀 좌표를 돌려준다.
    @discardableResult
    private func drawLine(_ px: inout [UInt8], _ w: Int, _ h: Int,
                          x0: Int, y0: Int, dx: Int, dy: Int, length: Int,
                          value: Int) -> [(Int, Int)] {
        var points: [(Int, Int)] = []
        for t in 0..<length {
            let x = x0 + dx * t, y = y0 + dy * t
            guard x >= 0, y >= 0, x < w, y < h else { continue }
            let o = (y * w + x) * 4
            px[o] = UInt8(value); px[o + 1] = UInt8(value); px[o + 2] = UInt8(value)
            points.append((x, y))
        }
        return points
    }

    private func automaticField(_ px: [UInt8], _ w: Int, _ h: Int) -> DefectLabelField {
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 1.0,
                                              scratchSensitivity: 1.0, protectDetail: 0.6)
        return SoftwareDefectRemoval.detectComponents(
            in: makeRGBA8CIImage(px, w, h, colorSpace: linear),
            roi: CGRect(x: 0, y: 0, width: w, height: h),
            parameters: params,
            wholeFrameAuto: true
        )
    }

    /// 주어진 좌표들이 검출 마스크에 덮인 비율.
    private func coverage(_ field: DefectLabelField, _ w: Int, _ points: [(Int, Int)]) -> Double {
        guard !points.isEmpty else { return 0 }
        let mask = DefectComponentMask.renderMask(field, excluded: [],
                                                  maxHoleArea: field.width * field.height,
                                                  dustDilate: 2)
        var covered = 0
        for (x, y) in points where mask[(y * w + x) * 4] > 0 { covered += 1 }
        return Double(covered) / Double(points.count)
    }

    // MARK: 가로/세로/대각 고립 스크래치

    func testAutomaticDetectsHorizontalVerticalAndDiagonalScratches() {
        let w = 1_100, h = 1_100
        var px = background(w, h)
        let horizontal = drawLine(&px, w, h, x0: 120, y0: 200, dx: 1, dy: 0, length: 620, value: 70)
        let vertical = drawLine(&px, w, h, x0: 880, y0: 150, dx: 0, dy: 1, length: 620, value: 70)
        let diagonal = drawLine(&px, w, h, x0: 200, y0: 420, dx: 1, dy: 1, length: 520, value: 70)

        let field = automaticField(px, w, h)

        for (name, points) in [("가로", horizontal), ("세로", vertical), ("대각", diagonal)] {
            let covered = coverage(field, w, points)
            XCTAssertGreaterThan(covered, 0.6,
                                 "\(name) 스크래치가 자동에서 검출되어야 한다 (커버 \(Int(covered * 100))%)")
        }
    }

    // MARK: 주변 잔선이 있을 때 — 구조선 배제가 실제로 도는 조건

    /// 실사진처럼 짧은 잔선이 깔린 프레임. 예전에는 이 잔선들 때문에 긴 스크래치(특히 대각)가
    /// 구조 텍스처로 몰려 자동에서만 버려졌다.
    func testAutomaticKeepsLongScratchesSurroundedByShortLineTexture() {
        let w = 1_100, h = 1_100
        var px = background(w, h)
        let horizontal = drawLine(&px, w, h, x0: 120, y0: 200, dx: 1, dy: 0, length: 620, value: 70)
        let vertical = drawLine(&px, w, h, x0: 880, y0: 150, dx: 0, dy: 1, length: 620, value: 70)
        let diagonal = drawLine(&px, w, h, x0: 200, y0: 420, dx: 1, dy: 1, length: 520, value: 70)
        // 짧은 잔선 텍스처(가로/대각 섞임) — 구조선 배제가 켜지는 최소 조건(선 8개 이상)을 넘긴다.
        for k in 0..<14 {
            drawLine(&px, w, h,
                     x0: 120 + (k % 7) * 120, y0: 820 + (k / 7) * 90,
                     dx: 1, dy: k.isMultiple(of: 2) ? 1 : 0, length: 60, value: 95)
        }

        let field = automaticField(px, w, h)

        for (name, points) in [("가로", horizontal), ("세로", vertical), ("대각", diagonal)] {
            let covered = coverage(field, w, points)
            XCTAssertGreaterThan(covered, 0.6,
                                 "잔선 텍스처가 있어도 \(name) 스크래치는 자동에서 살아야 한다 "
                                 + "(커버 \(Int(covered * 100))%)")
        }
    }
}
