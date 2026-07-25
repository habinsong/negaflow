import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// 합성 스크래치로 브러시 결함 제거 의 (1) 검출·복원 (2) 주변 보존을 픽셀 단위로 측정한다.
// 실제 필름 결함을 눈으로 못 보는 대신, 알려진 위치/세기의 결함으로 수치 검증한다.
final class DefectRepairTests: XCTestCase {
    private let cs = CGColorSpace(name: CGColorSpace.sRGB)!

    private func ciImage(_ px: [UInt8], _ w: Int, _ h: Int) -> CIImage {
        makeRGBA8CIImage(px, w, h, colorSpace: cs)
    }

    private func render(_ img: CIImage, _ w: Int, _ h: Int) -> [UInt8] {
        renderRGBA8Pixels(img, w, h, colorSpace: cs)
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
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let result = SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
                                       repairExtent: CGRect(x: 0, y: 0, width: w, height: h))
        return (px, render(result, w, h))
    }

    private func lum(_ a: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> Int { Int(a[(y * w + x) * 4]) }

    private func highpass(_ a: [UInt8], w: Int, x: Int, y: Int) -> Double {
        let center = Double(lum(a, w, x, y))
        var sum = 0.0
        for yy in (y - 2)...(y + 2) {
            for xx in (x - 2)...(x + 2) {
                sum += Double(lum(a, w, xx, yy))
            }
        }
        return center - sum / 25.0
    }

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
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
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
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
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
            let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                               scratchSensitivity: 0.7, protectDetail: 0.6)
            let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
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
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
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

    /// 복원면이 "크로마틱" 그레인(채널 독립 — 실제 필름 그레인)을 보존하는가. 채널 공통(luma) 노이즈
    /// 재주입은 복원면을 탈색시켜 주변과 확 달라 보이게 한다(밋밋한 블러 인상) — 질감 전사(인접 성한
    /// 영역의 채널별 잔차 복사)가 채널 간 편차 std(R−G) 를 주변 수준으로 유지해야 한다.
    func testRepairedRegionPreservesChromaticGrain() {
        let w = 160, h = 160, cx = 80, cy = 80, r = 8
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        addChromaGrain(&px, w: w, h: h, amp: 8, seed: 0xC401)
        for y in (cy - r)...(cy + r) {          // 뚱뚱한 결함(onion-peel 경로 — 내부는 전파 채움)
            for x in (cx - r)...(cx + r) where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r {
                let o = (y * w + x) * 4
                let v = UInt8(min(255, Int(px[o]) + 80))
                px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
        let img = ciImage(px, w, h)
        let brush = brushBand(w: w, h: h, x0: cx - r - 4, x1: cx + r + 4)
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        func chromaStd(_ x0: Int, _ y0: Int) -> Double {
            var vals = [Double]()
            for y in y0..<(y0 + 10) {
                for x in x0..<(x0 + 10) {
                    let o = (y * w + x) * 4
                    vals.append(Double(out[o]) - Double(out[o + 1]))   // R−G
                }
            }
            let m = vals.reduce(0, +) / Double(vals.count)
            return (vals.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(vals.count)).squareRoot()
        }
        let repairedChroma = chromaStd(cx - 5, cy - 5)    // 결함 내부(복원면)
        let referenceChroma = chromaStd(cx + 35, cy - 5)  // 성한 그레인
        print(String(format: "[chroma-grain] repaired std(R−G)=%.1f vs reference=%.1f", repairedChroma, referenceChroma))
        XCTAssertGreaterThan(repairedChroma, referenceChroma * 0.55,
                             "복원면의 크로마틱 그레인이 탈색되면 안 된다(채널 공통 노이즈 회귀)")
        XCTAssertLessThan(repairedChroma, referenceChroma * 1.6, "복원면 크로마 노이즈 과다")
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
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        // 가로 칠 → preferredAngle 0. 세로선(90°)은 방향 우세 판정으로 결함에서 제외되고,
        // 복원은 세로(직교) 방향을 선호해 교차점에서도 세로선을 잇는다.
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
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
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        var diff = 0, count = 0
        for y in 40..<120 { for x in 74..<86 { diff += abs(lum(out, w, x, y) - lum(before, w, x, y)); count += 1 } }
        let avg = diff / max(1, count)
        print("[grain-only] avg change in brushed grain = \(avg) (should stay small)")
        XCTAssertLessThan(avg, 7, "그레인을 결함으로 오검출(과검출)")
    }

    // MARK: 복잡한 이미지 + 일자 스트로크 — "칠 면적 전체 블러" 회귀 방지 (구조 가드)
    //
    // 검출 임계·SNR 배수는 절대 건드리지 않는다(과거 임계 상향이 저대비 결함 제거를 죽인 회귀).
    // 가드는 구조적: 물리 면적 상한(min-cap), 스크래치 두께 상한, strongMag 면제의 컨텍스트 게이트.

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

    /// 사용자 케이스 재현: 미세 텍스처(잎/직물류) 위를 "일자로"(preferredAngle 있음) 길게 칠했을 때
    /// 칠 면적 전체가 재합성(블러)되면 안 된다.
    func testStraightStrokeOnFineTextureDoesNotWipe() {
        let w = 520, h = 160
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
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
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        // 일자 가로 스트로크 = preferredAngle 0 (DefectBrush.strokeAngle 이 주는 값과 동일).
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h),
                                           preferredAngle: 0), w, h)
        var diff = 0, changed = 0, count = 0
        for y in 60..<100 {
            for x in 10..<510 {
                let d = abs(lum(out, w, x, y) - lum(before, w, x, y))
                diff += d; if d > 10 { changed += 1 }; count += 1
            }
        }
        let avg = Double(diff) / Double(count)
        let frac = Double(changed) / Double(count)
        print(String(format: "[straight-texture] avg change=%.2f changed(>10)=%.1f%%", avg, frac * 100))
        XCTAssertLessThan(avg, 5.0, "미세 텍스처 위 일자 칠이 통째로 재합성됨(전체 블러 회귀)")
        XCTAssertLessThan(frac, 0.20, "칠 영역의 20% 이상이 크게 변함(과검출 와이프)")
    }

    /// 사용자 케이스 재현 2: "복잡한 이미지"는 균일 텍스처가 아니라 불균일 — busy 한 디테일 섬이
    /// 매끈한 영역 사이에 있다. 섬 안의 정상 디테일이 strongMag 절대 면제(0.039)로 통째로 먼지
    /// 후보가 되고, 섬 크기 덩어리는 컴팩트해서(aspect≤4) 게이트를 통과 → 섬째로 재합성 = 블러.
    func testStraightStrokeOnBusyIslandsDoesNotWipeDetail() {
        let w = 520, h = 160
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        // 밴드 안 busy 디테일 섬 3개(고대비 미세 구조 — 나뭇잎/자갈 뭉치 류).
        let islands = [(70, 55), (230, 55), (390, 55)]   // (x0, y0), 크기 80×50
        for (ix, iy) in islands {
            for y in iy..<(iy + 50) {
                for x in ix..<(ix + 80) {
                    let s = sin(Double(x) * 0.95) * sin(Double(y) * 0.85)
                    let jitter = Double((x * 31 + y * 17) % 7) - 3
                    let o = (y * w + x) * 4
                    let v = UInt8(max(0, min(255, Int(px[o]) + Int(40 * s) + Int(jitter * 3))))
                    px[o] = v; px[o + 1] = v; px[o + 2] = v
                }
            }
        }
        let before = px
        let img = ciImage(px, w, h)
        let brush = horizontalBrush(w: w, h: h, x0: 10, x1: 510, y0: 60, y1: 100)
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h),
                                           preferredAngle: 0), w, h)
        var diff = 0, count = 0
        for (ix, iy) in islands {
            for y in max(60, iy)..<min(100, iy + 50) {
                for x in ix..<(ix + 80) {
                    diff += abs(lum(out, w, x, y) - lum(before, w, x, y)); count += 1
                }
            }
        }
        let avg = Double(diff) / Double(count)
        print(String(format: "[busy-islands] avg change in islands=%.2f", avg))
        XCTAssertLessThan(avg, 5.0, "busy 디테일 섬이 통째로 재합성됨(복잡한 이미지 일자 칠 블러 회귀)")
    }

    /// 크로마 그레인 위 일자 스트로크 — strongMag 면제가 그레인 피크를 통과시키면 안 된다.
    func testStraightStrokeOnChromaGrainDoesNotWipe() {
        let w = 520, h = 160
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        addChromaGrain(&px, w: w, h: h, amp: 10, seed: 0xBEEF)
        let before = px
        let img = ciImage(px, w, h)
        let brush = horizontalBrush(w: w, h: h, x0: 10, x1: 510, y0: 66, y1: 94)
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h),
                                           preferredAngle: 0), w, h)
        var diff = 0, changed = 0, count = 0
        for y in 66..<94 {
            for x in 10..<510 {
                let d = abs(lum(out, w, x, y) - lum(before, w, x, y))
                diff += d; if d > 10 { changed += 1 }; count += 1
            }
        }
        let avg = Double(diff) / Double(count)
        let frac = Double(changed) / Double(count)
        print(String(format: "[straight-grain] avg change=%.2f changed(>10)=%.1f%%", avg, frac * 100))
        // 기준선: 가드 도입 전 합성 크로마 그레인에서 avg 2.7 / frac 8.9%(흩어진 소규모 복원 —
        // 와이프 아님, 기존 동작). 가드는 이를 악화시키지 않아야 한다는 회귀 상한이다.
        XCTAssertLessThan(avg, 4.0, "결함 없는 그레인 띠가 통째로 재합성됨")
        XCTAssertLessThan(frac, 0.15, "칠 영역이 기준선(~9%) 대비 크게 악화됨")
    }

    /// 사용자 실전 케이스 재현: 크로마 그레인 위 "대각선" 브러시(preferredAngle 대각) — 얇은 대각
    /// 스크래치는 제거되고, 칠 안의 그레인은 낱알 복원이 쌓여 진행 방향으로 층층 블러가 되면 안 된다
    /// (그레인 필드 필터: 빽빽한 작은 컴포넌트 기각).
    func testDiagonalStrokeOnGrainRemovesScratchWithoutLayeredBlur() {
        let w = 300, h = 400, base = 150, delta = 40
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let o = i * 4
            px[o] = UInt8(base); px[o + 1] = UInt8(base); px[o + 2] = UInt8(base); px[o + 3] = 255
        }
        addChromaGrain(&px, w: w, h: h, amp: 10, seed: 0xD1A6)
        let clean = px
        // 대각 스크래치: (70,40) → 방향 (0.44, 1), 길이 340
        var scratchPts: [(Int, Int)] = []
        for t in 0..<340 {
            let x = 70 + Int((0.44 * Double(t)).rounded()), y = 40 + t
            guard x < w, y < h else { break }
            let o = (y * w + x) * 4
            let v = UInt8(min(255, Int(px[o]) + delta))
            px[o] = v; px[o + 1] = v; px[o + 2] = v
            scratchPts.append((x, y))
        }
        // 스크래치를 덮는 대각 브러시 띠(±14px)
        var bp = [UInt8](repeating: 0, count: w * h * 4)
        var brushPx = 0
        for t in 0..<360 {
            let xc = 70 + Int((0.44 * Double(t)).rounded()), y = 40 + t
            guard y < h else { break }
            for x in max(0, xc - 14)...min(w - 1, xc + 14) {
                let o = (y * w + x) * 4
                if bp[o] == 0 { brushPx += 1 }
                bp[o] = 255; bp[o + 1] = 255; bp[o + 2] = 255; bp[o + 3] = 255
            }
        }
        let img = ciImage(px, w, h)
        let brush = ciImage(bp, w, h)
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let angle = atan2(1.0, 0.44) * 180 / Double.pi   // 스트로크 주축(도)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h),
                                           preferredAngle: angle), w, h)
        // (a) 스크래치는 제거(잔존 편향이 delta 의 절반 미만)
        var bias = 0
        for (x, y) in scratchPts { bias += lum(out, w, x, y) - lum(clean, w, x, y) }
        let avgBias = Double(bias) / Double(scratchPts.count)
        // (b) 칠 안·스크래치에서 6px 이상 떨어진 그레인은 거의 안 변해야 한다(낱알 복원 누적 = 층층 블러)
        var diff = 0, changed = 0, count = 0
        for t in 0..<360 {
            let xc = 70 + Int((0.44 * Double(t)).rounded()), y = 40 + t
            guard y < h else { break }
            for x in max(0, xc - 14)...min(w - 1, xc + 14) where abs(x - xc) >= 6 {
                let d = abs(lum(out, w, x, y) - lum(clean, w, x, y))
                diff += d; if d > 10 { changed += 1 }; count += 1
            }
        }
        let avgGrain = Double(diff) / Double(max(1, count))
        let fracGrain = Double(changed) / Double(max(1, count))
        print(String(format: "[diag-grain] scratch bias=%.1f (delta=%d) | grain avg=%.2f changed=%.1f%%",
                     avgBias, delta, avgGrain, fracGrain * 100))
        XCTAssertLessThan(avgBias, Double(delta) / 2, "대각 스크래치가 제거되어야 한다")
        XCTAssertLessThan(avgGrain, 3.0, "칠 안 그레인이 낱알 복원으로 층층이 밀리면 안 된다")
        XCTAssertLessThan(fracGrain, 0.06, "칠 안 그레인 픽셀이 광범위하게 변하면 안 된다")
    }

    func testWideRepairMaskKeepsPaintedTextureOutsideDefects() {
        let w = 240, h = 180
        var px = [UInt8](repeating: 0, count: w * h * 4)
        var seed: UInt64 = 0x516C
        for y in 0..<h {
            for x in 0..<w {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let grain = Int(seed >> 40) % 15 - 7
                let band = 154
                    + Int(18 * sin(Double(y) * 0.12))
                    + Int(8 * sin(Double(x) * 0.31) * sin(Double(y) * 0.21))
                    + grain
                let o = (y * w + x) * 4
                let v = UInt8(max(0, min(255, band)))
                px[o] = v; px[o + 1] = v; px[o + 2] = v; px[o + 3] = 255
            }
        }
        let clean = px
        let defects = [
            CGRect(x: 52, y: 64, width: 42, height: 12),
            CGRect(x: 122, y: 62, width: 52, height: 16),
            CGRect(x: 154, y: 118, width: 26, height: 18),
        ]
        var maskBytes = [UInt8](repeating: 0, count: w * h * 4)
        var brush = [Bool](repeating: false, count: w * h)
        var defect = [Bool](repeating: false, count: w * h)
        func inEllipse(_ rect: CGRect, _ x: Int, _ y: Int, _ pad: CGFloat = 0) -> Bool {
            let rx = rect.width / 2 + pad, ry = rect.height / 2 + pad
            let dx = (CGFloat(x) - rect.midX) / max(1, rx)
            let dy = (CGFloat(y) - rect.midY) / max(1, ry)
            return dx * dx + dy * dy <= 1
        }
        let brushRects = [
            CGRect(x: 36, y: 50, width: 78, height: 48),
            CGRect(x: 108, y: 48, width: 82, height: 52),
            CGRect(x: 140, y: 106, width: 54, height: 44),
        ]
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if brushRects.contains(where: { inEllipse($0, x, y) }) {
                    brush[i] = true
                    let o = i * 4
                    maskBytes[o] = 255; maskBytes[o + 1] = 255; maskBytes[o + 2] = 255; maskBytes[o + 3] = 255
                }
                if defects.contains(where: { inEllipse($0, x, y, 6) }) {
                    defect[i] = true
                }
                if defects.contains(where: { inEllipse($0, x, y) }) {
                    let o = i * 4
                    px[o] = 238; px[o + 1] = 238; px[o + 2] = 238
                }
            }
        }
        let img = ciImage(px, w, h)
        let mask = ciImage(maskBytes, w, h)
        let out = render(SoftwareDefectRemoval.repair(image: img,
                                            roi: CGRect(x: 0, y: 0, width: w, height: h),
                                            mask: mask,
                                            preferredAngle: 0), w, h)
        var beforeHigh = 0.0, afterHigh = 0.0, diff = 0, count = 0
        for y in 2..<(h - 2) {
            for x in 2..<(w - 2) {
                let i = y * w + x
                guard brush[i], !defect[i] else { continue }
                beforeHigh += abs(highpass(clean, w: w, x: x, y: y))
                afterHigh += abs(highpass(out, w: w, x: x, y: y))
                diff += abs(lum(out, w, x, y) - lum(clean, w, x, y))
                count += 1
            }
        }
        let ratio = afterHigh / max(0.001, beforeHigh)
        let avgDiff = Double(diff) / Double(max(1, count))
        print(String(format: "[wide-mask-texture] highpass ratio=%.3f avgDiff=%.2f", ratio, avgDiff))
        XCTAssertGreaterThan(ratio, 0.88, "넓은 브러시 마스크의 정상 질감이 저해상도처럼 밀리면 안 된다")
        XCTAssertLessThan(avgDiff, 12.0, "넓은 브러시 마스크의 정상 영역이 과하게 바뀌면 안 된다")
    }

    func testWideBrushRepairDoesNotLeaveResidualPatchOrBoundaryArtifacts() {
        let w = 260, h = 180
        var clean = [UInt8](repeating: 0, count: w * h * 4)
        var seed: UInt64 = 0xB71CE
        for y in 0..<h {
            for x in 0..<w {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let grain = Int(seed >> 41) % 13 - 6
                let weave = Int(16 * sin(Double(x) * 0.33) * sin(Double(y) * 0.27))
                let wave = Int(10 * sin(Double(y) * 0.09))
                let value = 142 + wave + weave + grain
                let o = (y * w + x) * 4
                let v = UInt8(max(0, min(255, value)))
                clean[o] = v; clean[o + 1] = v; clean[o + 2] = v; clean[o + 3] = 255
            }
        }

        var damaged = clean
        var maskBytes = [UInt8](repeating: 0, count: w * h * 4)
        var brush = [Bool](repeating: false, count: w * h)
        var defect = [Bool](repeating: false, count: w * h)
        var boundaryRing = [Bool](repeating: false, count: w * h)
        let defectRects = [
            CGRect(x: 86, y: 70, width: 52, height: 14),
            CGRect(x: 145, y: 93, width: 38, height: 18),
        ]
        let brushRect = CGRect(x: 42, y: 54, width: 172, height: 78)
        func inEllipse(_ rect: CGRect, _ x: Int, _ y: Int, _ pad: CGFloat = 0) -> Bool {
            let rx = rect.width / 2 + pad, ry = rect.height / 2 + pad
            let dx = (CGFloat(x) - rect.midX) / max(1, rx)
            let dy = (CGFloat(y) - rect.midY) / max(1, ry)
            return dx * dx + dy * dy <= 1
        }
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if brushRect.contains(CGPoint(x: x, y: y)) {
                    brush[i] = true
                    let o = i * 4
                    maskBytes[o] = 255; maskBytes[o + 1] = 255; maskBytes[o + 2] = 255; maskBytes[o + 3] = 255
                }
                if defectRects.contains(where: { inEllipse($0, x, y, 7) })
                    && !defectRects.contains(where: { inEllipse($0, x, y, 1) }) {
                    boundaryRing[i] = true
                }
                if defectRects.contains(where: { inEllipse($0, x, y) }) {
                    defect[i] = true
                    let o = i * 4
                    damaged[o] = 236; damaged[o + 1] = 236; damaged[o + 2] = 236
                }
            }
        }

        let out = render(SoftwareDefectRemoval.repair(image: ciImage(damaged, w, h),
                                            roi: CGRect(x: 0, y: 0, width: w, height: h),
                                            mask: ciImage(maskBytes, w, h),
                                            preferredAngle: 0), w, h)
        func localMean(_ px: [UInt8], _ x: Int, _ y: Int) -> Double {
            var sum = 0
            var count = 0
            for yy in (y - 4)...(y + 4) {
                for xx in (x - 4)...(x + 4) {
                    sum += lum(px, w, xx, yy)
                    count += 1
                }
            }
            return Double(sum) / Double(count)
        }

        var cleanHigh = 0.0, outHigh = 0.0, lumaDelta = 0, nonDefectCount = 0
        var ringDelta = 0, ringCount = 0
        var lowDelta = 0.0, lowCount = 0
        var residual = 0, defectDelta = 0, defectCount = 0
        var defectLowDelta = 0.0
        for y in 4..<(h - 4) {
            for x in 4..<(w - 4) {
                let i = y * w + x
                if defect[i] {
                    residual += abs(lum(out, w, x, y) - lum(clean, w, x, y))
                    defectDelta += lum(out, w, x, y) - lum(clean, w, x, y)
                    defectLowDelta += abs(localMean(out, x, y) - localMean(clean, x, y))
                    defectCount += 1
                    continue
                }
                if brush[i], !boundaryRing[i] {
                    cleanHigh += abs(highpass(clean, w: w, x: x, y: y))
                    outHigh += abs(highpass(out, w: w, x: x, y: y))
                    lumaDelta += abs(lum(out, w, x, y) - lum(clean, w, x, y))
                    nonDefectCount += 1
                    if (56..<82).contains(x) || (194..<208).contains(x) {
                        lowDelta += abs(localMean(out, x, y) - localMean(clean, x, y))
                        lowCount += 1
                    }
                }
                if boundaryRing[i] {
                    ringDelta += abs(lum(out, w, x, y) - lum(clean, w, x, y))
                    ringCount += 1
                }
            }
        }
        let nonDefectHighpassRatio = outHigh / max(0.001, cleanHigh)
        let averageNonDefectLumaDelta = Double(lumaDelta) / Double(max(1, nonDefectCount))
        let boundaryRingDelta = Double(ringDelta) / Double(max(1, ringCount))
        let lowFrequencyPatchDelta = lowDelta / Double(max(1, lowCount))
        let defectResidual = Double(residual) / Double(max(1, defectCount))
        let defectMeanDelta = Double(defectDelta) / Double(max(1, defectCount))
        let defectLowFrequencyDelta = defectLowDelta / Double(max(1, defectCount))
        let metrics = String(format: "nonDefectHighpassRatio=%.3f averageNonDefectLumaDelta=%.2f boundaryRingDelta=%.2f lowFrequencyPatchDelta=%.2f defectResidual=%.2f defectMeanDelta=%.2f defectLowFrequencyDelta=%.2f samples=%d/%d/%d/%d",
                             nonDefectHighpassRatio, averageNonDefectLumaDelta,
                             boundaryRingDelta, lowFrequencyPatchDelta, defectResidual, defectMeanDelta, defectLowFrequencyDelta,
                             nonDefectCount, ringCount, lowCount, defectCount)
        print("[wide-boundary-red] \(metrics)")
        XCTAssertLessThan(defectResidual, 8.5, "결함 자리에 과한 픽셀 잔차가 남으면 안 된다: \(metrics)")
        XCTAssertLessThan(abs(defectMeanDelta), 2.5, "결함 자리에 평균 색 편차가 보여서는 안 된다: \(metrics)")
        XCTAssertLessThan(defectLowFrequencyDelta, 4.5, "결함 자리에 저주파 색/톤 패치가 남으면 안 된다: \(metrics)")
        XCTAssertGreaterThan(nonDefectHighpassRatio, 0.92, "정상 영역 고주파 질감이 넓은 패치 복원으로 남아야 한다: \(metrics)")
        XCTAssertLessThan(averageNonDefectLumaDelta, 4.0, "정상 영역 평균 밝기 변화가 보여서는 안 된다: \(metrics)")
        XCTAssertLessThan(boundaryRingDelta, 6.0, "결함 경계 ring 에 잔여 패치/halo 가 남으면 안 된다: \(metrics)")
        XCTAssertLessThan(lowFrequencyPatchDelta, 3.5, "넓은 브러시 안 저주파 patch 변화가 보여서는 안 된다: \(metrics)")
    }

    func testWideBrushRepairAcrossHorizontalVerticalAndDiagonalDirections() {
        let cases: [(name: String, angle: Double)] = [
            ("horizontal", 0),
            ("vertical", 90),
            ("diagonalDown", 45),
            ("diagonalUp", 135),
        ]
        for item in cases {
            let metrics = wideBrushResidualMetrics(preferredAngle: item.angle)
            print("[wide-direction-\(item.name)] \(metrics.description)")
            XCTAssertLessThan(metrics.defectResidual, 7.0,
                              "\(item.name): 결함 자리에 과한 픽셀 잔차가 남으면 안 된다: \(metrics.description)")
            XCTAssertLessThan(abs(metrics.defectMeanDelta), 2.5,
                              "\(item.name): 결함 자리에 평균 색 편차가 보여서는 안 된다: \(metrics.description)")
            XCTAssertLessThan(metrics.defectLowFrequencyDelta, 3.2,
                              "\(item.name): 결함 자리에 저주파 색/톤 패치가 남으면 안 된다: \(metrics.description)")
            XCTAssertGreaterThan(metrics.nonDefectHighpassRatio, 0.92,
                                 "\(item.name): 정상 영역 고주파 질감이 남아야 한다: \(metrics.description)")
            XCTAssertLessThan(metrics.averageNonDefectLumaDelta, 4.0,
                              "\(item.name): 정상 브러시 영역 평균 밝기 변화가 보여서는 안 된다: \(metrics.description)")
            XCTAssertLessThan(metrics.boundaryRingDelta, 6.0,
                              "\(item.name): 결함 경계 halo 가 보여서는 안 된다: \(metrics.description)")
            XCTAssertLessThan(metrics.lowFrequencyPatchDelta, 3.5,
                              "\(item.name): 넓은 저주파 patch 변화가 보여서는 안 된다: \(metrics.description)")
        }
    }

    private struct WideBrushMetrics: CustomStringConvertible {
        let nonDefectHighpassRatio: Double
        let averageNonDefectLumaDelta: Double
        let boundaryRingDelta: Double
        let lowFrequencyPatchDelta: Double
        let defectResidual: Double
        let defectMeanDelta: Double
        let defectLowFrequencyDelta: Double
        let nonDefectCount: Int
        let ringCount: Int
        let lowCount: Int
        let defectCount: Int

        var description: String {
            String(format: "nonDefectHighpassRatio=%.3f averageNonDefectLumaDelta=%.2f boundaryRingDelta=%.2f lowFrequencyPatchDelta=%.2f defectResidual=%.2f defectMeanDelta=%.2f defectLowFrequencyDelta=%.2f samples=%d/%d/%d/%d",
                   nonDefectHighpassRatio, averageNonDefectLumaDelta,
                   boundaryRingDelta, lowFrequencyPatchDelta, defectResidual, defectMeanDelta, defectLowFrequencyDelta,
                   nonDefectCount, ringCount, lowCount, defectCount)
        }
    }

    private func wideBrushResidualMetrics(preferredAngle: Double) -> WideBrushMetrics {
        let w = 280, h = 240
        let rad = preferredAngle * .pi / 180
        let ax = cos(rad), ay = sin(rad)
        let px = -sin(rad), py = cos(rad)
        let cx = Double(w) / 2, cy = Double(h) / 2
        var clean = [UInt8](repeating: 0, count: w * h * 4)
        var seed: UInt64 = 0xD1A601CE
        for y in 0..<h {
            for x in 0..<w {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let grain = Int(seed >> 41) % 13 - 6
                let dx = Double(x) - cx, dy = Double(y) - cy
                let u = dx * ax + dy * ay
                let vCoord = dx * px + dy * py
                let weave = Int(15 * sin(u * 0.31) * sin(vCoord * 0.23))
                let wave = Int(9 * sin(vCoord * 0.08) + 5 * sin(u * 0.05))
                let value = 142 + wave + weave + grain
                let o = (y * w + x) * 4
                let v = UInt8(max(0, min(255, value)))
                clean[o] = v; clean[o + 1] = v; clean[o + 2] = v; clean[o + 3] = 255
            }
        }

        func project(_ x: Int, _ y: Int, centerX: Double = cx, centerY: Double = cy) -> (u: Double, v: Double) {
            let dx = Double(x) - centerX, dy = Double(y) - centerY
            return (dx * ax + dy * ay, dx * px + dy * py)
        }
        func point(_ u: Double, _ v: Double) -> (x: Double, y: Double) {
            (cx + ax * u + px * v, cy + ay * u + py * v)
        }
        func inRotatedRect(_ x: Int, _ y: Int, length: Double, width: Double) -> Bool {
            let p = project(x, y)
            return abs(p.u) <= length / 2 && abs(p.v) <= width / 2
        }
        func inRotatedEllipse(_ x: Int, _ y: Int, center: (x: Double, y: Double),
                              length: Double, thickness: Double, pad: Double = 0) -> Bool {
            let p = project(x, y, centerX: center.x, centerY: center.y)
            let rx = max(1, length / 2 + pad)
            let ry = max(1, thickness / 2 + pad)
            let du = p.u / rx, dv = p.v / ry
            return du * du + dv * dv <= 1
        }

        let defects = [
            (center: point(-36, -10), length: 52.0, thickness: 14.0),
            (center: point(32, 13), length: 40.0, thickness: 18.0),
        ]
        var damaged = clean
        var maskBytes = [UInt8](repeating: 0, count: w * h * 4)
        var brush = [Bool](repeating: false, count: w * h)
        var defect = [Bool](repeating: false, count: w * h)
        var boundaryRing = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if inRotatedRect(x, y, length: 174, width: 78) {
                    brush[i] = true
                    let o = i * 4
                    maskBytes[o] = 255; maskBytes[o + 1] = 255; maskBytes[o + 2] = 255; maskBytes[o + 3] = 255
                }
                if defects.contains(where: { inRotatedEllipse(x, y, center: $0.center, length: $0.length, thickness: $0.thickness, pad: 7) })
                    && !defects.contains(where: { inRotatedEllipse(x, y, center: $0.center, length: $0.length, thickness: $0.thickness, pad: 1) }) {
                    boundaryRing[i] = true
                }
                if defects.contains(where: { inRotatedEllipse(x, y, center: $0.center, length: $0.length, thickness: $0.thickness) }) {
                    defect[i] = true
                    let o = i * 4
                    damaged[o] = 236; damaged[o + 1] = 236; damaged[o + 2] = 236
                }
            }
        }

        let out = render(SoftwareDefectRemoval.repair(image: ciImage(damaged, w, h),
                                            roi: CGRect(x: 0, y: 0, width: w, height: h),
                                            mask: ciImage(maskBytes, w, h),
                                            preferredAngle: preferredAngle), w, h)
        func localMean(_ px: [UInt8], _ x: Int, _ y: Int) -> Double {
            var sum = 0
            var count = 0
            for yy in (y - 4)...(y + 4) {
                for xx in (x - 4)...(x + 4) {
                    sum += lum(px, w, xx, yy)
                    count += 1
                }
            }
            return Double(sum) / Double(count)
        }

        var cleanHigh = 0.0, outHigh = 0.0, lumaDelta = 0, nonDefectCount = 0
        var ringDelta = 0, ringCount = 0
        var lowDelta = 0.0, lowCount = 0
        var residual = 0, defectDelta = 0, defectCount = 0
        var defectLowDelta = 0.0
        for y in 4..<(h - 4) {
            for x in 4..<(w - 4) {
                let i = y * w + x
                if defect[i] {
                    residual += abs(lum(out, w, x, y) - lum(clean, w, x, y))
                    defectDelta += lum(out, w, x, y) - lum(clean, w, x, y)
                    defectLowDelta += abs(localMean(out, x, y) - localMean(clean, x, y))
                    defectCount += 1
                    continue
                }
                if brush[i], !boundaryRing[i] {
                    cleanHigh += abs(highpass(clean, w: w, x: x, y: y))
                    outHigh += abs(highpass(out, w: w, x: x, y: y))
                    lumaDelta += abs(lum(out, w, x, y) - lum(clean, w, x, y))
                    nonDefectCount += 1
                    let p = project(x, y)
                    if abs(p.u) > 54 || abs(p.v) > 26 {
                        lowDelta += abs(localMean(out, x, y) - localMean(clean, x, y))
                        lowCount += 1
                    }
                }
                if boundaryRing[i] {
                    ringDelta += abs(lum(out, w, x, y) - lum(clean, w, x, y))
                    ringCount += 1
                }
            }
        }
        return WideBrushMetrics(
            nonDefectHighpassRatio: outHigh / max(0.001, cleanHigh),
            averageNonDefectLumaDelta: Double(lumaDelta) / Double(max(1, nonDefectCount)),
            boundaryRingDelta: Double(ringDelta) / Double(max(1, ringCount)),
            lowFrequencyPatchDelta: lowDelta / Double(max(1, lowCount)),
            defectResidual: Double(residual) / Double(max(1, defectCount)),
            defectMeanDelta: Double(defectDelta) / Double(max(1, defectCount)),
            defectLowFrequencyDelta: defectLowDelta / Double(max(1, defectCount)),
            nonDefectCount: nonDefectCount,
            ringCount: ringCount,
            lowCount: lowCount,
            defectCount: defectCount
        )
    }

    // MARK: 저대비 결함 제거 성능 가드 — 위 구조 가드가 이걸 깨면 안 된다(과거 롤백 원인)

    /// raw 도메인의 실제 스크래치는 저대비(±10~20/255)·비직선이다. 가드 적용 후에도 제거돼야 한다.
    func testFaintWavyThinScratchStillRemoved() {
        let w = 200, h = 200, delta = 13
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        addGrain(&px, w: w, h: h, amp: 5, seed: 0x5C27)
        let clean = px
        var pts: [(Int, Int)] = []
        for y in 8..<192 {
            let x = 100 + Int((8 * sin(Double(y) * 0.14)).rounded())
            pts.append((x, y))
        }
        for (x, y) in pts {
            let o = (y * w + x) * 4
            let v = UInt8(min(255, Int(px[o]) + delta))
            px[o] = v; px[o + 1] = v; px[o + 2] = v
        }
        let img = ciImage(px, w, h)
        let brush = brushBand(w: w, h: h, x0: 86, x1: 114)
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        var bias = 0
        for (x, y) in pts { bias += lum(out, w, x, y) - lum(clean, w, x, y) }
        let avgBias = Double(bias) / Double(pts.count)
        print(String(format: "[wavy-faint] leftover bias=%.1f (delta=%d)", avgBias, delta))
        XCTAssertLessThan(avgBias, Double(delta) / 2, "저대비 굽은 얇은 스크래치 제거가 가드로 인해 깨짐")
    }

    /// 그레인 위 저대비 꼬불꼬불(불규칙) 결함 — 가드 적용 후에도 제거돼야 한다.
    func testFaintIrregularCurlStillRemoved() {
        let w = 200, h = 200, delta = 15
        var px = scene(w: w, h: h, scratchX: -10, scratchW: 0, delta: 0)
        addGrain(&px, w: w, h: h, amp: 5, seed: 0x1CE)
        let clean = px
        var pts: [(Int, Int)] = []
        for t in 0..<70 {
            let x = 100 + Int((7 * sin(Double(t) * 0.45)).rounded())
            let y = 60 + t
            pts.append((x, y)); pts.append((x + 1, y))
        }
        for (x, y) in pts {
            let o = (y * w + x) * 4
            let v = UInt8(min(255, Int(px[o]) + delta))
            px[o] = v; px[o + 1] = v; px[o + 2] = v
        }
        let img = ciImage(px, w, h)
        let brush = brushBand(w: w, h: h, x0: 84, x1: 116)
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        var bias = 0
        for (x, y) in pts { bias += lum(out, w, x, y) - lum(clean, w, x, y) }
        let avgBias = Double(bias) / Double(pts.count)
        print(String(format: "[curl-faint] leftover bias=%.1f (delta=%d)", avgBias, delta))
        XCTAssertLessThan(avgBias, Double(delta) / 2, "저대비 불규칙 결함 제거가 가드로 인해 깨짐")
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
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
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
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
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
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
                                           repairExtent: CGRect(x: 0, y: 0, width: w, height: h)), w, h)
        let bg = 60 + 120 * cx / w
        print("[faint-fat] center \(lum(px, w, cx, cy))→\(lum(out, w, cx, cy)) (bg≈\(bg))")
        XCTAssertLessThan(abs(lum(out, w, cx, cy) - bg), 20, "흐릿한 뚱뚱한 먼지가 안 지워짐")
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
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        let out = render(SoftwareDefectRemoval.apply(to: img, parameters: params, brush: brush,
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
