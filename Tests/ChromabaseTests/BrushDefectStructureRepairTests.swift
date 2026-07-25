import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class BrushDefectStructureRepairTests: XCTestCase {
    private let cs = CGColorSpace(name: CGColorSpace.sRGB)!

    private func ciImage(_ px: [UInt8], _ w: Int, _ h: Int) -> CIImage {
        makeRGBA8CIImage(px, w, h, colorSpace: cs)
    }

    private func render(_ img: CIImage, _ w: Int, _ h: Int) -> [UInt8] {
        renderRGBA8Pixels(img, w, h, colorSpace: cs)
    }

    private func lum(_ a: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> Int {
        Int(a[(y * w + x) * 4])
    }

    private func scene(w: Int, h: Int, bg: Int, line: Int,
                       grainA: Int, grainB: Int,
                       isLine: (Int, Int) -> Bool) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let grain = ((x * grainA + y * grainB) % 11) - 5
                let v = (isLine(x, y) ? line : bg) + grain
                let o = (y * w + x) * 4
                let u = UInt8(max(0, min(255, v)))
                px[o] = u
                px[o + 1] = u
                px[o + 2] = u
                px[o + 3] = 255
            }
        }
        return px
    }

    private func fill(_ px: inout [UInt8], w: Int, xs: ClosedRange<Int>, ys: ClosedRange<Int>, value: UInt8) {
        for y in ys {
            for x in xs {
                let o = (y * w + x) * 4
                px[o] = value
                px[o + 1] = value
                px[o + 2] = value
            }
        }
    }

    private func ellipseMask(w: Int, h: Int, cx: Int, cy: Int, rx: Double, ry: Double) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in max(0, cy - Int(ry.rounded()) - 1)...min(h - 1, cy + Int(ry.rounded()) + 1) {
            for x in max(0, cx - Int(rx.rounded()) - 1)...min(w - 1, cx + Int(rx.rounded()) + 1) {
                let dx = Double(x - cx) / rx
                let dy = Double(y - cy) / ry
                if dx * dx + dy * dy <= 1.0 {
                    let o = (y * w + x) * 4
                    px[o] = 255
                    px[o + 1] = 255
                    px[o + 2] = 255
                    px[o + 3] = 255
                }
            }
        }
        return px
    }

    private func diagonalMask(w: Int, h: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 58...162 {
            for x in 58...162 {
                let along = Double((x - 110) + (y - 110)) / 74.0
                let cross = Double((x - 110) - (y - 110)) / 16.0
                if along * along + cross * cross <= 1.0 {
                    let o = (y * w + x) * 4
                    px[o] = 255
                    px[o + 1] = 255
                    px[o + 2] = 255
                    px[o + 3] = 255
                }
            }
        }
        return px
    }

    func testBrushDefectDoesNotSmoothWideHorizontalBrushTextureAndLineStructure() {
        let w = 260, h = 140
        let clean = scene(w: w, h: h, bg: 166, line: 58, grainA: 37, grainB: 19) { _, y in
            abs(y - 70) <= 1
        }
        var damaged = clean
        fill(&damaged, w: w, xs: 112...148, ys: 66...74, value: 238)

        let repaired = render(
            SoftwareDefectRemoval.repair(
                image: ciImage(damaged, w, h),
                roi: CGRect(x: 0, y: 0, width: w, height: h),
                mask: ciImage(ellipseMask(w: w, h: h, cx: 130, cy: 70, rx: 54, ry: 13), w, h),
                preferredAngle: 0
            ),
            w, h
        )

        var lineErr = 0
        var lineCount = 0
        var offLineErr = 0
        var offLineCount = 0
        for x in 92...168 {
            lineErr += abs(lum(repaired, w, x, 70) - lum(clean, w, x, 70))
            lineCount += 1
            offLineErr += abs(lum(repaired, w, x, 64) - lum(clean, w, x, 64))
            offLineErr += abs(lum(repaired, w, x, 76) - lum(clean, w, x, 76))
            offLineCount += 2
        }
        let avgLineErr = Double(lineErr) / Double(lineCount)
        let avgOffLineErr = Double(offLineErr) / Double(offLineCount)
        let centerLine = lum(repaired, w, 130, 70)
        let centerUpper = lum(repaired, w, 130, 64)
        print(String(format: "[wide-horizontal] lineErr=%.1f offLineErr=%.1f centerLine=%d centerUpper=%d",
                     avgLineErr, avgOffLineErr, centerLine, centerUpper))
        XCTAssertLessThan(avgLineErr, 28.0, "브러시와 같은 방향의 구조선이 상하 평균으로 지워지면 안 된다")
        XCTAssertLessThan(avgOffLineErr, 32.0, "브러시 내부 배경도 주변 질감과 너무 달라지면 안 된다")
        XCTAssertLessThan(centerLine, centerUpper - 45, "중앙 구조선 대비가 유지되어야 한다")
    }

    func testBrushDefectPreservesVerticalAndDiagonalStructure() {
        assertVerticalBrushStructure()
        assertDiagonalBrushStructure()
    }

    private func assertVerticalBrushStructure() {
        let w = 140, h = 260
        let clean = scene(w: w, h: h, bg: 164, line: 56, grainA: 29, grainB: 41) { x, _ in
            abs(x - 70) <= 1
        }
        var damaged = clean
        fill(&damaged, w: w, xs: 66...74, ys: 112...148, value: 236)
        let repaired = render(
            SoftwareDefectRemoval.repair(
                image: ciImage(damaged, w, h),
                roi: CGRect(x: 0, y: 0, width: w, height: h),
                mask: ciImage(ellipseMask(w: w, h: h, cx: 70, cy: 130, rx: 13, ry: 54), w, h),
                preferredAngle: 90
            ),
            w, h
        )
        var lineErr = 0
        var count = 0
        for y in 92...168 {
            lineErr += abs(lum(repaired, w, 70, y) - lum(clean, w, 70, y))
            count += 1
        }
        let avgLineErr = Double(lineErr) / Double(count)
        let centerLine = lum(repaired, w, 70, 130)
        let centerSide = lum(repaired, w, 64, 130)
        print(String(format: "[wide-vertical] lineErr=%.1f centerLine=%d centerSide=%d",
                     avgLineErr, centerLine, centerSide))
        XCTAssertLessThan(avgLineErr, 28.0, "세로 브러시와 같은 방향의 구조선이 좌우 평균으로 지워지면 안 된다")
        XCTAssertLessThan(centerLine, centerSide - 45, "세로 구조선 대비가 유지되어야 한다")
    }

    private func assertDiagonalBrushStructure() {
        let w = 220, h = 220
        let clean = scene(w: w, h: h, bg: 164, line: 58, grainA: 31, grainB: 17) { x, y in
            abs(x - y) <= 1
        }
        var damaged = clean
        for y in 92...128 {
            for x in 92...128 where abs(x - y) <= 5 {
                let o = (y * w + x) * 4
                damaged[o] = 238
                damaged[o + 1] = 238
                damaged[o + 2] = 238
            }
        }
        let repaired = render(
            SoftwareDefectRemoval.repair(
                image: ciImage(damaged, w, h),
                roi: CGRect(x: 0, y: 0, width: w, height: h),
                mask: ciImage(diagonalMask(w: w, h: h), w, h),
                preferredAngle: 45
            ),
            w, h
        )
        var lineErr = 0
        var count = 0
        for t in 72...148 {
            lineErr += abs(lum(repaired, w, t, t) - lum(clean, w, t, t))
            count += 1
        }
        let avgLineErr = Double(lineErr) / Double(count)
        let centerLine = lum(repaired, w, 110, 110)
        let centerSide = lum(repaired, w, 103, 117)
        print(String(format: "[wide-diagonal] lineErr=%.1f centerLine=%d centerSide=%d",
                     avgLineErr, centerLine, centerSide))
        XCTAssertLessThan(avgLineErr, 34.0, "대각 브러시와 같은 방향의 구조선이 대각 주변 평균으로 지워지면 안 된다")
        XCTAssertLessThan(centerLine, centerSide - 42, "대각 구조선 대비가 유지되어야 한다")
    }
}
