import XCTest
import CoreImage
import CoreGraphics
@testable import negaflowApp
@testable import Chromabase

// 복제 도장 엔진(CloneStampBrush → DefectPatch)을 실제 앱 진입점(computeDefectPatches,
// linear16 raw 도메인)으로 돌려 수치로 검증한다: 오프셋 복제 정확도, 경도 페더 곡선,
// 소스 범위 밖 무변경, 레코드 왕복/지문.
final class CloneStampPipelineTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    /// 16bit linear RGBA CGImage 합성(앱의 cleaned raw 와 같은 도메인).
    private func makeLinear16(w: Int, h: Int, pixel: (Int, Int) -> (UInt16, UInt16, UInt16)) -> CGImage {
        var data = [UInt16](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let (r, g, b) = pixel(x, y)
                let o = (y * w + x) * 4
                data[o] = r; data[o + 1] = g; data[o + 2] = b; data[o + 3] = 0xFFFF
            }
        }
        let provider = CGDataProvider(data: Data(bytes: data, count: data.count * 2) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 16, bitsPerPixel: 64,
                       bytesPerRow: w * 8, space: linear,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                           | CGBitmapInfo.byteOrder16Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func render16(_ cg: CGImage, w: Int, h: Int) -> [UInt16] {
        var out = [UInt16](repeating: 0, count: w * h * 4)
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        ctx.render(CIImage(cgImage: cg, options: [.colorSpace: linear]), toBitmap: &out,
                   rowBytes: w * 8, bounds: CGRect(x: 0, y: 0, width: w, height: h),
                   format: .RGBA16, colorSpace: linear)
        return out
    }

    private func compose(_ patches: [DefectPatch], over cg: CGImage,
                         strength: Double, w: Int, h: Int) -> [UInt16] {
        var working = CIImage(cgImage: cg, options: [.colorSpace: linear])
        for p in patches { working = p.composited(over: working, strength: strength, colorSpace: linear) }
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        guard let out = ctx.createCGImage(working, from: working.extent,
                                          format: .RGBA16, colorSpace: linear) else { return [] }
        return render16(out, w: w, h: h)
    }

    private func lum(_ a: [UInt16], _ w: Int, _ x: Int, _ y: Int) -> Int { Int(a[(y * w + x) * 4]) }

    /// 경도 100%: 스트로크 중심부는 소스 픽셀과 "동일"해야 하고(복제이지 필터가 아니다),
    /// 스트로크 밖은 변하면 안 된다.
    func testFullHardnessCopiesSourcePixelsExactly() throws {
        let w = 480, h = 360
        // 공간적으로 유일한 결정적 패턴 — 오프셋이 1px만 틀려도 큰 차이가 난다.
        let cg = makeLinear16(w: w, h: h) { x, y in
            (UInt16(((x * 37 + y * 11) % 4096) * 12),
             UInt16(((x * 13 + y * 29) % 4096) * 12),
             UInt16(((x * 7 + y * 3) % 4096) * 12))
        }
        // 대상: y=180 가로선 x=120→216. 소스: +120px 오른쪽, −72px 위(y-down 오프셋).
        let stroke = CloneStampStroke(
            points: [CGPoint(x: 0.25, y: 0.5), CGPoint(x: 0.45, y: 0.5)],
            offset: CGVector(dx: 0.25, dy: -0.2),
            diameter: 24, hardness: 1.0
        )
        guard let patches = computeDefectPatches(.clone([stroke]), base: cg, shouldCancel: { false }),
              !patches.isEmpty else { return XCTFail("패치 계산 실패") }
        let before = render16(cg, w: w, h: h)
        let after = compose(patches, over: cg, strength: 1.0, w: w, h: h)

        // 패턴 유효성: 대상과 소스 픽셀이 실제로 달라야 검증이 의미 있다.
        var patternDiff = 0
        var count = 0
        for x in stride(from: 130, through: 206, by: 4) {
            patternDiff += abs(lum(before, w, x, 180) - lum(before, w, x + 120, 180 - 72))
            count += 1
        }
        XCTAssertGreaterThan(patternDiff / count, 1000, "합성 패턴이 대상/소스에서 달라야 한다")

        // (a) 중심선: 소스 픽셀과 채널 단위로 일치(복제 = 실제 픽셀 이동).
        var maxCoreDev = 0
        for x in stride(from: 130, through: 206, by: 2) {
            let o = (180 * w + x) * 4
            let so = ((180 - 72) * w + (x + 120)) * 4
            for c in 0..<3 {
                maxCoreDev = max(maxCoreDev, abs(Int(after[o + c]) - Int(before[so + c])))
            }
        }
        XCTAssertLessThan(maxCoreDev, 130, "경도 100% 중심부는 소스와 동일해야 한다(≈0.5/255 미만)")

        // (b) 스트로크 밖(중심선에서 40px): 무변화.
        var maxOutDev = 0
        for x in stride(from: 110, through: 226, by: 4) {
            for dy in [-40, 40] {
                let o = ((180 + dy) * w + x) * 4
                for c in 0..<3 {
                    maxOutDev = max(maxOutDev, abs(Int(after[o + c]) - Int(before[o + c])))
                }
            }
        }
        XCTAssertLessThan(maxOutDev, 130, "브러시 밖은 변하면 안 된다")
    }

    /// 경도 0%: 중심은 소스, 가장자리로 갈수록 원본과 부드럽게 섞여야 한다(단조 감소 페더).
    func testZeroHardnessFeathersMonotonically() throws {
        let w = 480, h = 360
        let leftValue: UInt16 = 20000, rightValue: UInt16 = 40000
        let cg = makeLinear16(w: w, h: h) { x, _ in
            let v = x < 240 ? leftValue : rightValue
            return (v, v, v)
        }
        // 클릭 1회(도장 1개): 대상 (120,180) 왼쪽 균일 영역, 소스 +240px 오른쪽 균일 영역.
        let stroke = CloneStampStroke(
            points: [CGPoint(x: 0.25, y: 0.5)],
            offset: CGVector(dx: 0.5, dy: 0),
            diameter: 40, hardness: 0.0
        )
        guard let patches = computeDefectPatches(.clone([stroke]), base: cg, shouldCancel: { false }),
              !patches.isEmpty else { return XCTFail("패치 계산 실패") }
        let after = compose(patches, over: cg, strength: 1.0, w: w, h: h)

        func alpha(atDistance d: Int) -> Double {
            let v = Double(lum(after, w, 120 + d, 180))
            return (v - Double(leftValue)) / Double(rightValue - leftValue)
        }
        XCTAssertGreaterThan(alpha(atDistance: 0), 0.9, "중심은 소스 픽셀이어야 한다")
        var previous = 2.0
        for d in stride(from: 0, through: 18, by: 3) {
            let a = alpha(atDistance: d)
            XCTAssertLessThanOrEqual(a, previous + 0.03, "페더는 중심→가장자리로 단조 감소해야 한다(d=\(d))")
            previous = a
        }
        let mid = alpha(atDistance: 10)   // t=0.5 — smoothstep 중간값 부근
        XCTAssertGreaterThan(mid, 0.25, "경도 0% 중간 지점이 너무 딱딱하다")
        XCTAssertLessThan(mid, 0.75, "경도 0% 중간 지점이 너무 퍼졌다")
        XCTAssertLessThan(alpha(atDistance: 23), 0.03, "반경 밖은 변하면 안 된다")
    }

    /// 강도 50%: 결과가 원본과 100% 결과의 정확한 중간(패치 상수 알파 합성 선형성).
    func testHalfStrengthBlendsLinearly() throws {
        let w = 320, h = 240
        let cg = makeLinear16(w: w, h: h) { x, y in
            (UInt16(((x * 31 + y * 17) % 4096) * 12),
             UInt16(((x * 5 + y * 23) % 4096) * 12),
             UInt16(((x * 19 + y * 7) % 4096) * 12))
        }
        let stroke = CloneStampStroke(
            points: [CGPoint(x: 0.3, y: 0.5), CGPoint(x: 0.5, y: 0.5)],
            offset: CGVector(dx: 0, dy: -0.25),
            diameter: 20, hardness: 0.5
        )
        guard let patches = computeDefectPatches(.clone([stroke]), base: cg, shouldCancel: { false }),
              !patches.isEmpty else { return XCTFail("패치 계산 실패") }
        let before = render16(cg, w: w, h: h)
        let full = compose(patches, over: cg, strength: 1.0, w: w, h: h)
        let half = compose(patches, over: cg, strength: 0.5, w: w, h: h)
        var maxDev = 0
        for y in stride(from: 108, through: 132, by: 3) {
            for x in stride(from: 90, through: 166, by: 3) {
                let o = (y * w + x) * 4
                for c in 0..<3 {
                    let expected = Double(before[o + c]) + 0.5 * (Double(full[o + c]) - Double(before[o + c]))
                    maxDev = max(maxDev, abs(Int(half[o + c]) - Int(expected.rounded())))
                }
            }
        }
        XCTAssertLessThan(maxDev, 260, "강도 합성이 선형이어야 즉시 경로가 전체 재계산과 일치한다")
    }

    /// 소스가 이미지 밖이면 복제하지 않는다(빈 패치 = 무변경).
    func testSourceOutsideImageProducesNoChange() throws {
        let w = 300, h = 200
        let cg = makeLinear16(w: w, h: h) { x, y in
            (UInt16(x * 100), UInt16(y * 200), 30000)
        }
        let stroke = CloneStampStroke(
            points: [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.6, y: 0.5)],
            offset: CGVector(dx: 0.9, dy: 0),
            diameter: 30, hardness: 1.0
        )
        let patches = computeDefectPatches(.clone([stroke]), base: cg, shouldCancel: { false })
        XCTAssertNotNil(patches)
        XCTAssertTrue(patches?.isEmpty ?? false, "소스가 전부 범위 밖이면 변경이 없어야 한다")
    }

    /// 레코드 왕복(스트로크/오프셋/지름/경도 보존) + 지문/리소스 정책 통과 + 형태 위반 거부.
    @MainActor
    func testRecordRoundTripFingerprintAndShapeValidation() throws {
        let stroke = CloneStampStroke(
            points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.3, y: 0.4)],
            offset: CGVector(dx: 0.05, dy: -0.07),
            diameter: 32, hardness: 0.65
        )
        let item = DefectEditItem(edit: .clone([stroke]), title: "clone", summary: "clone",
                                  preview: [], baseSize: CGSize(width: 100, height: 80))
        let record = DefectEditItemRecord(item: item)
        XCTAssertEqual(record.kind, .clone)

        guard let restored = record.makeItem(), case .clone(let strokes) = restored.edit,
              strokes.count == 1 else {
            return XCTFail("clone 레코드 복원 실패")
        }
        XCTAssertEqual(strokes[0].points, stroke.points)
        XCTAssertEqual(strokes[0].offset.dx, stroke.offset.dx, accuracy: 1e-12)
        XCTAssertEqual(strokes[0].offset.dy, stroke.offset.dy, accuracy: 1e-12)
        XCTAssertEqual(Double(strokes[0].diameter), Double(stroke.diameter), accuracy: 1e-12)
        XCTAssertEqual(Double(strokes[0].hardness), Double(stroke.hardness), accuracy: 1e-12)

        // 지문: 계산 가능해야 하고, 경도만 바꿔도 달라져야 한다.
        let hash = try DefectRecipeFingerprint.sha256(items: [record])
        var changed = record
        changed.cloneStrokes?[0].hardness = 0.3
        XCTAssertNotEqual(hash, try DefectRecipeFingerprint.sha256(items: [changed]))

        // 리소스 정책 통과.
        XCTAssertNoThrow(try DefectSidecarResourcePolicy.checkedItems([record]))
        XCTAssertNoThrow(try DefectSidecarResourcePolicy.normalizedItems([record]))

        // 형태 위반: clone 레코드에 브러시 스트로크가 섞이면 거부.
        var malformed = record
        malformed.strokes = [DefectStrokeRecord(points: [CGPoint(x: 0.5, y: 0.5)], thickness: 0.01)]
        XCTAssertThrowsError(try DefectRecipeFingerprint.canonicalData(items: [malformed]))

        // 스칼라 위반: 경도 범위 밖 거부.
        var invalid = record
        invalid.cloneStrokes?[0].hardness = 1.5
        XCTAssertThrowsError(try DefectRecipeFingerprint.canonicalData(items: [invalid]))
    }

    /// 도장 간격: 경로를 따라 지름의 25% 간격으로 중심이 찍힌다(첫 점 포함).
    func testStampCentersFollowSpacing() {
        let centers = CloneStampBrush.stampCenters(
            along: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            spacing: 10
        )
        XCTAssertEqual(centers.count, 11)
        XCTAssertEqual(centers.first, CGPoint(x: 0, y: 0))
        for (i, c) in centers.enumerated() {
            XCTAssertEqual(Double(c.x), Double(i) * 10, accuracy: 1e-9)
            XCTAssertEqual(Double(c.y), 0, accuracy: 1e-9)
        }
    }
}
