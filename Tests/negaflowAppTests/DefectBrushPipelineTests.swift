import XCTest
import CoreImage
import CoreGraphics
@testable import negaflowApp
@testable import Chromabase

// 실제 앱 브러시 결함 제거 진입점(DefectBrush.removeDefects, linear16 raw 도메인)을 그대로 돌려
// "칠한 곳 전체 밀림(블러/저해상도화)"을 수치로 감시한다. SoftwareDefectRemoval.apply 단위 테스트는
// 청크 분할·flatten 사이클·패치 합성(실제 앱에서만 도는 경로)을 못 본다 — 여기서 본다.
final class DefectBrushPipelineTests: XCTestCase {
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

    /// CGImage → RGBA16 linear 버퍼(비교용 공통 렌더).
    private func render16(_ cg: CGImage, w: Int, h: Int) -> [UInt16] {
        var out = [UInt16](repeating: 0, count: w * h * 4)
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        ctx.render(CIImage(cgImage: cg, options: [.colorSpace: linear]), toBitmap: &out,
                   rowBytes: w * 8, bounds: CGRect(x: 0, y: 0, width: w, height: h),
                   format: .RGBA16, colorSpace: linear)
        return out
    }

    private func lum(_ a: [UInt16], _ w: Int, _ x: Int, _ y: Int) -> Int { Int(a[(y * w + x) * 4]) }

