import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// GrainMend RGB 분류(dust/pinhole/방향별 scratch/emulsion) + confidence 검증 — 합성 픽셀만 사용.
final class DefectClassifierTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private let params = SoftwareDefectParameters(strength: 1, dustSensitivity: 0.6,
                                               scratchSensitivity: 0.7, protectDetail: 0.6)

    private func ciImage(_ px: [UInt8], _ w: Int, _ h: Int) -> CIImage {
        makeRGBA8CIImage(px, w, h, colorSpace: linear)
    }

    private func gray(_ w: Int, _ h: Int, _ base: Int) -> [UInt8] {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) { let o = i * 4; px[o] = UInt8(base); px[o + 1] = UInt8(base); px[o + 2] = UInt8(base) }
        return px
    }

    private func set(_ px: inout [UInt8], _ w: Int, _ x: Int, _ y: Int, _ v: Int) {
        let o = (y * w + x) * 4
        px[o] = UInt8(v); px[o + 1] = UInt8(v); px[o + 2] = UInt8(v)
    }

    private func detect(_ px: [UInt8], _ w: Int, _ h: Int) -> DefectLabelField {
        SoftwareDefectRemoval.detectComponents(in: ciImage(px, w, h),
                                     roi: CGRect(x: 0, y: 0, width: w, height: h),
                                     parameters: params)
    }

    func testScratchOrientationClassification() {
        let w = 160, h = 160, base = 120
        // 가로.
        var px = gray(w, h, base)
        for x in 20..<140 { set(&px, w, x, 80, 190) }
        var field = detect(px, w, h)
        XCTAssertFalse(field.isEmpty, "가로 스크래치 검출")
        XCTAssertEqual(field.components.max(by: { $0.pixelCount < $1.pixelCount })?.classification,
                       .scratchHorizontal)
        // 세로.
        px = gray(w, h, base)
        for y in 20..<140 { set(&px, w, 80, y, 190) }
        field = detect(px, w, h)
        XCTAssertFalse(field.isEmpty, "세로 스크래치 검출")
        XCTAssertEqual(field.components.max(by: { $0.pixelCount < $1.pixelCount })?.classification,
                       .scratchVertical)
        // 대각(45°).
        px = gray(w, h, base)
        for t in 20..<140 { set(&px, w, t, t, 190) }
        field = detect(px, w, h)
        XCTAssertFalse(field.isEmpty, "대각 스크래치 검출")
        XCTAssertEqual(field.components.max(by: { $0.pixelCount < $1.pixelCount })?.classification,
                       .scratchDiagonal)
    }

    func testPinholeVsDustPolarity() {
        let w = 160, h = 160, base = 120
        var px = gray(w, h, base)
        // 밝은 작은 점(핀홀: 유제 구멍은 투과광이 그대로 지나 밝다).
        for yy in 38..<42 { for xx in 38..<42 { set(&px, w, xx, yy, 215) } }
        // 어두운 작은 blob(먼지: 이물이 빛을 가린다).
        for yy in 108..<113 { for xx in 108..<113 { set(&px, w, xx, yy, 35) } }
        let field = detect(px, w, h)
        XCTAssertGreaterThanOrEqual(field.components.count, 2, "핀홀+먼지 둘 다 검출")
        func classAt(_ x: Int, _ y: Int) -> DefectClass? {
            guard let id = field.nearestComponentID(atX: x, y: y, radius: 4) else { return nil }
            return field.components.first { $0.id == id }?.classification
        }
        XCTAssertEqual(classAt(40, 40), .pinhole, "밝은 작은 점은 pinhole")
        XCTAssertEqual(classAt(110, 110), .dust, "어두운 blob 은 dust")
    }

    func testEmulsionDamageLargeIrregular() {
        let w = 200, h = 200, base = 120
        var px = gray(w, h, base)
        // 십자(+) 모양의 넓고 불규칙한 어두운 손상: bbox 40×40, 팔 폭 10 → fill≈0.44, 면적 700.
        for y in 80..<120 { for x in 95..<105 { set(&px, w, x, y, 25) } }
        for y in 95..<105 { for x in 80..<120 { set(&px, w, x, y, 25) } }
        // 넓은 손상은 자기 국소평균을 끌어올려 자기억제된다 — 영역 결함 제거 기본 슬라이더처럼
        // 민감도를 올려(절대 면제선↓ + 두께/면적 게이트 완화) 한 덩어리로 채택되게 한다.
        let strongParams = SoftwareDefectParameters(strength: 1, dustSensitivity: 1.2,
                                                 scratchSensitivity: 1.2, protectDetail: 0.6)
        let field = SoftwareDefectRemoval.detectComponents(in: ciImage(px, w, h),
                                                 roi: CGRect(x: 0, y: 0, width: w, height: h),
                                                 parameters: strongParams)
        XCTAssertFalse(field.isEmpty, "십자 손상 검출")
        let big = field.components.max { $0.pixelCount < $1.pixelCount }!
        XCTAssertEqual(big.classification, .emulsionDamage,
                       "넓고 불규칙(fill<0.5)한 손상은 emulsionDamage: area=\(big.pixelCount)")
    }

    func testConfidenceBoundsAndOrdering() {
        let w = 160, h = 160, base = 120
        // 강한 스크래치(Δ70)와 희미한 스크래치(Δ16) — confidence 는 강한 쪽이 커야 한다.
        var strongPx = gray(w, h, base)
        for x in 20..<140 { set(&strongPx, w, x, 80, base + 70) }
        var faintPx = gray(w, h, base)
        for x in 20..<140 { set(&faintPx, w, x, 80, base + 16) }
        let strongField = detect(strongPx, w, h)
        let faintField = detect(faintPx, w, h)
        XCTAssertFalse(strongField.isEmpty)
        XCTAssertFalse(faintField.isEmpty)
        for comp in strongField.components + faintField.components {
            XCTAssertGreaterThanOrEqual(comp.confidence, 0)
            XCTAssertLessThanOrEqual(comp.confidence, 1)
        }
        let strongConf = strongField.components.max { $0.pixelCount < $1.pixelCount }!.confidence
        let faintConf = faintField.components.max { $0.pixelCount < $1.pixelCount }!.confidence
        print("[classifier] strong=\(strongConf) faint=\(faintConf)")
        XCTAssertGreaterThan(strongConf, faintConf,
                             "강한 결함의 confidence 가 희미한 결함보다 커야 한다")
    }
}
