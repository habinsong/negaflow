import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// 저대비·조각난 결함을 히스테리시스(strong/weak 이중 임계) 연결로 잇는지 검증한다.
//   A) strong 코어 + weak 연결부로 대비가 임계 주변에서 오르내리는 가늘고 긴 스크래치를
//      하나의 긴 컴포넌트로 이어 대부분 덮는다(조각 분해 방지).
//   B) grain-safe 경계: strong 코어가 전혀 없는 "균일 저대비 선"은 검출되지 않는다
//      (weak 만으로는 컴포넌트를 만들지 못한다 — 실제 필름 그레인이 폭발하지 않게).
final class RegionICEFaintDefectTests: XCTestCase {
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
    private func paint(_ px: inout [UInt8], _ w: Int, _ x: Int, _ y: Int, _ v: Int) {
        let o = (y * w + x) * 4; px[o] = UInt8(v); px[o + 1] = UInt8(v); px[o + 2] = UInt8(v)
    }
    // 슬라이더 최대에서의 검출 파라미터(민감도 1.0 clamp).
    private let params = SoftwareICEParameters(strength: 1, dustSensitivity: 1.0,
                                               scratchSensitivity: 1.0, protectDetail: 0.6)

    // A) strong 코어 + weak 연결부: 세로 스크래치의 대비가 강(138)/약(126) 구간으로 오르내린다.
    //    weak(126)은 strong 절대 임계 미만이라, 히스테리시스가 없으면 strong 구간만 조각 검출되어
    //    weak 구간이 빠진다. 히스테리시스로 하나의 긴 컴포넌트로 이어 대부분 덮어야 한다.
    func testFaintFragmentedScratchLinkedByHysteresis() {
        let w = 240, h = 240, base = 120
        let x = 120, y0 = 30, y1 = 210
        var px = bg(w, h, base)
        var defect: [(Int, Int)] = []
        for y in y0...y1 {
            // 30px strong, 20px weak 반복(적분 창 25px 보다 커 weak 구간 중앙은 실제로 weak).
            let strong = (y - y0) % 50 < 30
            paint(&px, w, x, y, strong ? 138 : 126)
            defect.append((x, y))
        }
        let img = ci(px, w, h)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let field = SoftwareICE.detectComponents(in: img, roi: roi, parameters: params)
        let mask = ICEComponentMask.renderMask(field, excluded: [], dustDilate: 2)
        var covered = 0
        for (dx, dy) in defect where mask[(dy * w + dx) * 4] > 0 { covered += 1 }
        let coverage = Double(covered) / Double(defect.count)
        // strong 구간만이면 커버리지 ≤ 60%. weak 연결까지 덮어야 대부분(≥85%) 커버.
        print(String(format: "[faint] fragmented scratch coverage=%.0f%% comps=%d", coverage * 100, field.components.count))
        XCTAssertGreaterThanOrEqual(coverage, 0.85, "저대비 조각 스크래치가 히스테리시스로 이어져야 한다(커버 \(Int(coverage * 100))%)")
        XCTAssertLessThanOrEqual(field.components.count, 4, "조각으로 분해되지 않고 소수 컴포넌트로 이어져야 한다")
        // 복원 후 잔존이 작아야 한다.
        let out = render(SoftwareICE.repair(image: img, roi: roi, mask: ci(mask, w, h)), w, h)
        var sum = 0
        for (dx, dy) in defect { sum += abs(lum(out, w, dx, dy) - base) }
        XCTAssertLessThan(Double(sum) / Double(defect.count), 12, "이어진 스크래치가 복원으로 제거돼야 한다")
    }

    // A2) 작은 불규칙(꼬불꼬불) 저대비 얇은 먼지: 대비가 strong/weak 로 오르내리는 짧은 곡선을
    //     히스테리시스로 이어 대부분 덮는다(사용자의 "불규칙한 먼지" 케이스 — 작고 성김).
    func testFaintIrregularDustLinked() {
        let w = 240, h = 240, base = 120
        var px = bg(w, h, base)
        var seen = Set<Int>()
        var defect: [(Int, Int)] = []
        var prev: (Int, Int)?
        // 짧고 성긴 불규칙 먼지(반경 12 안에 한 가닥만 — 자기억제 없음). 검출 가능한 코어(165)와
        // 더 흐린 연결부(138)가 섞임 — 히스테리시스가 이어 불규칙 형태 전체를 덮는지 본다.
        let x0 = 120, y0 = 100, length = 34, amp = 7.0
        func add(_ x: Int, _ y: Int, _ v: Int) {
            guard x >= 0, y >= 0, x < w, y < h, seen.insert(y * 100000 + x).inserted else { return }
            paint(&px, w, x, y, v); defect.append((x, y))
        }
        for t in 0..<length {
            let x = x0 + Int((amp * sin(Double(t) * 0.28)).rounded())
            let y = y0 + t
            let v = (t % 12 < 7) ? 165 : 138   // 검출 가능한 코어 / 흐린 연결부
            if let (pxx, pyy) = prev {
                let steps = max(1, max(abs(x - pxx), abs(y - pyy)))
                for s in 1...steps { add(pxx + (x - pxx) * s / steps, pyy + (y - pyy) * s / steps, v) }
            } else { add(x, y, v) }
            prev = (x, y)
        }
        let img = ci(px, w, h)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let field = SoftwareICE.detectComponents(in: img, roi: roi, parameters: params)
        let mask = ICEComponentMask.renderMask(field, excluded: [], dustDilate: 2)
        var covered = 0
        for (dx, dy) in defect where mask[(dy * w + dx) * 4] > 0 { covered += 1 }
        let coverage = Double(covered) / Double(defect.count)
        print(String(format: "[faint] irregular dust coverage=%.0f%% comps=%d", coverage * 100, field.components.count))
        XCTAssertGreaterThanOrEqual(coverage, 0.75, "작은 불규칙 저대비 먼지가 히스테리시스로 이어져야 한다(커버 \(Int(coverage * 100))%)")
    }

    // B) grain-safe 경계: strong 코어가 전혀 없는 균일 저대비 선(126)은 검출되지 않아야 한다.
    //    weak 만으로는 컴포넌트를 만들 수 없다(실제 그레인 폭발 방지) — 사용자가 선택한 "그레인 안전 우선".
    func testUniformSubThresholdLineNotDetected() {
        let w = 240, h = 240, base = 120
        let x = 120, y0 = 30, y1 = 210
        var px = bg(w, h, base)
        for y in y0...y1 { paint(&px, w, x, y, 126) }   // 전 구간 weak(= strong 임계 미만)
        let img = ci(px, w, h)
        let roi = CGRect(x: 0, y: 0, width: w, height: h)
        let field = SoftwareICE.detectComponents(in: img, roi: roi, parameters: params)
        let mask = ICEComponentMask.renderMask(field, excluded: [], dustDilate: 2)
        var covered = 0
        for y in y0...y1 where mask[(y * w + x) * 4] > 0 { covered += 1 }
        let coverage = Double(covered) / Double(y1 - y0 + 1)
        print(String(format: "[faint] uniform sub-threshold line coverage=%.0f%% comps=%d", coverage * 100, field.components.count))
        XCTAssertLessThan(coverage, 0.30, "strong 코어 없는 균일 저대비 선은 검출되면 안 된다(grain-safe 경계, \(Int(coverage * 100))%)")
    }
}
