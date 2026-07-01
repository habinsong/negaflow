import Foundation
import CoreGraphics

// 라이트룸식 자동 보정(고전 알고리즘, AI 아님). 호출측(AppModel)이 대상 슬라이더를 0 으로 리셋한
// **중립 현상본**을 렌더해 그 통계를 넘기고, 여기 반환값을 슬라이더에 **대입**한다(누적 아님) → 1회 결정적.
//  • Auto WB = gray-world **full-correction**(ColorModel 계수 0.18/0.24 역산) → Warmth/Tint 로 무채색화.
//  • Auto Tone = Exposure(**하이라이트 p99 기준** — mean 기반이 밝은 씬을 어둡게 만드는 결함 회피),
//    Whites/Blacks(풀스트레치), Highlights/Shadows(클리핑+분포), Contrast(분산), Vibrance(채도).
public enum AutoAdjust {
    public struct ImageStats: Sendable, Equatable {
        public var avgR: Double, avgG: Double, avgB: Double   // 0..1
        public var lumaHist: [Double]                         // 256 bins, 합=1
        public var avgSaturation: Double                      // 0..1 (HSV S 평균)
        public init(avgR: Double, avgG: Double, avgB: Double, lumaHist: [Double], avgSaturation: Double) {
            self.avgR = avgR; self.avgG = avgG; self.avgB = avgB
            self.lumaHist = lumaHist; self.avgSaturation = avgSaturation
        }
    }

    /// 현상 결과 톤 보정 델타. 현재 DevelopParameters 위에 더한다(clamp는 호출측).
    public struct ToneDelta: Sendable, Equatable {
        public var exposure = 0.0, contrast = 0.0, highlight = 0.0, shadow = 0.0
        public var whites = 0.0, blacks = 0.0, vibrance = 0.0, saturation = 0.0
        public init() {}
    }

    // MARK: 이미지 통계 (다운샘플 RGBA8 → 평균색/luma 히스토그램/채도)

    /// CGImage 를 작은 격자로 다운샘플해 통계를 낸다(전체 픽셀 순회 불필요 — Lanczos 없이 ctx.draw 보간).
    public static func imageStats(_ cg: CGImage, sample: Int = 200) -> ImageStats? {
        let longSide = max(cg.width, cg.height)
        guard longSide > 0 else { return nil }
        let scale = min(1.0, Double(sample) / Double(longSide))
        let w = max(1, Int(Double(cg.width) * scale)), h = max(1, Int(Double(cg.height) * scale))
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumSat = 0.0
        var hist = [Double](repeating: 0, count: 256)
        let n = w * h
        for i in 0..<n {
            let o = i * 4
            let r = Double(data[o]) / 255, g = Double(data[o + 1]) / 255, b = Double(data[o + 2]) / 255
            sumR += r; sumG += g; sumB += b
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            hist[min(255, max(0, Int(luma * 255)))] += 1
            let mx = max(r, max(g, b)), mn = min(r, min(g, b))
            sumSat += mx > 1e-6 ? (mx - mn) / mx : 0
        }
        let nd = Double(n)
        return ImageStats(avgR: sumR / nd, avgG: sumG / nd, avgB: sumB / nd,
                          lumaHist: hist.map { $0 / nd }, avgSaturation: sumSat / nd)
    }

    // MARK: Auto White Balance (gray-world)

    /// 평균색이 무채색이 되도록 Warmth/Tint 절대값. **정확한 full-correction**: ColorModel 의 실제 계수
    /// (warmth ±0.18, tint G+0.24 / RB−0.12)를 역산해 결과가 R'=B', G'=(R'+B')/2 가 되는 값을 낸다.
    /// (과거 임의 gain 1.1 은 필요치 ≈2.8 의 40% 라 캐스트가 거의 안 지워져 "작동 안 함" 이었다.)
    public static func autoWhiteBalance(_ s: ImageStats) -> (warmth: Double, tint: Double) {
        // Warmth: R(1+0.18w) = B(1−0.18w) → w = (B−R) / (0.18·(R+B)).  R>B(따뜻)면 음수(식힘).
        let wDen = 0.18 * (s.avgR + s.avgB)
        let warmth = wDen > 1e-4 ? clamp((s.avgB - s.avgR) / wDen, -1, 1) : 0
        // Tint: G(1+0.24t) = (R+B)/2·(1−0.12t) → t = ((R+B)/2 − G) / (0.24·G + 0.06·(R+B)).
        let tDen = 0.24 * s.avgG + 0.06 * (s.avgR + s.avgB)
        let tint = tDen > 1e-4 ? clamp(((s.avgR + s.avgB) / 2 - s.avgG) / tDen, -1, 1) : 0
        return (warmth, tint)
    }

    // MARK: Auto Tone (histogram / clipping)

    public static func autoTone(_ s: ImageStats) -> ToneDelta {
        var d = ToneDelta()
        let hist = s.lumaHist
        func percentile(_ p: Double) -> Double {
            var acc = 0.0
            for i in 0..<256 { acc += hist[i]; if acc >= p { return Double(i) / 255 } }
            return 1
        }
        let p99 = percentile(0.99)
        let p005 = percentile(0.005), p995 = percentile(0.995)
        let p025 = percentile(0.025), p975 = percentile(0.975)
        var mean = 0.0
        for i in 0..<256 { mean += Double(i) / 255 * hist[i] }
        var variance = 0.0
        for i in 0..<256 { let dv = Double(i) / 255 - mean; variance += dv * dv * hist[i] }
        let std = variance.squareRoot()
        let clipHigh = hist[255], clipLow = hist[0]

        // Exposure: **하이라이트(p99) 기준.** mean/median 을 목표로 밀면 밝은 씬(하늘/눈)을 잘못 어둡게
        // 만든다(문헌 공통 결함) — 하이라이트를 목표 0.90 으로 맞춰 어두운 씬만 올리고, 밝은 씬(p99 이미
        // 높음)은 거의 안 내린다. 과노출 클리핑은 아래 Highlights 가 복구한다.
        d.exposure = clamp(log2(0.90 / max(0.06, p99)) * 1.1, -1.2, 1.5)
        // Whites/Blacks: 상/하위 0.5% 를 거의 끝(0.97/0.03)으로 — 히스토그램 풀스트레치.
        d.whites = clamp((0.97 - p995) * 2.2, -1, 1)
        d.blacks = clamp((0.03 - p005) * 2.2, -1, 1)
        // Highlights/Shadows: 톤 분포 + 클리핑. 상위(p97.5)가 밝게 몰리거나 클리핑되면 Highlights 를
        // 내려(-) 복구, 하위(p2.5)가 어둡게 몰리거나 클리핑되면 Shadows 를 올려(+) 복구. 한 방향만
        // 작동(반대쪽 0)해 자연스러운 톤 밸런스가 되고, 노출 외의 슬라이더도 이미지에 맞게 움직인다.
        d.highlight = clamp(-clipHigh * 8.0 - max(0, p975 - 0.88) * 1.5, -1, 0)
        d.shadow = clamp(clipLow * 8.0 + max(0, 0.12 - p025) * 1.5, 0, 1)
        // Contrast: 분산이 작으면(평평) 올리고, 과대비면 내린다.
        d.contrast = clamp((0.20 - std) * 2.0, -0.5, 0.5)
        // Vibrance: 채도가 낮으면 부스트(+ only — 라이트룸 Auto 도 채도를 거의 올리기만 한다).
        d.vibrance = clamp((0.42 - s.avgSaturation) * 1.0, 0, 0.6)
        return d
    }

    @inline(__always)
    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
}
