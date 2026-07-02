import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// SoftwareICE.detectComponents / repair (Region ICE 분리 진입점) 검증.
//  1) build 보존: buildLabeled→renderMask 가 기존 build 와 동일 마스크(정수 비교).
//  2) end-to-end: 검출→복원으로 결함 제거 + 배경 보존, 좌표 정합, 클릭 제외 반영.
final class RegionICEEntryTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    private func ciImage(_ px: [UInt8], _ w: Int, _ h: Int) -> CIImage {
        CIImage(bitmapData: Data(px), bytesPerRow: w * 4,
                size: CGSize(width: w, height: h), format: .RGBA8, colorSpace: linear)
    }
    private func render(_ img: CIImage, _ w: Int, _ h: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        CIContext(options: [.workingColorSpace: linear]).render(
            img, toBitmap: &out, rowBytes: w * 4,
            bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8, colorSpace: linear)
        return out
    }
    private func lum(_ a: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> Int { Int(a[(y * w + x) * 4]) }

    private func gray(_ w: Int, _ h: Int, _ base: Int) -> [UInt8] {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) { let o = i * 4; px[o] = UInt8(base); px[o + 1] = UInt8(base); px[o + 2] = UInt8(base) }
        return px
    }

    // 1) build(RGBA8) == buildLabeled→renderMask(전체 선택). 브러시 마스크 보존을 정수로 보장.
    func testLabeledRenderMatchesBuild() {
        let w = 80, h = 60
        var dust = [Bool](repeating: false, count: w * h)
        var scratch = [Bool](repeating: false, count: w * h)
        for dy in -1...1 { for dx in -1...1 { dust[(20 + dy) * w + (20 + dx)] = true } }
        for dy in -1...1 { for dx in -1...1 { dust[(15 + dy) * w + (55 + dx)] = true } }
        for y in 10..<50 { scratch[y * w + 40] = true }
        let maxDustArea = 150, minLen = 8, dilate = 2
        let built = ICEComponentMask.build(width: w, height: h, dust: dust, scratch: scratch,
                                           maxDustArea: maxDustArea, minScratchLength: minLen,
                                           minScratchAspect: 2.5, dustDilate: dilate)
        let field = ICEComponentMask.buildLabeled(width: w, height: h, dust: dust, scratch: scratch,
                                                  maxDustArea: maxDustArea, minScratchLength: minLen,
                                                  minScratchAspect: 2.5)
        let rendered = ICEComponentMask.renderMask(field, excluded: [], dustDilate: dilate)
        XCTAssertEqual(built, rendered, "buildLabeled+renderMask가 build와 다른 마스크를 냄")
    }

    // 2) 세로 스크래치 검출→복원 제거 + 배경 보존.
    func testDetectComponentsThenRepairRemovesScratch() {
        let w = 160, h = 160, base = 120, dx = 80
        var px = gray(w, h, base)
        for y in 0..<h { let o = (y * w + dx) * 4; px[o] = 190; px[o + 1] = 190; px[o + 2] = 190 }
        let img = ciImage(px, w, h)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6, scratchSensitivity: 0.7, protectDetail: 0.6)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let field = SoftwareICE.detectComponents(in: img, roi: roi, parameters: params)
        XCTAssertFalse(field.isEmpty, "세로 스크래치가 검출되어야 한다")
        let maskBytes = ICEComponentMask.renderMask(field, excluded: [], dustDilate: 2)
        let out = render(SoftwareICE.repair(image: img, roi: roi, mask: ciImage(maskBytes, w, h)), w, h)
        XCTAssertLessThan(abs(lum(out, w, dx, 80) - base), 24, "스크래치가 제거되어야 한다")
        XCTAssertLessThan(abs(lum(out, w, 20, 80) - base), 6, "결함 없는 배경은 보존되어야 한다")
    }

    // 3) 좌표 정합: 비대칭 위치의 점 먼지가 정확히 그 자리에서만 제거된다(배열↔CIImage y 정합 가드).
    func testDotDustRepairedAtCorrectPosition() {
        let w = 120, h = 120, base = 120, dotX = 50, dotY = 30
        var px = gray(w, h, base)
        for yy in (dotY - 2)..<(dotY + 2) { for xx in (dotX - 2)..<(dotX + 2) {
            let o = (yy * w + xx) * 4; px[o] = 205; px[o + 1] = 205; px[o + 2] = 205
        } }
        let img = ciImage(px, w, h)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6, scratchSensitivity: 0.7, protectDetail: 0.6)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let field = SoftwareICE.detectComponents(in: img, roi: roi, parameters: params)
        XCTAssertFalse(field.isEmpty, "점 먼지가 검출되어야 한다")
        let maskBytes = ICEComponentMask.renderMask(field, excluded: [], dustDilate: 2)
        let out = render(SoftwareICE.repair(image: img, roi: roi, mask: ciImage(maskBytes, w, h)), w, h)
        XCTAssertLessThan(abs(lum(out, w, dotX, dotY) - base), 26, "점 먼지가 그 위치에서 제거되어야 한다")
        XCTAssertLessThan(abs(lum(out, w, dotX, dotY + 40) - base), 6, "먼지 아래(결함 없음)는 보존")
        XCTAssertLessThan(abs(lum(out, w, dotX + 40, dotY) - base), 6, "먼지 옆(결함 없음)은 보존")
    }

    // 4) 클릭 제외 end-to-end: 제외한 컴포넌트는 복원되지 않고, 나머지는 제거된다.
    func testExcludedComponentNotRepaired() {
        let w = 160, h = 120, base = 120
        var px = gray(w, h, base)
        for y in 0..<h { for x in [40, 110] { let o = (y * w + x) * 4; px[o] = 190; px[o + 1] = 190; px[o + 2] = 190 } }
        let img = ciImage(px, w, h)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6, scratchSensitivity: 0.7, protectDetail: 0.6)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let field = SoftwareICE.detectComponents(in: img, roi: roi, parameters: params)
        XCTAssertGreaterThanOrEqual(field.components.count, 2, "두 스크래치가 검출되어야 한다")
        guard let excludeID = field.nearestComponentID(atX: 40, y: 60, radius: 3) else {
            return XCTFail("좌측 스크래치 컴포넌트를 찾지 못함")
        }
        let maskBytes = ICEComponentMask.renderMask(field, excluded: [excludeID], dustDilate: 2)
        let out = render(SoftwareICE.repair(image: img, roi: roi, mask: ciImage(maskBytes, w, h)), w, h)
        XCTAssertGreaterThan(lum(out, w, 40, 60) - base, 30, "제외한 스크래치는 남아야 한다")
        XCTAssertLessThan(abs(lum(out, w, 110, 60) - base), 24, "제외하지 않은 스크래치는 제거되어야 한다")
    }

    // 5) 타일링: 타일 경계에 걸친 먼지까지 모두 검출(halo) + 중복 없이 정확한 개수(centroid-in-core).
    func testTiledDetectionCoversAllDustNoDuplicates() {
        let w = 600, h = 200, base = 120
        var px = gray(w, h, base)
        let dots = [(50, 100), (200, 100), (400, 100), (550, 100), (300, 60)]   // 200,400 = 타일 경계
        for (cx, cy) in dots {
            for yy in (cy - 2)..<(cy + 2) { for xx in (cx - 2)..<(cx + 2) {
                let o = (yy * w + xx) * 4; px[o] = 205; px[o + 1] = 205; px[o + 2] = 205
            } }
        }
        let img = ciImage(px, w, h)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6, scratchSensitivity: 0.7, protectDetail: 0.6)
        let field = SoftwareICE.detectComponents(in: img, roi: CGRect(x: 0, y: 0, width: w, height: h),
                                                 parameters: params, tileMax: 200, halo: 48)
        for (cx, cy) in dots {
            XCTAssertNotNil(field.nearestComponentID(atX: cx, y: cy, radius: 4), "(\(cx),\(cy)) 먼지 미검출(타일 경계/halo)")
        }
        XCTAssertEqual(field.components.count, dots.count, "타일 병합에서 중복/누락 발생")
    }

    // 6) 성능 실측: 큰 ROI 의 타일 병렬 검출이 "몇 초 내외"인지 Release 에서 측정한다.
    //    Debug(-Onone)는 픽셀 루프가 수배 느리므로 평소엔 skip; ICE_PERF=1 일 때만 측정한다.
    func testDetectionPerformanceLargeROI() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ICE_PERF"] != nil,
                          "성능 측정은 ICE_PERF=1 + Release(-c release)에서만 의미가 있다")
        let w = 1600, h = 1600, base = 120
        var px = gray(w, h, base)
        var dots = 0
        for gy in stride(from: 150, to: 1500, by: 280) {
            for gx in stride(from: 150, to: 1500, by: 280) {
                for yy in (gy - 2)..<(gy + 2) { for xx in (gx - 2)..<(gx + 2) {
                    let o = (yy * w + xx) * 4; px[o] = 205; px[o + 1] = 205; px[o + 2] = 205
                } }
                dots += 1
            }
        }
        let img = ciImage(px, w, h)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6, scratchSensitivity: 0.7, protectDetail: 0.6)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let t0 = Date()
        let field = SoftwareICE.detectComponents(in: img, roi: roi, parameters: params, tileMax: 1400, halo: 48)
        let dt = Date().timeIntervalSince(t0)
        print("[perf] 1600x1600 tiled detect = \(String(format: "%.2f", dt))s, comps=\(field.components.count), dots=\(dots)")
        XCTAssertGreaterThanOrEqual(field.components.count, dots - 2, "대부분 먼지가 검출되어야 한다")
    }

    // 7) 회귀 가드: 결함이 전혀 없는 그레인+그라데이션 평면(하늘 등)을 결함으로 폭발 검출하면 안 된다.
    //    과거 버그: Region ICE 가 ROI 를 "결함 보증"으로 보고 brush 의 공격 임계 + ROI×0.6 면적 상한을
    //    적용해, 평탄/그레인 픽셀 수만 개가 결함으로 잡히고 슬라이더를 올리면 ROI 전체가 한 덩어리가 됐다.
    //    이제 ROI 는 범위 제한일 뿐이고 보수 자동 검출이 돈다 → 결함 없는 면은 거의 비어야 한다.
    func testDetectComponentsDoesNotExplodeOnGrainGradient() {
        let w = 300, h = 300
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let grad = 150.0 + Double(y) / Double(h) * 60.0      // 완만한 세로 그라데이션(150→210)
                let n = Double((x * 7 + y * 13) % 5 - 2) * 1.5       // ±3/255 결정적 그레인
                let v = UInt8(max(0, min(255, grad + n)))
                let o = (y * w + x) * 4; px[o] = v; px[o + 1] = v; px[o + 2] = v
            }
        }
        let img = ciImage(px, w, h)
        // 슬라이더 최대(최악 민감도)에서도 폭발하면 안 된다.
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 1.0, scratchSensitivity: 1.0, protectDetail: 0.6)
        let field = SoftwareICE.detectComponents(in: img, roi: CGRect(x: 0, y: 0, width: w, height: h), parameters: params)
        XCTAssertLessThan(field.components.count, 20, "결함 없는 평면을 대량 오검출하면 안 된다(검출 \(field.components.count)개)")
        let maskBytes = ICEComponentMask.renderMask(field, excluded: [], dustDilate: 2)
        var covered = 0
        for i in 0..<(w * h) where maskBytes[i * 4] > 0 { covered += 1 }
        let ratio = Double(covered) / Double(w * h)
        XCTAssertLessThan(ratio, 0.02, "결함 없는 평면의 2% 이상이 마스킹되면 안 된다(\(String(format: "%.1f", ratio * 100))% 마스킹)")
    }

    // 8) 회귀 가드: ROI 가 이미지 일부일 때 repair 는 ROI 밖을 보존한 "전체 이미지"를 돌려줘야 한다.
    //    과거 버그: 복원 후 ROI 로 다시 crop 해 ROI 조각만 반환 → createCGImage(from: 원본 전체)에서
    //    ROI 밖이 0(검정)으로 채워져 "검은 배경 + 깨진 네모" 결과가 나왔다.
    func testRepairReturnsFullImageNotJustROI() {
        let w = 120, h = 120, base = 120
        var px = gray(w, h, base)
        for yy in 58..<62 { for xx in 58..<62 {   // 중앙 점 먼지(ROI 안)
            let o = (yy * w + xx) * 4; px[o] = 205; px[o + 1] = 205; px[o + 2] = 205
        } }
        let img = ciImage(px, w, h)
        let roi = CGRect(x: 35, y: 35, width: 50, height: 50)   // 전체보다 작은 부분 ROI
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.6, scratchSensitivity: 0.7, protectDetail: 0.6)
        let field = SoftwareICE.detectComponents(in: img, roi: roi, parameters: params)
        XCTAssertFalse(field.isEmpty, "ROI 안 점 먼지가 검출되어야 한다")
        guard let repaired = SoftwareICE.repairComponents(image: img, roi: roi, field: field, excluded: []) else {
            return XCTFail("repairComponents 가 nil")
        }
        XCTAssertEqual(repaired.extent, img.extent, "repair 결과는 원본 전체 extent 여야 한다(ROI 조각 아님)")
        let out = render(repaired, w, h)
        XCTAssertLessThan(abs(lum(out, w, 5, 5) - base), 5, "ROI 밖 픽셀은 원본 그대로 보존(검정 0 이 아님)")
        XCTAssertLessThan(abs(lum(out, w, 114, 114) - base), 5, "ROI 밖 반대 코너도 보존")
    }

    // 9) 뚱뚱한 먼지: 높은 민감도(슬라이더 우측)에서 maxDustArea 가 커져 큰 blob 도 검출돼야 한다.
    //    (보수 기본 maxDustArea 로는 reject 되던 크기 — 강도 상향이 형태 게이트까지 푸는지 확인.)
    func testFatDustDetectedAtHighSensitivity() {
        let w = 240, h = 240, base = 120
        var px = gray(w, h, base)
        for yy in 108..<132 { for xx in 108..<132 {   // 24×24 뚱뚱한 먼지(면적 576)
            let o = (yy * w + xx) * 4; px[o] = 210; px[o + 1] = 210; px[o + 2] = 210
        } }
        let img = ciImage(px, w, h)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let high = SoftwareICE.detectComponents(in: img, roi: roi,
            parameters: SoftwareICEParameters(strength: 1, dustSensitivity: 1.0, scratchSensitivity: 1.0, protectDetail: 0.6))
        XCTAssertNotNil(high.nearestComponentID(atX: 119, y: 119, radius: 8),
                        "높은 민감도에서 뚱뚱한 먼지가 검출돼야 한다")
    }

    // 10) 두꺼운 스크래치: 폭이 굵어 ridge 가 안 잡히고 aspect 가 커 dust 게이트에서도 빠지던 사각지대.
    //     폭(두께) 기반 게이트로 검출되고, 폭 중앙까지 마스크에 들어가 복원으로 완전 제거돼야 한다.
    func testThickScratchDetectedAndRepaired() {
        let w = 200, h = 200, base = 120
        var px = gray(w, h, base)
        for y in 40..<160 { for x in 96..<103 {   // 폭 7 × 길이 120 세로 스크래치
            let o = (y * w + x) * 4; px[o] = 250; px[o + 1] = 250; px[o + 2] = 250
        } }
        let img = ciImage(px, w, h)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 1.0, scratchSensitivity: 1.0, protectDetail: 0.6)
        let field = SoftwareICE.detectComponents(in: img, roi: roi, parameters: params)
        XCTAssertFalse(field.isEmpty, "두꺼운 스크래치가 검출돼야 한다")
        let maskBytes = ICEComponentMask.renderMask(field, excluded: [], dustDilate: 2)
        XCTAssertGreaterThan(Int(maskBytes[(100 * w + 99) * 4]), 0, "두꺼운 스크래치의 폭 중앙이 마스크에 포함돼야 한다")
        let out = render(SoftwareICE.repair(image: img, roi: roi, mask: ciImage(maskBytes, w, h)), w, h)
        XCTAssertLessThan(abs(lum(out, w, 99, 100) - base), 28, "두꺼운 스크래치 폭 중앙이 제거돼야 한다")
        XCTAssertLessThan(abs(lum(out, w, 30, 100) - base), 6, "결함 없는 배경은 보존돼야 한다")
    }

    // 12) 회귀 가드: 고리(loop)로 말린 결함(둥근 머리카락 등)의 안쪽 "정상 영역"이 커밋 마스크에
    //     포함되면 안 된다. 과거 버그: 커밋 마스크 렌더(componentMaskBytes→renderMask)가 내부 hole
    //     채움을 ROI 전체 면적 한도(사실상 무제한)로 수행하고 dilate(r2)가 근접 고리를 닫아, 고리 안
    //     정상 콘텐츠가 통째로 마스크→재합성되어 "일부분 블러" 패치가 생겼다. 이 픽셀들은 빨강
    //     미리보기(comp.pixels)에 없어 사용자에게 보이지도 않았다.
    func testLoopDefectInteriorNotWiped() {
        let w = 240, h = 240, base = 120, cx = 120, cy = 120
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                // 검출 임계 아래 세로 줄무늬(±10) — 안쪽이 재합성되면 사라지는 측정 가능한 구조.
                let v = base + (((x / 3) % 2 == 0) ? 10 : -10)
                let o = (y * w + x) * 4
                px[o] = UInt8(v); px[o + 1] = UInt8(v); px[o + 2] = UInt8(v)
            }
        }
        let clean = px
        for yy in (cy - 31)...(cy + 31) {          // 반지름 28, 두께 ~2.6 밝은 고리(말린 머리카락)
            for xx in (cx - 31)...(cx + 31) {
                let d = Double((xx - cx) * (xx - cx) + (yy - cy) * (yy - cy)).squareRoot()
                guard abs(d - 28) <= 1.3 else { continue }
                let o = (yy * w + xx) * 4
                px[o] = 245; px[o + 1] = 245; px[o + 2] = 245
            }
        }
        let img = ciImage(px, w, h)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 1.0, scratchSensitivity: 1.0, protectDetail: 0.6)
        let field = SoftwareICE.detectComponents(in: img, roi: roi, parameters: params)
        XCTAssertFalse(field.isEmpty, "고리 결함이 검출되어야 한다")
        let maskBytes = SoftwareICE.componentMaskBytes(field: field, excluded: [])   // 커밋과 동일 진입점
        var interiorMasked = 0, interiorCount = 0
        for yy in (cy - 20)...(cy + 20) {
            for xx in (cx - 20)...(cx + 20) where (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy) <= 400 {
                if maskBytes[(yy * w + xx) * 4] > 0 { interiorMasked += 1 }
                interiorCount += 1
            }
        }
        let maskedFrac = Double(interiorMasked) / Double(interiorCount)
        let out = render(SoftwareICE.repair(image: img, roi: roi, mask: ciImage(maskBytes, w, h)), w, h)
        var diff = 0
        for yy in (cy - 20)...(cy + 20) {
            for xx in (cx - 20)...(cx + 20) where (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy) <= 400 {
                diff += abs(lum(out, w, xx, yy) - lum(clean, w, xx, yy))
            }
        }
        let avgInterior = Double(diff) / Double(interiorCount)
        var ringResid = 0, ringCount = 0
        for a in stride(from: 0.0, to: 360.0, by: 45.0) {
            let xx = cx + Int((28 * cos(a * .pi / 180)).rounded())
            let yy = cy + Int((28 * sin(a * .pi / 180)).rounded())
            ringResid += abs(lum(out, w, xx, yy) - lum(clean, w, xx, yy)); ringCount += 1
        }
        print(String(format: "[loop] interior masked=%.0f%% interior change=%.2f ring residual=%d",
                     maskedFrac * 100, avgInterior, ringResid / ringCount))
        XCTAssertLessThan(maskedFrac, 0.05, "고리 안 정상 영역이 커밋 마스크에 포함됨(미리보기에 없는 픽셀)")
        XCTAssertLessThan(avgInterior, 3.0, "고리 안 정상 줄무늬가 재합성됨(일부분 블러 회귀)")
        XCTAssertLessThan(ringResid / ringCount, 30, "고리 결함 자체는 제거되어야 한다")
    }

    // 11) 통합 편집 누적 불변식: 두 영역을 순차로 복원하면 둘 다 제거되고, 먼저 복원한 것이 나중
    //     복원으로 되살아나지 않는다. 브러시↔반자동 통합(cleaned raw = 원본 + edits 순차 적용)이
    //     서로 덮어쓰지 않음을 보장하는 핵심 성질이다.
    func testSequentialMaskRepairsAccumulate() {
        let w = 160, h = 160, base = 120
        var px = gray(w, h, base)
        for y in 20..<140 { for x in 40..<42 { let o = (y * w + x) * 4; px[o] = 205; px[o + 1] = 205; px[o + 2] = 205 } }
        for y in 20..<140 { for x in 120..<122 { let o = (y * w + x) * 4; px[o] = 205; px[o + 1] = 205; px[o + 2] = 205 } }
        let img = ciImage(px, w, h)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        func mask(_ xs: Range<Int>) -> CIImage {
            var m = [UInt8](repeating: 0, count: w * h * 4)
            for y in 20..<140 { for x in xs { let o = (y * w + x) * 4; m[o] = 255; m[o + 1] = 255; m[o + 2] = 255; m[o + 3] = 255 } }
            return ciImage(m, w, h)
        }
        // 순차: 좌(A) 복원 → 그 결과 위에 우(B) 복원. A 는 B 복원 후에도 base 로 남아야 한다.
        let after1 = SoftwareICE.repair(image: img, roi: roi, mask: mask(39..<43))
        let after2 = SoftwareICE.repair(image: after1, roi: roi, mask: mask(119..<123))
        let out = render(after2, w, h)
        XCTAssertLessThan(abs(lum(out, w, 40, 80) - base), 26, "먼저 복원한 좌 결함이 우 복원 후에도 유지(되살아나면 안 됨)")
        XCTAssertLessThan(abs(lum(out, w, 120, 80) - base), 26, "나중 복원한 우 결함도 제거")
        XCTAssertLessThan(abs(lum(out, w, 80, 80) - base), 6, "두 영역 사이 배경은 보존")
    }
}
