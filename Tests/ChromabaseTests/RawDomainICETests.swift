import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// raw 스캔 도메인(linearSRGB)에서 브러시 ICE 가 결함을 제거하는지 검증한다.
// 사용자는 현상된 positive 에서 칠하지만 실제 적용은 raw 에 일어나므로(raw 단계 ICE),
// 선형 도메인에서, 그리고 네거티브에서 결함이 밝게/어둡게 나타나는 양극성 모두에서
// 검출·복원이 동작해야 한다.
final class RawDomainICETests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    private func ciImage(_ px: [UInt8], _ w: Int, _ h: Int) -> CIImage {
        CIImage(bitmapData: Data(px), bytesPerRow: w * 4,
                size: CGSize(width: w, height: h), format: .RGBA8, colorSpace: linear)
    }

    private func render(_ img: CIImage, _ w: Int, _ h: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CIContext(options: [.workingColorSpace: linear])
        ctx.render(img, toBitmap: &out, rowBytes: w * 4,
                   bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8, colorSpace: linear)
        return out
    }

    private func lum(_ a: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> Int { Int(a[(y * w + x) * 4]) }

    /// 균일 배경 + 세로 결함 선(밝거나 어둡게).
    private func scene(w: Int, h: Int, base: Int, defectX: Int, defectW: Int, delta: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let o = i * 4
            px[o] = UInt8(base); px[o + 1] = UInt8(base); px[o + 2] = UInt8(base); px[o + 3] = 255
        }
        for y in 0..<h {
            for x in defectX..<min(w, defectX + defectW) {
                let o = (y * w + x) * 4
                let v = UInt8(max(0, min(255, base + delta)))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
        return px
    }

    private func brushBand(w: Int, h: Int, x0: Int, x1: Int) -> CIImage {
        var bp = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in x0..<x1 {
                let o = (y * w + x) * 4
                bp[o] = 255; bp[o + 1] = 255; bp[o + 2] = 255; bp[o + 3] = 255
            }
        }
        return ciImage(bp, w, h)
    }

    /// 결함을 칠해 ICE 적용 → 결함 위치의 복원 후 밝기와 배경을 돌려준다.
    private func removed(base: Int, delta: Int) -> (after: Int, base: Int) {
        let w = 160, h = 160, dx = 80, dw = 2
        let px = scene(w: w, h: h, base: base, defectX: dx, defectW: dw, delta: delta)
        let img = ciImage(px, w, h)
        let brush = brushBand(w: w, h: h, x0: dx - 6, x1: dx + dw + 6)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        return (lum(out, w, dx, 80), base)
    }

    func testRawLinearBrightDefectRemoved() {
        let (after, base) = removed(base: 120, delta: 70)
        print("[raw-linear bright] defect→\(after) (base=\(base))")
        XCTAssertLessThan(abs(after - base), 24, "선형 도메인 밝은 결함이 제거되지 않음")
    }

    func testRawLinearDarkDefectRemoved() {
        let (after, base) = removed(base: 120, delta: -60)
        print("[raw-linear dark] defect→\(after) (base=\(base))")
        XCTAssertLessThan(abs(after - base), 24, "선형 도메인 어두운 결함이 제거되지 않음")
    }

    /// 결함 없는 칠 영역은 거의 변하지 않아야 한다(과검출=우그러짐 방지).
    func testRawLinearNoDefectPreserved() {
        let w = 160, h = 160, base = 120
        let px = scene(w: w, h: h, base: base, defectX: -10, defectW: 0, delta: 0)
        let img = ciImage(px, w, h)
        let brush = brushBand(w: w, h: h, x0: 74, x1: 86)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        var diff = 0, count = 0
        for y in 40..<120 { for x in 74..<86 { diff += abs(lum(out, w, x, y) - base); count += 1 } }
        XCTAssertLessThan(diff / max(1, count), 6, "결함 없는 영역을 과검출")
    }
}
