import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// 가이드 영역 결함 제거가 결함 종류 전반(먼지/스크래치/머리카락 — 두께·길이·곡률 다양)을 모두 검출·복원
// 하는지 합성으로 검증한다. 학술 분류(dust, short/long hair, scratch)를 모두 커버한다.
// 각 케이스: 결함 픽셀 생성 → detectComponents → renderMask 커버율 측정 → 복원 후 잔존 측정.
final class RegionDefectHardCasesTests: XCTestCase {
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
    private func paint(_ px: inout [UInt8], _ w: Int, _ h: Int, _ x: Int, _ y: Int, _ v: Int) {
        guard x >= 0, y >= 0, x < w, y < h else { return }
        let o = (y * w + x) * 4; px[o] = UInt8(v); px[o + 1] = UInt8(v); px[o + 2] = UInt8(v)
    }
    private let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 1.0,
                                               scratchSensitivity: 1.0, protectDetail: 0.6)
    private let defectV = 245   // 밝은 결함(긁힘/이물). sRGB 변환 후에도 충분한 대비.

    /// 결함 픽셀 좌표 리스트를 만들고, detectComponents→renderMask 가 그 픽셀들을 얼마나 덮는지 + 복원 후
    /// 결함 위치가 배경으로 돌아오는지 측정한다.
    private func measure(_ name: String, w: Int, h: Int, base: Int,
                        defect: [(Int, Int)]) -> (coverage: Double, comps: Int, leftover: Double) {
        var px = bg(w, h, base)
        for (x, y) in defect { paint(&px, w, h, x, y, defectV) }
        let img = ci(px, w, h)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let field = SoftwareDefectRemoval.detectComponents(in: img, roi: roi, parameters: params)
        let mask = DefectComponentMask.renderMask(field, excluded: [], maxHoleArea: w * h, dustDilate: 2)
        var covered = 0
        for (x, y) in defect where mask[(y * w + x) * 4] > 0 { covered += 1 }
        let coverage = defect.isEmpty ? 0 : Double(covered) / Double(defect.count)
        // 복원 후 결함 위치 평균 잔존(0=완전 제거, defectV-base=미제거)
        let out = render(SoftwareDefectRemoval.repair(image: img, roi: roi, mask: ci(mask, w, h)), w, h)
        var sum = 0
        for (x, y) in defect { sum += abs(lum(out, w, x, y) - base) }
        let leftover = defect.isEmpty ? 0 : Double(sum) / Double(defect.count)
        print(String(format: "[hardcase] %@: coverage=%.0f%% comps=%d leftover=%.0f (defect=%d)",
                     name, coverage * 100, field.components.count, leftover, defectV - base))
        return (coverage, field.components.count, leftover)
    }

    // MARK: 결함 모양 생성

    private func fatDust(_ cx: Int, _ cy: Int, _ r: Int) -> [(Int, Int)] {
        var p: [(Int, Int)] = []
        for y in (cy - r)...(cy + r) { for x in (cx - r)...(cx + r) where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r { p.append((x, y)) } }
        return p
    }
    private func vLine(_ x: Int, _ y0: Int, _ y1: Int, halfWidth: Int) -> [(Int, Int)] {
        var p: [(Int, Int)] = []
        for y in y0...y1 { for dx in -halfWidth...halfWidth { p.append((x + dx, y)) } }
        return p
    }
    /// 사인 곡선 머리카락(가늘고 굽음). 인접 표본을 라인으로 이어 연속 곡선으로 만든다(실제 머리카락).
    private func curlyHair(_ x0: Int, _ y0: Int, length: Int, amp: Double, halfWidth: Int) -> [(Int, Int)] {
        var seen = Set<Int>()
        var p: [(Int, Int)] = []
        func add(_ x: Int, _ y: Int) {
            for dx in -halfWidth...halfWidth {
                let xx = x + dx
                if seen.insert(y * 100000 + xx).inserted { p.append((xx, y)) }
            }
        }
        var prev: (Int, Int)?
        for t in 0..<length {
            let x = x0 + Int((amp * sin(Double(t) * 0.18)).rounded())
            let y = y0 + t
            if let (px, py) = prev {
                let steps = max(1, max(abs(x - px), abs(y - py)))
                for s in 1...steps { add(px + (x - px) * s / steps, py + (y - py) * s / steps) }
            } else { add(x, y) }
            prev = (x, y)
        }
        return p
    }

    func testAllDefectTypesDetectedAndRepaired() {
        let w = 240, h = 240, base = 120
        let cases: [(String, [(Int, Int)])] = [
            ("얇은먼지(3px)",       fatDust(120, 120, 1)),
            ("중간먼지(9px)",       fatDust(120, 120, 4)),
            ("뚱뚱먼지(23px)",      fatDust(120, 120, 11)),
            ("얇은직선스크래치",     vLine(120, 40, 200, halfWidth: 0)),
            ("긴직선스크래치",       vLine(120, 20, 220, halfWidth: 1)),
            ("짧은스크래치",         vLine(120, 110, 134, halfWidth: 0)),
            ("두꺼운스크래치(7px)",  vLine(120, 40, 200, halfWidth: 3)),
            ("꼬부랑머리카락(가늚)",  curlyHair(120, 60, length: 110, amp: 22, halfWidth: 0)),
            ("꼬부랑머리카락(두꺼움)", curlyHair(120, 60, length: 110, amp: 22, halfWidth: 2)),
        ]
        var failures: [String] = []
        for (name, defect) in cases {
            let r = measure(name, w: w, h: h, base: base, defect: defect)
            // 검출: 결함 픽셀의 70% 이상 마스크 커버. 복원: 결함 위치 평균 잔존이 defect 의 ~30% 미만.
            if r.coverage < 0.7 { failures.append("\(name) 검출 \(Int(r.coverage * 100))%") }
            if r.leftover > 35 { failures.append("\(name) 복원잔존 \(Int(r.leftover))") }
        }
        XCTAssertTrue(failures.isEmpty, "결함 종류 미해결: \(failures.joined(separator: ", "))")
    }

    /// 가이드 검출이 긴 곡선 결함의 강한 중심선만 라벨링해도, 제거 마스크는 스캔 광학/초점이 만든
    /// 부드러운 가장자리까지 포함해야 한다. 중심선만 지워지고 얇은 윤곽이 남는 실사용 회귀를 고정한다.
    func testLongCurvedScratchSoftEdgeIsFullyRemoved() {
        let w = 220, h = 180, base = 120
        var px = bg(w, h, base)
        var core: [Int] = []
        var affected = Set<Int>()

        for x in 30..<190 {
            let y = 90 + Int((24 * sin(Double(x - 30) / 17)).rounded())
            core.append(y * w + x)
            for dy in -3...3 {
                for dx in -3...3 {
                    let xx = x + dx, yy = y + dy
                    guard xx >= 0, yy >= 0, xx < w, yy < h else { continue }
                    let distance = max(abs(dx), abs(dy))
                    let delta = [80, 52, 28, 14][distance]
                    let index = yy * w + xx
                    let offset = index * 4
                    let value = UInt8(min(255, base + delta))
                    px[offset] = max(px[offset], value)
                    px[offset + 1] = max(px[offset + 1], value)
                    px[offset + 2] = max(px[offset + 2], value)
                    affected.insert(index)
                }
            }
        }

        let component = DefectComponent(
            id: 0,
            kind: .scratch,
            pixels: core,
            minX: 30,
            minY: core.map { $0 / w }.min()!,
            maxX: 189,
            maxY: core.map { $0 / w }.max()!,
            classification: .scratchDiagonal,
            confidence: 0.9
        )
        var labels = [Int32](repeating: -1, count: w * h)
        for index in core { labels[index] = 0 }
        let field = DefectLabelField(width: w, height: h, labels: labels, components: [component])
        let mask = SoftwareDefectRemoval.componentMaskBytes(
            field: field,
            excluded: [],
            scratchDilate: 3
        )
        let image = ci(px, w, h)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let out = render(SoftwareDefectRemoval.repair(image: image, roi: roi, mask: ci(mask, w, h)), w, h)

        var residual = 0
        var maxResidual = 0
        for index in affected {
            let value = abs(Int(out[index * 4]) - base)
            residual += value
            maxResidual = max(maxResidual, value)
        }
        let averageResidual = Double(residual) / Double(affected.count)
        print(String(format: "[curved-soft-edge] average=%.2f max=%d", averageResidual, maxResidual))
        XCTAssertLessThan(averageResidual, 2.0, "긴 곡선 결함의 부드러운 가장자리가 얇게 남음")
        XCTAssertLessThan(maxResidual, 8, "긴 곡선 결함 가장자리에 눈에 띄는 잔존이 남음")
    }
}
