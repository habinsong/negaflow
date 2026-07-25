import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// 미세 입자(DefectSpeckDetector) 검증 — 합성 픽셀 전용.
//
// 실측 시나리오: 3600dpi 스캔의 현상 찌꺼기·유분·미세 먼지(2~7px, 무채색, 밀집)가 크로마틱
// 그레인 위에 있어도 검출·복원되고, 그레인만 있는 입력·채널 상관(흑백 은염) 입력에서는
// 오탐이 0이어야 한다. speck 대비(−20/255, 감마 Δ≈0.058)는 기존 보수 경로의 strong 임계
// (≈0.092) 아래로 설계했다 — 그레인이 우연히 얹혀 임계를 넘는 소수를 빼면 새 패스가 잡는다.
final class DefectSpeckDetectorTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    private struct LCG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func gray(_ w: Int, _ h: Int, _ base: Int) -> [UInt8] {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            let o = i * 4
            px[o] = UInt8(base); px[o + 1] = UInt8(base); px[o + 2] = UInt8(base)
        }
        return px
    }

    /// 채널 독립(chromatic) 그레인 — 컬러 필름의 염료층별 독립 입자를 모사한다.
    private func addChromaticGrain(_ px: inout [UInt8], _ w: Int, _ h: Int,
                                   probability: Double, amplitude: Int, seed: UInt64) {
        var rng = LCG(state: seed)
        for i in 0..<(w * h) {
            for c in 0..<3 where Double.random(in: 0..<1, using: &rng) < probability {
                let sign = Bool.random(using: &rng) ? amplitude : -amplitude
                let o = i * 4 + c
                px[o] = UInt8(min(255, max(0, Int(px[o]) + sign)))
            }
        }
    }

    /// 채널 상관 그레인 — 흑백 은염(모든 파장 동시 차단)을 모사한다. 판별축 붕괴 입력.
    private func addCorrelatedGrain(_ px: inout [UInt8], _ w: Int, _ h: Int,
                                    probability: Double, amplitude: Int, seed: UInt64) {
        var rng = LCG(state: seed)
        for i in 0..<(w * h) where Double.random(in: 0..<1, using: &rng) < probability {
            let sign = Bool.random(using: &rng) ? amplitude : -amplitude
            let o = i * 4
            for c in 0..<3 { px[o + c] = UInt8(min(255, max(0, Int(px[o + c]) + sign))) }
        }
    }

    /// 무채색 어두운 미세 입자(이물은 raw 네거티브에서 투과광을 가려 어둡다).
    private func addSpeck(_ px: inout [UInt8], _ w: Int, x: Int, y: Int, size: Int, drop: Int) {
        for yy in y..<(y + size) {
            for xx in x..<(x + size) {
                let o = (yy * w + xx) * 4
                for c in 0..<3 { px[o + c] = UInt8(max(0, Int(px[o + c]) - drop)) }
            }
        }
    }

    private func detect(_ px: [UInt8], _ w: Int, _ h: Int, micro: Bool) -> DefectLabelField {
        let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6,
                                           detectMicroSpecks: micro)
        return SoftwareDefectRemoval.detectComponents(
            in: makeRGBA8CIImage(px, w, h, colorSpace: linear),
            roi: CGRect(x: 0, y: 0, width: w, height: h), parameters: params)
    }

    private func speckClass(_ field: DefectLabelField, atX x: Int, y: Int) -> DefectClass? {
        guard let id = field.nearestComponentID(atX: x, y: y, radius: 4) else { return nil }
        return field.components.first { $0.id == id }?.classification
    }

    private var gridPositions: [(Int, Int)] {
        var out: [(Int, Int)] = []
        for x in stride(from: 40, through: 460, by: 60) where out.count < 40 {
            for y in stride(from: 60, through: 420, by: 90) { out.append((x, y)) }
        }
        return out
    }

    // MARK: 검출

    func testMicroSpecksOnChromaticGrainDetected() {
        let w = 512, h = 512
        var px = gray(w, h, 120)
        addChromaticGrain(&px, w, h, probability: 0.05, amplitude: 10, seed: 7)
        let specks = gridPositions
        for (x, y) in specks { addSpeck(&px, w, x: x, y: y, size: 3, drop: 20) }

        let field = detect(px, w, h, micro: true)
        // 그레인이 우연히 얹힌 입자는 기존 보수 경로가 먼저 .dust 로 채택할 수 있다(머지는 기존
        // 우선 — 제거 관점에선 동일). 전체 검출은 100%, 새 패스(.microSpeck) 기여는 80% 이상.
        var found = 0, foundMicro = 0
        for (x, y) in specks {
            switch speckClass(field, atX: x + 1, y: y + 1) {
            case .microSpeck: found += 1; foundMicro += 1
            case .dust, .pinhole: found += 1
            default: break
            }
        }
        XCTAssertEqual(found, specks.count, "미세 입자 전수 검출 (\(found)/\(specks.count))")
        XCTAssertGreaterThanOrEqual(foundMicro, Int(Double(specks.count) * 0.8),
                                    "새 패스 기여 80% 이상 (\(foundMicro)/\(specks.count))")
        // 오탐 가드: microSpeck 컴포넌트 수가 주입 수를 크게 넘지 않는다(그레인 오탐 없음).
        let microCount = field.components.filter { $0.classification == .microSpeck }.count
        XCTAssertLessThanOrEqual(microCount, specks.count + 4, "그레인 오탐 없음 (\(microCount)개)")
    }

    func testDenseClusterNotSelfSuppressed() {
        // 밀집 입자(간격 14px)가 서로의 잡음 바닥을 끌어올려 자기억제되지 않아야 한다 —
        // boxMean 통계였다면 전멸하는 배치다(분위수 바닥의 존재 이유).
        let w = 512, h = 512
        var px = gray(w, h, 120)
        addChromaticGrain(&px, w, h, probability: 0.05, amplitude: 10, seed: 11)
        var specks: [(Int, Int)] = []
        for gy in 0..<4 {
            for gx in 0..<4 { specks.append((200 + gx * 14, 200 + gy * 14)) }
        }
        for (x, y) in specks { addSpeck(&px, w, x: x, y: y, size: 3, drop: 20) }

        let field = detect(px, w, h, micro: true)
        var found = 0
        for (x, y) in specks where speckClass(field, atX: x + 1, y: y + 1) == .microSpeck { found += 1 }
        XCTAssertGreaterThanOrEqual(found, 14, "밀집 입자 비자기억제 (\(found)/16)")
    }

    // MARK: 오탐 안전선

    func testChromaticGrainOnlyZeroFalsePositives() {
        let w = 512, h = 512
        var px = gray(w, h, 120)
        addChromaticGrain(&px, w, h, probability: 0.10, amplitude: 12, seed: 23)
        let field = detect(px, w, h, micro: true)
        XCTAssertEqual(field.components.filter { $0.classification == .microSpeck }.count, 0,
                       "크로마틱 그레인만으로는 microSpeck 0개")
    }

    func testCorrelatedGrainDisablesSpeckPass() {
        // 흑백 은염 모사(3채널 동시 그레인): 채널 동시성 판별축이 무너지는 입력에서는
        // 강건 바닥/후보 퓨즈가 패스를 무해하게 무력화해야 한다 — 대량 오탐 대신 0 검출.
        let w = 512, h = 512
        var px = gray(w, h, 120)
        addCorrelatedGrain(&px, w, h, probability: 0.3, amplitude: 12, seed: 31)
        for (x, y) in gridPositions { addSpeck(&px, w, x: x, y: y, size: 3, drop: 20) }
        let field = detect(px, w, h, micro: true)
        XCTAssertEqual(field.components.filter { $0.classification == .microSpeck }.count, 0,
                       "채널 상관 그레인에서는 speck 패스 무력화(오탐 방지 우선)")
    }

    func testToggleOffLeavesLegacyPathIdentical() {
        let w = 512, h = 512
        var px = gray(w, h, 120)
        addChromaticGrain(&px, w, h, probability: 0.05, amplitude: 10, seed: 7)
        for (x, y) in gridPositions { addSpeck(&px, w, x: x, y: y, size: 3, drop: 20) }

        let off = detect(px, w, h, micro: false)
        XCTAssertEqual(off.components.filter { $0.classification == .microSpeck }.count, 0,
                       "토글 off 면 microSpeck 없음")
        // 머지는 순수 추가 — 토글 on 의 비-micro 컴포넌트는 off 결과와 동일해야 한다.
        let on = detect(px, w, h, micro: true)
        let onLegacy = on.components.filter { $0.classification != .microSpeck }
        XCTAssertEqual(onLegacy.count, off.components.count, "기존 경로 결과 불변")
    }

    // MARK: 복원

    func testRepairRemovesSpecksAndPreservesBackground() {
        let w = 512, h = 512, base = 120
        var px = gray(w, h, base)
        addChromaticGrain(&px, w, h, probability: 0.05, amplitude: 10, seed: 7)
        let specks = gridPositions
        for (x, y) in specks { addSpeck(&px, w, x: x, y: y, size: 3, drop: 20) }

        let image = makeRGBA8CIImage(px, w, h, colorSpace: linear)
        let field = detect(px, w, h, micro: true)
        XCTAssertFalse(field.isEmpty)
        guard let repaired = SoftwareDefectRemoval.repairComponents(
            image: image, roi: CGRect(x: 0, y: 0, width: w, height: h),
            field: field, excluded: []) else {
            return XCTFail("repairComponents 실패")
        }
        let out = renderRGBA8Pixels(repaired, w, h, colorSpace: linear)

        // 검출된 입자 중심: 원본 |Δ|=25 → 복원 후 배경 근처(그레인 진폭 이내)로 복귀.
        var repairedCount = 0
        for (x, y) in specks where speckClass(field, atX: x + 1, y: y + 1) == .microSpeck {
            // 렌더 y-down == 픽스처 인덱스 규약(라벨과 동일).
            let o = ((y + 1) * w + (x + 1)) * 4
            let delta = abs(Int(out[o]) - base)
            if delta <= 14 { repairedCount += 1 }
        }
        XCTAssertGreaterThanOrEqual(repairedCount, Int(Double(specks.count) * 0.85),
                                    "검출 입자 대부분이 배경 수준으로 복원")

        // 마스크에서 먼 배경 픽셀은 불변(±2/255). 라벨 반경 8px 이내는 제외.
        var checked = 0
        for (x, y) in specks {
            let bx = x + 30, by = y + 30
            guard bx < w - 8, by < h - 8 else { continue }
            var nearLabel = false
            for dy in -8...8 {
                for dx in -8...8 where field.componentID(atX: bx + dx, y: by + dy) != nil {
                    nearLabel = true
                }
            }
            guard !nearLabel else { continue }
            let o = (by * w + bx) * 4
            for c in 0..<3 {
                XCTAssertLessThanOrEqual(abs(Int(out[o + c]) - Int(px[o + c])), 2,
                                         "배경(\(bx),\(by)) ch\(c) 보존")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 10, "배경 보존 검증 표본 확보")
    }
}
