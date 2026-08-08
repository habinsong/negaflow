import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// v2 질감 전사(외관 매칭 exemplar) 검증 — 합성 픽셀만 사용.
//
// 시나리오: 세로 줄무늬 텍스처 안의 결함 오른쪽에 "평탄 지역"이 붙어 있다. v1(성한 비율만으로
// 변위 선택, 첫 후보 (d,0)가 비율 1.0이면 즉시 채택)은 평탄 쪽 잔차(≈0)를 전사해 결함 자리가
// 균일 텍스처 케이스보다 매끈해졌다. v2는 결함 둘레 컨텍스트와 변위 위치의 SSD 를 봐서 같은
// 텍스처 지역을 골라야 한다 — 동일 기하의 균일 텍스처 복원과 같은 수준의 질감이 나와야 한다.
final class DefectTextureExemplarTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    private func ciImage(_ px: [UInt8], _ w: Int, _ h: Int) -> CIImage {
        makeRGBA8CIImage(px, w, h, colorSpace: linear)
    }
    private func render(_ img: CIImage, _ w: Int, _ h: Int) -> [UInt8] {
        renderRGBA8Pixels(img, w, h, colorSpace: linear)
    }
    private func lum(_ a: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> Int { Int(a[(y * w + x) * 4]) }

    /// 수평 방향 고주파(x±2 국소평균 대비) 평균 크기 — 세로 줄무늬 에너지.
    private func stripeEnergy(_ px: [UInt8], _ w: Int, xRange: Range<Int>, yRange: Range<Int>) -> Double {
        var sum = 0.0
        var count = 0
        for y in yRange {
            for x in xRange {
                let c = Double(lum(px, w, x, y))
                let m = (Double(lum(px, w, x - 2, y)) + Double(lum(px, w, x - 1, y))
                    + Double(lum(px, w, x + 1, y)) + Double(lum(px, w, x + 2, y))) / 4
                sum += abs(c - m)
                count += 1
            }
        }
        return sum / Double(max(1, count))
    }

    /// 줄무늬 텍스처(주기 8, ±22) 이미지. flatRight=true 면 x≥120 을 평탄(base)으로 둔다.
    private func stripes(_ w: Int, _ h: Int, base: Int, flatRight: Bool) -> [UInt8] {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let v = (!flatRight || x < 120) ? base + Int(22 * sin(Double(x) * .pi / 4)) : base
                let o = (y * w + x) * 4
                px[o] = UInt8(max(0, min(255, v))); px[o + 1] = px[o]; px[o + 2] = px[o]; px[o + 3] = 255
            }
        }
        return px
    }

    /// 16×16 blob 결함을 심고 복원한 결과를 돌려준다(blob: x 88..104, y 72..88).
    private func repairBlob(_ clean: [UInt8], _ w: Int, _ h: Int) -> [UInt8] {
        var damaged = clean
        var mask = [UInt8](repeating: 0, count: w * h * 4)
        for y in 72..<88 {
            for x in 88..<104 {
                let o = (y * w + x) * 4
                damaged[o] = 235; damaged[o + 1] = 235; damaged[o + 2] = 235
                mask[o] = 255; mask[o + 1] = 255; mask[o + 2] = 255; mask[o + 3] = 255
            }
        }
        return render(SoftwareDefectRemoval.repair(image: ciImage(damaged, w, h),
                                         roi: CGRect(x: 0, y: 0, width: w, height: h),
                                         mask: ciImage(mask, w, h)), w, h)
    }

    func testExemplarPicksMatchingTextureRegionNextToFlatArea() {
        let w = 200, h = 160, base = 120
        // 같은 blob 기하로 두 번 복원: ① 평탄 지역이 오른쪽(+d 변위 위치)에 붙은 경우,
        // ② 사방이 같은 텍스처인 기준 경우. 채움 동역학이 동일하므로 두 결과의 질감 차이는
        // 오로지 exemplar(변위 소스) 선택에서 온다.
        let cleanBoundary = stripes(w, h, base: base, flatRight: true)
        let cleanUniform = stripes(w, h, base: base, flatRight: false)
        let outBoundary = repairBlob(cleanBoundary, w, h)
        let outUniform = repairBlob(cleanUniform, w, h)

        let xR = 90..<102, yR = 74..<86
        let boundaryEnergy = stripeEnergy(outBoundary, w, xRange: xR, yRange: yR)
        let uniformEnergy = stripeEnergy(outUniform, w, xRange: xR, yRange: yR)
        let textureEnergy = stripeEnergy(cleanUniform, w, xRange: 30..<70, yRange: yR)
        print("[exemplar] boundary=\(boundaryEnergy) uniform=\(uniformEnergy) texture=\(textureEnergy)")
        // 기준(균일 텍스처) 복원 자체가 어느 정도 질감을 재현해야 한다(잔차 전사 동작 확인).
        XCTAssertGreaterThan(uniformEnergy, textureEnergy * 0.15,
                             "잔차 전사가 텍스처를 일부라도 재현해야 한다")
        // 핵심(v2): 평탄 지역이 옆에 있어도 균일 케이스와 같은 수준의 질감이어야 한다.
        // v1 은 첫 후보 (d,0)=평탄을 채택해 잔차≈0 이 되어 이 비율이 크게 떨어졌다.
        XCTAssertGreaterThan(boundaryEnergy, uniformEnergy * 0.75,
                             "평탄 지역 잔차가 전사되면 안 된다(외관 매칭 exemplar)")
        // 평균 밝기는 원본 텍스처 평균에 수렴해야 한다(구조 채움 정합).
        var meanDelta = 0.0
        for y in yR { for x in xR { meanDelta += Double(lum(outBoundary, w, x, y) - lum(cleanBoundary, w, x, y)) } }
        meanDelta /= Double(xR.count * yR.count)
        XCTAssertLessThan(abs(meanDelta), 12, "복원 평균이 원본 텍스처에서 크게 벗어나면 안 된다")
    }
}