    /// 대각 스크래치 + 크로마 그레인 위 대각 스트로크. (before, after, 스크래치 점, 스트로크 중심선)
    private func runPipeline(strength: Double)
        -> (before: [UInt16], after: [UInt16], scratch: [(Int, Int)], centers: [(Int, Int)], w: Int, h: Int)? {
        let w = 1600, h = 1200, base: Int = 26000, grainAmp = 1400, delta = 9000
        var seed: UInt64 = 0xFEED
        func noise() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed >> 40) % (2 * grainAmp + 1) - grainAmp
        }
        // 결정적 크로마 그레인(채널 독립) 맵을 먼저 만들어 before/after 재현성 확보.
        var px = [(UInt16, UInt16, UInt16)](repeating: (0, 0, 0), count: w * h)
        for i in 0..<(w * h) {
            let r = UInt16(max(0, min(65535, base + noise())))
            let g = UInt16(max(0, min(65535, base + noise())))
            let b = UInt16(max(0, min(65535, base + noise())))
            px[i] = (r, g, b)
        }
        // 대각 스크래치: (320,240) → 방향 (0.5, 1)로 길이 720 — 스트로크와 같은 경로.
        var scratch: [(Int, Int)] = []
        var centers: [(Int, Int)] = []
        for t in 0..<720 {
            let x = 320 + Int((0.5 * Double(t)).rounded()), y = 240 + t
            guard x < w, y < h else { break }
            centers.append((x, y))
            for dx in 0...1 {
                let i = y * w + (x + dx)
                let (r, g, b) = px[i]
                px[i] = (UInt16(min(65535, Int(r) + delta)),
                         UInt16(min(65535, Int(g) + delta)),
                         UInt16(min(65535, Int(b) + delta)))
                scratch.append((x + dx, y))
            }
        }
        let cg = makeLinear16(w: w, h: h) { x, y in px[y * w + x] }
        // 스트로크: 스크래치 경로를 따라 (0..1, y-down) 정규좌표, 두께 0.02(=24px).
        let pts = stride(from: 0, to: 720, by: 24).map { t in
            CGPoint(x: (320.0 + 0.5 * Double(t)) / Double(w), y: (240.0 + Double(t)) / Double(h))
        }
        let params = SoftwareDefectParameters(strength: strength, dustSensitivity: 0.6,
                                           scratchSensitivity: 0.7, protectDetail: 0.6)
        guard let out = DefectBrush.removeDefects(in: cg,
                                                  strokes: [DefectStroke(points: pts, thickness: 0.02)],
                                                  parameters: params, linear16: true) else { return nil }
        return (render16(cg, w: w, h: h), render16(out, w: w, h: h), scratch, centers, w, h)
    }

    /// 표본 위치들의 luma std(그레인 진폭 지표).
    private func sampleStd(_ a: [UInt16], _ w: Int, _ pts: [(Int, Int)]) -> Double {
        var vals = [Double]()
        for (x, y) in pts { vals.append(Double(lum(a, w, x, y))) }
        let m = vals.reduce(0, +) / Double(vals.count)
        return (vals.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(vals.count)).squareRoot()
    }
    /// 표본 위치들의 R−G std(크로마 그레인 지표).
    private func sampleChromaStd(_ a: [UInt16], _ w: Int, _ pts: [(Int, Int)]) -> Double {
        var vals = [Double]()
        for (x, y) in pts {
            let o = (y * w + x) * 4
            vals.append(Double(a[o]) - Double(a[o + 1]))
        }
        let m = vals.reduce(0, +) / Double(vals.count)
        return (vals.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(vals.count)).squareRoot()
    }
    /// 15×15 박스 평균(저주파 톤).
    private func boxMean(_ a: [UInt16], _ w: Int, _ h: Int, _ cx: Int, _ cy: Int) -> Double {
        var sum = 0.0, count = 0.0
        for y in max(0, cy - 7)...min(h - 1, cy + 7) {
            for x in max(0, cx - 7)...min(w - 1, cx + 7) { sum += Double(lum(a, w, x, y)); count += 1 }
        }
        return sum / count
    }

    /// 강도 100%(heal): 스크래치 소멸 + 칠 안 텍스처 통계 보존(실제 픽셀 복제라 밀림/블러 불가)
    /// + 저주파 톤 연속 + 칠 밖 무변화. heal 은 픽셀 동일성이 아니라 지각 동일성이 계약이다.
    func testFullStrengthRemovesScratchWithoutAreaWipe() throws {
        guard let r = runPipeline(strength: 1.0) else { return XCTFail("removeDefects nil") }
        let (before, after, scratch, centers, w, h) = r
        // (a) 스크래치 제거.
        var resid = 0
        for (x, y) in scratch { resid += lum(after, w, x, y) - lum(before, w, x, y) }
        let avgRemoved = Double(-resid) / Double(scratch.count)   // 제거됐으면 ≈ +9000 하락
        // (b) 칠 안 텍스처 통계: 중심선 ±8px 표본 std/크로마 std ≈ 칠 밖(±60px) 표본.
        var inPts: [(Int, Int)] = [], outPts: [(Int, Int)] = []
        for (cx, cy) in centers {
            for off in [-8, 8] where cx + off >= 0 && cx + off < w { inPts.append((cx + off, cy)) }
            for off in [-60, 60] where cx + off >= 0 && cx + off < w { outPts.append((cx + off, cy)) }
        }
        let stdRatio = sampleStd(after, w, inPts) / max(1, sampleStd(after, w, outPts))
        let chromaRatio = sampleChromaStd(after, w, inPts) / max(1, sampleChromaStd(after, w, outPts))
        // (c) 저주파 톤 연속: 중심선 +9px 옆 15×15 박스 평균이 before(스크래치 밖 지점)와 일치.
        var toneDiff = 0.0, toneCount = 0.0
        for (cx, cy) in centers where cy % 40 == 0 {
            toneDiff += abs(boxMean(after, w, h, cx + 9, cy) - boxMean(before, w, h, cx + 9, cy))
            toneCount += 1
        }
        let avgTone = toneDiff / max(1, toneCount)
        // (d) 칠 밖 무변화.
        var outDiff = 0, outCount = 0
        for (x, y) in outPts { outDiff += abs(lum(after, w, x, y) - lum(before, w, x, y)); outCount += 1 }
        let avgOut = Double(outDiff) / Double(max(1, outCount))
        print(String(format: "[pipeline s=1.0] removed=%.0f/9000 stdRatio=%.2f chromaRatio=%.2f tone=%.0f(%.1f/255) outside=%.0f",
                     avgRemoved, stdRatio, chromaRatio, avgTone, avgTone / 257, avgOut))
        XCTAssertGreaterThan(avgRemoved, 6500, "브러시로 지목한 스크래치가 제거돼야 한다")
        XCTAssertGreaterThan(stdRatio, 0.62, "칠 안 그레인이 뭉개지면(블러) 안 된다")
        XCTAssertLessThan(stdRatio, 1.5, "칠 안 노이즈 과다")
        XCTAssertGreaterThan(chromaRatio, 0.55, "칠 안 크로마 그레인이 탈색되면 안 된다")
        XCTAssertLessThan(avgTone, 700, "칠 안 저주파 톤이 주변과 이어져야 한다(≈2.7/255 미만)")
        XCTAssertLessThan(avgOut, 130, "칠 밖(60px)은 변하면 안 된다(≈0.5/255 미만)")
    }

    /// 강도 즉시 경로의 계약: 패치(강도 1.0) 상수 알파 합성이 픽셀 단위로 선형이어야 한다 —
    /// compose(patches, s) == original + s·(compose(patches, 1) − original). 강도 슬라이더가
    /// heal 재계산 없이 캐시 패치 합성만으로 전체 재계산과 같은 결과를 낸다는 근거.
    func testPatchCompositionStrengthLinearity() throws {
        let w = 500, h = 400, base: Int = 24000, amp = 1200
        var seed: UInt64 = 0xA11CE
        func noise() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed >> 40) % (2 * amp + 1) - amp
        }
        var px = [(UInt16, UInt16, UInt16)](repeating: (0, 0, 0), count: w * h)
        for i in 0..<(w * h) {
            px[i] = (UInt16(max(0, min(65535, base + noise()))),
                     UInt16(max(0, min(65535, base + noise()))),
                     UInt16(max(0, min(65535, base + noise()))))
        }
        for y in 60..<340 {                       // 세로 스크래치(x=250)
            for x in 250...251 {
                let i = y * w + x
                let (r, g, b) = px[i]
                px[i] = (UInt16(min(65535, Int(r) + 9000)), UInt16(min(65535, Int(g) + 9000)),
                         UInt16(min(65535, Int(b) + 9000)))
            }
        }
        let cg = makeLinear16(w: w, h: h) { x, y in px[y * w + x] }
        let strokes = [DefectStroke(points: [CGPoint(x: 0.5, y: 0.15), CGPoint(x: 0.5, y: 0.85)],
                                    thickness: 0.05)]
        guard let patches = DefectBrush.removeDefectsPatches(in: cg, strokes: strokes,
                                                             parameters: SoftwareDefectParameters(
                                                                 strength: 1, dustSensitivity: 0.6,
                                                                 scratchSensitivity: 0.7, protectDetail: 0.6),
                                                             linear16: true),
              !patches.isEmpty else { return XCTFail("패치 계산 실패") }
        func compose(_ s: Double) -> [UInt16] {
            var working = CIImage(cgImage: cg, options: [.colorSpace: linear])
            for p in patches { working = p.composited(over: working, strength: s, colorSpace: linear) }
            let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
            guard let out = ctx.createCGImage(working, from: working.extent,
                                              format: .RGBA16, colorSpace: linear) else { return [] }
            return render16(out, w: w, h: h)
        }
        let orig = render16(cg, w: w, h: h)
        let full = compose(1.0)
        let half = compose(0.5)
        guard !full.isEmpty, !half.isEmpty else { return XCTFail("합성 렌더 실패") }
        var maxDev = 0
        for y in stride(from: 60, to: 340, by: 7) {
            for x in stride(from: 230, to: 272, by: 3) {
                let o = (y * w + x) * 4
                for c in 0..<3 {
                    let expected = Double(orig[o + c]) + 0.5 * (Double(full[o + c]) - Double(orig[o + c]))
                    maxDev = max(maxDev, abs(Int(half[o + c]) - Int(expected.rounded())))
                }
            }
        }
        print("[patch-linear] max deviation = \(maxDev)/65535")
        XCTAssertLessThan(maxDev, 260, "강도 합성이 선형이어야 즉시 경로가 전체 재계산과 일치한다(≈1/255 미만)")
    }

    /// 강도 50%: 제거량이 절반 수준(블렌드 비례) — 강도 무관 전체 밀림 회귀 감시.
    func testHalfStrengthScalesRemovalWithoutAreaWipe() throws {
        guard let r = runPipeline(strength: 0.5) else { return XCTFail("removeDefects nil") }
        let (before, after, scratch, centers, w, h) = r
        var resid = 0
        for (x, y) in scratch { resid += lum(after, w, x, y) - lum(before, w, x, y) }
        let avgRemoved = Double(-resid) / Double(scratch.count)
        // 저주파 톤은 강도와 무관하게 이어져야 한다(절반 블렌드도 톤 매칭 결과라 평균은 동일).
        var toneDiff = 0.0, toneCount = 0.0
        for (cx, cy) in centers where cy % 40 == 0 {
            toneDiff += abs(boxMean(after, w, h, cx + 9, cy) - boxMean(before, w, h, cx + 9, cy))
            toneCount += 1
        }
        let avgTone = toneDiff / max(1, toneCount)
        print(String(format: "[pipeline s=0.5] removed=%.0f/9000 tone=%.0f", avgRemoved, avgTone))
        XCTAssertGreaterThan(avgRemoved, 2500, "50%에서도 결함이 절반쯤 제거돼야 한다")
        XCTAssertLessThan(avgRemoved, 7000, "50%는 100%보다 약해야 한다(블렌드 비례)")
        XCTAssertLessThan(avgTone, 700, "강도와 무관하게 칠 안 톤이 밀리면 안 된다")
    }
}
