import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// 합성 스크래치로 브러시 ICE 의 (1) 검출·복원 (2) 주변 보존을 픽셀 단위로 측정한다.
// 실제 필름 결함을 눈으로 못 보는 대신, 알려진 위치/세기의 결함으로 수치 검증한다.
final class ICERepairTests: XCTestCase {
    private let cs = CGColorSpace(name: CGColorSpace.sRGB)!

    private func ciImage(_ px: [UInt8], _ w: Int, _ h: Int) -> CIImage {
        CIImage(bitmapData: Data(px), bytesPerRow: w * 4,
                size: CGSize(width: w, height: h), format: .RGBA8, colorSpace: cs)
    }

    private func render(_ img: CIImage, _ w: Int, _ h: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CIContext(options: [.workingColorSpace: cs])
        ctx.render(img, toBitmap: &out, rowBytes: w * 4,
                   bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8, colorSpace: cs)
        return out
    }

    /// 가로 그라데이션 배경. 세로 스크래치(폭 scratchW, 밝기 +delta).
    private func scene(w: Int, h: Int, scratchX: Int, scratchW: Int, delta: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let base = 60 + 120 * x / w
                let o = (y * w + x) * 4
                px[o] = UInt8(base); px[o + 1] = UInt8(base); px[o + 2] = UInt8(base); px[o + 3] = 255
            }
        }
        for y in 0..<h {
            for x in scratchX..<min(w, scratchX + scratchW) {
                let o = (y * w + x) * 4
                let v = UInt8(max(0, min(255, Int(px[o]) + delta)))
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

    private func run(w: Int, h: Int, scratchX: Int, scratchW: Int, delta: Int) -> (before: [UInt8], after: [UInt8]) {
        let px = scene(w: w, h: h, scratchX: scratchX, scratchW: scratchW, delta: delta)
        let img = ciImage(px, w, h)
        let brush = brushBand(w: w, h: h, x0: scratchX - 6, x1: scratchX + scratchW + 6)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let result = SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                       repairExtent: CGRect(x: 0, y: 0, width: w, height: h))
        return (px, render(result, w, h))
    }

    private func lum(_ a: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> Int { Int(a[(y * w + x) * 4]) }

    func testBrightScratchRemovedAndSurroundingsPreserved() {
        let w = 160, h = 160, scratchX = 80, scratchW = 2
        let (before, after) = run(w: w, h: h, scratchX: scratchX, scratchW: scratchW, delta: 70)
        let bg = 60 + 120 * scratchX / w

        let scBefore = lum(before, w, scratchX, 80)
        let scAfter = lum(after, w, scratchX, 80)
        let nearAfter = lum(after, w, scratchX - 4, 80)
        let nearBefore = lum(before, w, scratchX - 4, 80)
        let sideAfter = lum(after, w, 130, 80)
        let sideBefore = lum(before, w, 130, 80)
        print("[bright] scratch \(scBefore)→\(scAfter) (bg≈\(bg)) | near \(nearBefore)→\(nearAfter) | side \(sideBefore)→\(sideAfter)")

        XCTAssertLessThan(abs(scAfter - bg), 22, "밝은 스크래치가 제거되지 않음")
        XCTAssertLessThanOrEqual(abs(nearAfter - nearBefore), 12, "브러시 안 비결함 픽셀이 우그러짐")
        XCTAssertLessThanOrEqual(abs(sideAfter - sideBefore), 2, "브러시 밖 주변이 변함")
    }

    func testDarkThinScratchRemoved() {
        let w = 160, h = 160, scratchX = 80, scratchW = 1
        let (before, after) = run(w: w, h: h, scratchX: scratchX, scratchW: scratchW, delta: -60)
        let bg = 60 + 120 * scratchX / w
        let scBefore = lum(before, w, scratchX, 80)
        let scAfter = lum(after, w, scratchX, 80)
        print("[dark-thin] scratch \(scBefore)→\(scAfter) (bg≈\(bg))")
        XCTAssertLessThan(abs(scAfter - bg), 22, "얇은 어두운 스크래치가 제거되지 않음")
    }

    // MARK: 현실 조건 (그레인 + 구조 에지)

    private func addGrain(_ px: inout [UInt8], w: Int, h: Int, amp: Int, seed: UInt64) {
        var s = seed
        for i in 0..<(w * h) {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let n = Int(s >> 40) % (2 * amp + 1) - amp
            let o = i * 4
            for c in 0..<3 { px[o + c] = UInt8(max(0, min(255, Int(px[o + c]) + n))) }
        }
    }

    /// 그레인이 깔린 배경의 스크래치도 검출·복원되는가(그레인은 결함으로 오인되면 안 됨).
    func testScratchInGrainRemoved() {
        let w = 160, h = 160, scratchX = 80, scratchW = 2
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        addGrain(&px, w: w, h: h, amp: 7, seed: 0xABCD)
        let clean = px   // 스크래치 그리기 전(그레인 포함) ground truth
        for y in 0..<h {
            for x in scratchX..<(scratchX + scratchW) {
                let o = (y * w + x) * 4
                let v = UInt8(max(0, min(255, Int(px[o]) + 55)))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
        let img = ciImage(px, w, h)
        let brush = brushBand(w: w, h: h, x0: scratchX - 6, x1: scratchX + scratchW + 6)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        var resid = 0, count = 0
        for y in 40..<120 {
            for x in scratchX..<(scratchX + scratchW) { resid += abs(lum(out, w, x, y) - lum(clean, w, x, y)); count += 1 }
        }
        let avg = resid / max(1, count)
        print("[grain] avg scratch residual vs clean = \(avg)")
        XCTAssertLessThan(avg, 22, "그레인 속 스크래치가 복원되지 않음")
    }

    /// 가로 스크래치가 세로 에지를 가로지를 때, isophote(세로) 방향 보간이 에지를 보존하는가.
    /// "최단 거리" 보간이면 좌우가 섞여 에지가 뭉개진다 — 우그러짐의 핵심 케이스.
    func testHorizontalScratchAcrossVerticalEdgePreservesEdge() {
        let w = 160, h = 160, edgeX = 80
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let v = x < edgeX ? 75 : 175
                let o = (y * w + x) * 4
                px[o] = UInt8(v); px[o + 1] = UInt8(v); px[o + 2] = UInt8(v); px[o + 3] = 255
            }
        }
        for y in 78..<81 {       // 가로 스크래치(어둡게)
            for x in 0..<w {
                let o = (y * w + x) * 4
                let v = UInt8(max(0, min(255, Int(px[o]) - 40)))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
        var bp = [UInt8](repeating: 0, count: w * h * 4)
        for y in 72..<87 {       // 가로 브러시 띠
            for x in 0..<w { let o = (y * w + x) * 4; bp[o] = 255; bp[o + 1] = 255; bp[o + 2] = 255; bp[o + 3] = 255 }
        }
        let img = ciImage(px, w, h)
        let brush = ciImage(bp, w, h)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        let left = lum(out, w, edgeX - 4, 79)    // 에지 왼쪽(어두움 75)
        let right = lum(out, w, edgeX + 4, 79)   // 에지 오른쪽(밝음 175)
        print("[edge] across scratch row: left=\(left) right=\(right) (expect ~75 / ~175)")
        XCTAssertLessThan(abs(left - 75), 35, "에지 왼쪽이 우그러짐")
        XCTAssertGreaterThan(right - left, 60, "에지가 뭉개짐(좌우 대비 소실)")
    }

    // MARK: 검출 민감도 (얇은 스크래치 vs 그레인 과검출)

    /// 대비를 스윕해 검출 플로어를 찾는다. residual ≈ delta 면 미검출, ≈0 이면 제거됨.
    /// 실제 이미지를 모사하려 강한 그레인(amp 14)을 깔아 kFloor 게이트를 압박한다.
    func testFaintScratchDetectionFloor() {
        let w = 160, h = 160, scratchX = 80
        for delta in [10, 14, 20, 28] {
            var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
            addGrain(&px, w: w, h: h, amp: 14, seed: 0x55AA)
            let clean = px
            for y in 0..<h {
                let o = (y * w + scratchX) * 4
                let v = UInt8(max(0, min(255, Int(px[o]) + delta)))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
            let img = ciImage(px, w, h)
            let brush = brushBand(w: w, h: h, x0: scratchX - 6, x1: scratchX + 7)
            let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                               scratchSensitivity: 0.7, protectDetail: 0.6)
            let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                               repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
            // 부호 있는 평균: 그레인(평균0)은 상쇄되고 미검출 스크래치 편향(≈delta)만 남는다.
            var bias = 0, count = 0
            for y in 40..<120 { bias += lum(out, w, scratchX, y) - lum(clean, w, scratchX, y); count += 1 }
            print("[faint] delta=\(delta) → leftover bias=\(bias / max(1, count)) (0=removed, ≈delta=missed)")
        }
    }

    /// 복원면이 주변 그레인 수준의 질감을 갖는가(매끈하면 "뿌옇"). 세로 그레인 std 비교.
    func testRepairedRegionGrainPreserved() {
        let w = 160, h = 160, scratchX = 80
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        addGrain(&px, w: w, h: h, amp: 8, seed: 0x77)
        for y in 0..<h {
            for x in scratchX..<(scratchX + 2) {
                let o = (y * w + x) * 4
                let v = UInt8(max(0, min(255, Int(px[o]) + 55)))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
        let img = ciImage(px, w, h)
        let brush = brushBand(w: w, h: h, x0: scratchX - 6, x1: scratchX + 8)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        func columnStd(_ x: Int) -> Double {
            var vals = [Double]()
            for y in 40..<120 { vals.append(Double(lum(out, w, x, y))) }
            let m = vals.reduce(0, +) / Double(vals.count)
            return (vals.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(vals.count)).squareRoot()
        }
        let repaired = columnStd(scratchX)        // 복원된 컬럼
        let neighbor = columnStd(scratchX + 20)   // 성한 이웃 컬럼
        print("[blur] repaired-column std=\(String(format: "%.1f", repaired)) vs neighbor std=\(String(format: "%.1f", neighbor)) (가까울수록 자연)")
        XCTAssertGreaterThan(repaired, neighbor * 0.72, "복원면이 매끈해 뿌옇게 보임(그레인 부족)")
        XCTAssertLessThan(repaired, neighbor * 1.15, "복원면 노이즈 과다(티남)")
    }

    /// 가로 스크래치를 가로지르는 세로 어두운 선이 복원 후에도 보존되는가(색 날아감/끊김 방지).
    /// 사용자 핵심 불만: 교차점에서 세로 구조가 밝은 배경으로 채워져 사라짐.
    func testVerticalLineThroughHorizontalScratchPreserved() {
        let w = 160, h = 160, bg = 170, line = 45, lineX = 100
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let v = (x == lineX || x == lineX + 1) ? line : bg
                let o = (y * w + x) * 4
                px[o] = UInt8(v); px[o + 1] = UInt8(v); px[o + 2] = UInt8(v); px[o + 3] = 255
            }
        }
        addGrain(&px, w: w, h: h, amp: 5, seed: 0x99)
        let clean = px
        for y in 78..<81 {       // 가로 밝은 스크래치
            for x in 0..<w {
                let o = (y * w + x) * 4
                let v = UInt8(min(255, Int(px[o]) + 55))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
        var bp = [UInt8](repeating: 0, count: w * h * 4)
        for y in 72..<87 {       // 가로 브러시 띠
            for x in 30..<150 { let o = (y * w + x) * 4; bp[o] = 255; bp[o + 1] = 255; bp[o + 2] = 255; bp[o + 3] = 255 }
        }
        let img = ciImage(px, w, h)
        let brush = ciImage(bp, w, h)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        // 가로 칠 → preferredAngle 0. 세로선(90°)은 방향 우세 판정으로 결함에서 제외되고,
        // 복원은 세로(직교) 방향을 선호해 교차점에서도 세로선을 잇는다.
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h),
                                           preferredAngle: 0), w, h)
        let crossing = lum(out, w, lineX, 79)        // 교차점 — 세로선 색(어두움 45)이어야
        let cleanCross = lum(clean, w, lineX, 79)
        let scratchOnly = lum(out, w, 50, 79)        // 세로선 없는 가로 스크래치 — 제거되어 배경(≈170)
        print("[vline] crossing=\(crossing) (clean=\(cleanCross)) | scratchOnly=\(scratchOnly) (bg=\(bg))")
        XCTAssertLessThan(abs(crossing - cleanCross), 35, "세로선이 스크래치 제거로 색 날아감/끊김")
        XCTAssertLessThan(abs(scratchOnly - bg), 25, "가로 스크래치 자체는 여전히 제거되어야")
    }

    /// 그레인만 있고 결함이 없는 칠 영역은 거의 안 변해야 한다(과검출=우그러짐 방지 가드).
    func testGrainOnlyNotOverDetected() {
        let w = 160, h = 160
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        addGrain(&px, w: w, h: h, amp: 6, seed: 0x1234)
        let before = px
        let img = ciImage(px, w, h)
        let brush = brushBand(w: w, h: h, x0: 74, x1: 86)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        var diff = 0, count = 0
        for y in 40..<120 { for x in 74..<86 { diff += abs(lum(out, w, x, y) - lum(before, w, x, y)); count += 1 } }
        let avg = diff / max(1, count)
        print("[grain-only] avg change in brushed grain = \(avg) (should stay small)")
        XCTAssertLessThan(avg, 7, "그레인을 결함으로 오검출(과검출)")
    }

    // MARK: 뚱뚱한(짧고 두꺼운) 먼지 / 곡선 먼지 — onion-peel 복원으로 중앙까지 완전 제거

    private func filledDisc(_ px: inout [UInt8], w: Int, h: Int, cx: Int, cy: Int, r: Int, delta: Int) {
        for y in max(0, cy - r)...min(h - 1, cy + r) {
            for x in max(0, cx - r)...min(w - 1, cx + r) {
                let dx = x - cx, dy = y - cy
                guard dx * dx + dy * dy <= r * r else { continue }
                let o = (y * w + x) * 4
                let v = UInt8(max(0, min(255, Int(px[o]) + delta)))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
    }

    /// 짧고 두꺼운(뚱뚱한) 원형 먼지: 중앙까지 평균 블러 없이 배경으로 채워져야 한다.
    func testFatBlobDustRemoved() {
        let w = 160, h = 160, cx = 80, cy = 80, r = 8   // 지름 16, area ~201px
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        filledDisc(&px, w: w, h: h, cx: cx, cy: cy, r: r, delta: 80)
        let img = ciImage(px, w, h)
        let brush = brushBand(w: w, h: h, x0: cx - r - 4, x1: cx + r + 4)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        let bg = 60 + 120 * cx / w
        print("[fat-blob] center \(lum(px, w, cx, cy))→\(lum(out, w, cx, cy)) (bg≈\(bg))")
        XCTAssertLessThan(abs(lum(out, w, cx, cy) - bg), 26, "뚱뚱한 먼지 중앙이 안 지워짐")
        XCTAssertLessThan(abs(lum(out, w, cx - r + 1, cy) - bg), 26, "뚱뚱한 먼지 가장자리 잔존")
    }

    /// 부드러운 경계(halo)를 가진 흰 뚱뚱한 먼지: 중앙뿐 아니라 경계 흰색까지 잔존 없이 제거.
    func testFatBlobSoftEdgeFullyRemoved() {
        let w = 160, h = 160, cx = 80, cy = 80, r = 7
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        for y in max(0, cy - r - 3)...min(h - 1, cy + r + 3) {
            for x in max(0, cx - r - 3)...min(w - 1, cx + r + 3) {
                let dd = (Double((x - cx) * (x - cx) + (y - cy) * (y - cy))).squareRoot()
                let falloff = dd <= Double(r) ? 1.0 : max(0, 1 - (dd - Double(r)) / 3)
                guard falloff > 0 else { continue }
                let o = (y * w + x) * 4
                let v = UInt8(min(255, Int(px[o]) + Int(85 * falloff)))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
        let img = ciImage(px, w, h)
        let brush = brushBand(w: w, h: h, x0: cx - r - 6, x1: cx + r + 6)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        let bg = 60 + 120 * cx / w
        let center = lum(out, w, cx, cy), edge = lum(out, w, cx + r, cy), halo = lum(out, w, cx + r + 2, cy)
        print("[soft-fat] center=\(center) edge=\(edge) halo=\(halo) (bg≈\(bg))")
        XCTAssertLessThan(abs(center - bg), 16, "부드러운 뚱뚱 먼지 중앙 잔존")
        XCTAssertLessThan(abs(edge - bg), 16, "부드러운 경계 흰색 잔존")
        XCTAssertLessThan(abs(halo - bg), 14, "halo 흰색 잔존")
    }

    /// 흐릿한(저대비) 뚱뚱한 먼지: 덜 하얀/검은 약한 신호도 brush 영역에선 검출·제거되어야 한다.
    func testFaintFatBlobDustRemoved() {
        let w = 160, h = 160, cx = 80, cy = 80, r = 9
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        filledDisc(&px, w: w, h: h, cx: cx, cy: cy, r: r, delta: 34)   // 저대비(흐릿)
        let img = ciImage(px, w, h)
        let brush = brushBand(w: w, h: h, x0: cx - r - 4, x1: cx + r + 4)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        let bg = 60 + 120 * cx / w
        print("[faint-fat] center \(lum(px, w, cx, cy))→\(lum(out, w, cx, cy)) (bg≈\(bg))")
        XCTAssertLessThan(abs(lum(out, w, cx, cy) - bg), 20, "흐릿한 뚱뚱한 먼지가 안 지워짐")
    }

    // MARK: 긴 스트로크 / 크로마 그레인·텍스처 — "칠 영역 전체 와이프(블러)" 회귀 방지

    /// 실제 컬러 필름 그레인은 채널 독립(chromatic)이다. dustMag(채널 max)가 luma 그레인보다
    /// 크게 나와, 과검출 마스크가 칠 영역 전체로 번지면 복원(경계 전파 보간)이 칠을 통째로
    /// 밀어 "전체 블러"가 된다.
    private func addChromaGrain(_ px: inout [UInt8], w: Int, h: Int, amp: Int, seed: UInt64) {
        var s = seed
        for i in 0..<(w * h) {
            let o = i * 4
            for c in 0..<3 {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                let n = Int(s >> 40) % (2 * amp + 1) - amp
                px[o + c] = UInt8(max(0, min(255, Int(px[o + c]) + n)))
            }
        }
    }

    private func horizontalBrush(w: Int, h: Int, x0: Int, x1: Int, y0: Int, y1: Int) -> CIImage {
        var bp = [UInt8](repeating: 0, count: w * h * 4)
        for y in y0..<y1 {
            for x in x0..<x1 {
                let o = (y * w + x) * 4
                bp[o] = 255; bp[o + 1] = 255; bp[o + 2] = 255; bp[o + 3] = 255
            }
        }
        return ciImage(bp, w, h)
    }

    /// 결함 없는 크로마 그레인 위를 길게 칠했을 때, 칠 영역이 통째로 재합성되면 안 된다.
    func testLongStrokeOnChromaGrainDoesNotWipeWholeBand() {
        let w = 520, h = 160
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        addChromaGrain(&px, w: w, h: h, amp: 10, seed: 0xBEEF)
        let before = px
        let img = ciImage(px, w, h)
        let brush = horizontalBrush(w: w, h: h, x0: 10, x1: 510, y0: 66, y1: 94)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        var diff = 0, changed = 0, count = 0
        for y in 66..<94 {
            for x in 10..<510 {
                let d = abs(lum(out, w, x, y) - lum(before, w, x, y))
                diff += d; if d > 10 { changed += 1 }; count += 1
            }
        }
        let avg = Double(diff) / Double(count)
        let frac = Double(changed) / Double(count)
        print("[long-stroke grain] avg change=\(String(format: "%.2f", avg)) changed(>10)=\(String(format: "%.1f", frac * 100))%")
        XCTAssertLessThan(avg, 4.0, "결함 없는 그레인 띠가 통째로 재합성됨(전체 블러 회귀)")
        XCTAssertLessThan(frac, 0.10, "칠 영역의 10% 이상이 크게 변함(과검출 와이프)")
    }

    /// 고주파 텍스처(가는 구조가 빽빽한 면) 위를 길게 칠해도 텍스처가 결함으로 통째로
    /// 오검출되면 안 된다 — "특정 상황(나뭇잎/직물/자갈)에서 칠 전체 블러"의 회귀 방지.
    func testLongStrokeOnFineTextureDoesNotWipeTexture() {
        let w = 520, h = 160
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                // 사인 격자 + 결정적 지터: 잎/직물 같은 고대비 미세 구조.
                let s = sin(Double(x) * 0.9) * sin(Double(y) * 0.8)
                let jitter = Double((x * 31 + y * 17) % 7) - 3
                let v = 120 + Int(46 * s) + Int(jitter * 3)
                let o = (y * w + x) * 4
                let u = UInt8(max(0, min(255, v)))
                px[o] = u; px[o + 1] = u; px[o + 2] = u; px[o + 3] = 255
            }
        }
        let before = px
        let img = ciImage(px, w, h)
        let brush = horizontalBrush(w: w, h: h, x0: 10, x1: 510, y0: 60, y1: 100)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        var diff = 0, count = 0
        for y in 60..<100 {
            for x in 10..<510 { diff += abs(lum(out, w, x, y) - lum(before, w, x, y)); count += 1 }
        }
        let avg = Double(diff) / Double(count)
        print("[long-stroke texture] avg change=\(String(format: "%.2f", avg))")
        XCTAssertLessThan(avg, 5.0, "미세 텍스처가 결함으로 통째로 오검출되어 재합성됨(전체 블러 회귀)")
    }

    /// 와이프 가드가 실제 결함 제거까지 죽이면 안 된다: 크로마 그레인 띠 안의 스크래치·먼지는
    /// 여전히 제거되어야 한다.
    func testDefectsInChromaGrainBandStillRemoved() {
        let w = 520, h = 160
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        addChromaGrain(&px, w: w, h: h, amp: 10, seed: 0xF00D)
        let clean = px
        for y in 79..<81 {          // 밴드 안 가로 스크래치(밝음). 먼지와 x 범위 분리(병합 방지).
            for x in 60..<300 {
                let o = (y * w + x) * 4
                let v = UInt8(min(255, Int(px[o]) + 55))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
        filledDisc(&px, w: w, h: h, cx: 400, cy: 78, r: 6, delta: 65)   // 밴드 안 먼지
        let img = ciImage(px, w, h)
        let brush = horizontalBrush(w: w, h: h, x0: 10, x1: 510, y0: 66, y1: 94)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        var resid = 0, count = 0
        for x in stride(from: 80, to: 280, by: 4) {
            for y in 79..<81 { resid += abs(lum(out, w, x, y) - lum(clean, w, x, y)); count += 1 }
        }
        let scratchResid = resid / max(1, count)
        let dustResid = abs(lum(out, w, 400, 78) - lum(clean, w, 400, 78))
        print("[grain-band defects] scratch residual=\(scratchResid) dust residual=\(dustResid)")
        XCTAssertLessThan(scratchResid, 22, "그레인 띠 안 스크래치가 제거되지 않음(가드 과보수)")
        XCTAssertLessThan(dustResid, 26, "그레인 띠 안 먼지가 제거되지 않음(가드 과보수)")
    }

    /// 굽은(꼬부랑) 먼지: 곡선을 따라 어디서도 희미하게 남지 않아야 한다.
    func testCurvedDustRemoved() {
        let w = 180, h = 160
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        var pts = [(Int, Int)]()
        for x in 50..<130 {
            let yc = 80 + Int(18 * sin(Double(x - 50) / 12))
            for dy in -2...2 { pts.append((x, yc + dy)) }   // 두께 5 곡선
        }
        for (x, y) in pts {
            let o = (y * w + x) * 4
            let v = UInt8(min(255, Int(px[o]) + 70))
            px[o] = v; px[o + 1] = v; px[o + 2] = v
        }
        var bp = [UInt8](repeating: 0, count: w * h * 4)
        for x in 46..<134 { for y in 56..<104 {
            let o = (y * w + x) * 4; bp[o] = 255; bp[o + 1] = 255; bp[o + 2] = 255; bp[o + 3] = 255
        } }
        let img = ciImage(px, w, h)
        let brush = ciImage(bp, w, h)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareICE.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        var maxResid = 0
        for (x, y) in pts {
            let bg = 60 + 120 * x / w
            maxResid = max(maxResid, abs(lum(out, w, x, y) - bg))
        }
        print("[curved] max residual along curve = \(maxResid)")
        XCTAssertLessThan(maxResid, 30, "곡선 먼지가 희미하게 남음")
    }
}
