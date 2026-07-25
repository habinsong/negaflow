import Foundation

// 질감 전사(v2, patch-based/texture-aware).
//
// 구조 채움(directionalFill/onion-peel)이 저주파 구조를 이었더라도 고주파 그레인·텍스처가
// 비면 "매끈한 자국"이 남는다. 여기서는 결함 주변의 성한 영역에서 exemplar(변위된 소스 패치)를
// 골라 그 고주파 잔차를 전사한다.
//
// v1은 변위 후보를 "성한 픽셀 비율"만으로 골랐다(외관 무관) — 텍스처 경계 옆 결함에서 다른
// 텍스처의 잔차가 섞일 수 있었다. v2는 Criminisi(2004) exemplar 매칭 정신으로 결함 둘레의
// 성한 컨텍스트 픽셀과 "변위된 위치의 픽셀" SSD 를 함께 본다 — 통계적으로 같은 텍스처 지역의
// 잔차만 가져온다. 잔차 클램프(±3σ)·cloneMix·폴백 노이즈 등 그레인 안전장치는 v1 그대로다.
extension DefectScratchRepairer {
    static func transferTexture(_ repaired: inout [Float], source rgba: [Float],
                                damagedOrig: [Bool], width: Int, height: Int,
                                filled: [Int], compCount: Int,
                                minX: Int, maxX: Int, minY: Int, maxY: Int,
                                crossAngle: Double?, sigma: (r: Float, g: Float, b: Float),
                                seed: inout UInt64) {
        guard !filled.isEmpty else { return }
        let maxSide = max(maxX - minX, maxY - minY) + 1
        let avgThick = Double(compCount) / Double(max(1, maxSide))
        let d = min(128, max(6, Int((avgThick * 2.0).rounded()) + 8))
        let cloneMix = Float(min(0.42, max(0, (avgThick - 10.0) / 120.0)))

        // 변위 후보: 스크래치 직교(우선) + 8방향 × 반경 {d, 2d}. 2d 링은 좁은 성한 틈밖에
        // 없는 d 링보다 넓은 텍스처 표본을 준다(성긴 결함 군집에서 유효).
        var candidates: [(dx: Int, dy: Int)] = []
        if let crossAngle {
            let rad = crossAngle * .pi / 180
            for r in [d, 2 * d] {
                let vx = Int((cos(rad) * Double(r)).rounded())
                let vy = Int((sin(rad) * Double(r)).rounded())
                candidates.append((vx, vy))
                candidates.append((-vx, -vy))
            }
        }
        for r in [d, 2 * d] {
            candidates += [(r, 0), (-r, 0), (0, r), (0, -r), (r, r), (-r, -r), (r, -r), (-r, r)]
        }

        let context = contextSamples(damagedOrig, width: width, height: height,
                                     minX: minX, maxX: maxX, minY: minY, maxY: maxY)
        let bestDisp = selectDisplacement(candidates, filled: filled, context: context,
                                          rgba: rgba, damagedOrig: damagedOrig,
                                          width: width, height: height)

        let cap = (r: max(1e-4, 3 * sigma.r), g: max(1e-4, 3 * sigma.g), b: max(1e-4, 3 * sigma.b))
        for p in filled {
            let y = p / width
            let x = p - y * width
            let o = p * 4
            var applied = false
            if let disp = bestDisp {
                let sx = x + disp.dx
                let sy = y + disp.dy
                if sx >= 1, sy >= 1, sx < width - 1, sy < height - 1, !damagedOrig[sy * width + sx] {
                    applied = applyTextureResidual(&repaired, source: rgba, damagedOrig: damagedOrig,
                                                   width: width, x: x, y: y, sx: sx, sy: sy,
                                                   cap: cap, cloneMix: cloneMix)
                }
            }
            if !applied {
                repaired[o] = clamp01(repaired[o] + (sigma.r > 0 ? sigma.r * nextNoise(&seed) : 0))
                repaired[o + 1] = clamp01(repaired[o + 1] + (sigma.g > 0 ? sigma.g * nextNoise(&seed) : 0))
                repaired[o + 2] = clamp01(repaired[o + 2] + (sigma.b > 0 ? sigma.b * nextNoise(&seed) : 0))
            }
        }
    }

    // MARK: exemplar 선택 (v2)

    /// 결함 bbox 둘레 링(pad 2~5)의 성한 픽셀 표본 — 변위 후보의 외관(SSD) 비교 기준.
    private static func contextSamples(_ damagedOrig: [Bool], width: Int, height: Int,
                                       minX: Int, maxX: Int, minY: Int, maxY: Int) -> [Int] {
        var ring: [Int] = []
        let x0 = max(0, minX - 5), x1 = min(width - 1, maxX + 5)
        let y0 = max(0, minY - 5), y1 = min(height - 1, maxY + 5)
        for y in y0...y1 {
            let inCoreY = y >= minY - 1 && y <= maxY + 1
            for x in x0...x1 {
                if inCoreY, x >= minX - 1, x <= maxX + 1 { continue }   // 결함에 붙은 1px 은 제외
                let p = y * width + x
                if !damagedOrig[p] { ring.append(p) }
            }
        }
        guard ring.count > 96 else { return ring }
        let stride = ring.count / 96
        var out: [Int] = []
        out.reserveCapacity(96)
        var i = 0
        while i < ring.count { out.append(ring[i]); i += stride }
        return out
    }

    /// 후보 변위 중 exemplar 를 고른다.
    ///  1차 게이트: 채운 픽셀의 변위 위치가 성한 비율(validFraction) — v1과 동일한 안전 조건.
    ///  2차 선택: 게이트 통과 후보 중 컨텍스트 SSD 최소 — 외관이 같은 텍스처 지역을 선호.
    private static func selectDisplacement(_ candidates: [(dx: Int, dy: Int)], filled: [Int],
                                           context: [Int], rgba: [Float], damagedOrig: [Bool],
                                           width: Int, height: Int) -> (dx: Int, dy: Int)? {
        let stride = max(1, filled.count / 64)
        var best: (disp: (dx: Int, dy: Int), valid: Double, ssd: Double)?
        for cand in candidates {
            var ok = 0, total = 0
            var i = 0
            while i < filled.count {
                let p = filled[i]
                let y = p / width
                let x = p - y * width
                let sx = x + cand.dx
                let sy = y + cand.dy
                total += 1
                if sx >= 1, sy >= 1, sx < width - 1, sy < height - 1, !damagedOrig[sy * width + sx] {
                    ok += 1
                }
                i += stride
            }
            let valid = total > 0 ? Double(ok) / Double(total) : 0
            guard valid > 0.25 else { continue }
            let ssd = contextSSD(context, disp: cand, rgba: rgba, damagedOrig: damagedOrig,
                                 width: width, height: height)
            // 유효 비율이 확실히 높은 후보(+0.15)는 SSD 이전에 우선한다 — 결함 위를 소스로 쓰는
            // 위험이 더 크다. 비슷한 유효 비율끼리는 외관(SSD)이 좋은 쪽을 고른다.
            if let b = best {
                if valid > b.valid + 0.15 || (valid > b.valid - 0.15 && ssd < b.ssd) {
                    best = (cand, valid, ssd)
                }
            } else {
                best = (cand, valid, ssd)
            }
        }
        return best?.disp
    }

    /// 컨텍스트 표본과 "변위된 소스" 픽셀의 평균 채널 SSD. 소스가 결함/범위 밖인 표본은 제외하고,
    /// 유효 표본이 절반 미만이면 ∞(최후순위) — 외관 증거가 부족한 변위는 신뢰하지 않는다.
    private static func contextSSD(_ context: [Int], disp: (dx: Int, dy: Int),
                                   rgba: [Float], damagedOrig: [Bool],
                                   width: Int, height: Int) -> Double {
        guard !context.isEmpty else { return .greatestFiniteMagnitude }
        var sum = 0.0
        var count = 0
        for p in context {
            let y = p / width
            let x = p - y * width
            let sx = x + disp.dx, sy = y + disp.dy
            guard sx >= 0, sy >= 0, sx < width, sy < height else { continue }
            let q = sy * width + sx
            guard !damagedOrig[q] else { continue }
            let o = p * 4, so = q * 4
            let dr = Double(rgba[o] - rgba[so])
            let dg = Double(rgba[o + 1] - rgba[so + 1])
            let db = Double(rgba[o + 2] - rgba[so + 2])
            sum += dr * dr + dg * dg + db * db
            count += 1
        }
        guard count * 2 >= context.count else { return .greatestFiniteMagnitude }
        return sum / Double(count)
    }

    private static func applyTextureResidual(_ repaired: inout [Float], source rgba: [Float],
                                             damagedOrig: [Bool], width: Int,
                                             x: Int, y: Int, sx: Int, sy: Int,
                                             cap: (r: Float, g: Float, b: Float),
                                             cloneMix: Float) -> Bool {
        var mr: Float = 0
        var mg: Float = 0
        var mb: Float = 0
        var c: Float = 0
        for ny in (sy - 1)...(sy + 1) {
            for nx in (sx - 1)...(sx + 1) {
                let q = ny * width + nx
                guard !damagedOrig[q] else { continue }
                let qo = q * 4
                mr += rgba[qo]
                mg += rgba[qo + 1]
                mb += rgba[qo + 2]
                c += 1
            }
        }
        guard c >= 4 else { return false }
        let o = (y * width + x) * 4
        let so = (sy * width + sx) * 4
        let keep = 1 - cloneMix
        let r = repaired[o] * keep + rgba[so] * cloneMix
        let g = repaired[o + 1] * keep + rgba[so + 1] * cloneMix
        let b = repaired[o + 2] * keep + rgba[so + 2] * cloneMix
        repaired[o] = clamp01(r + min(cap.r, max(-cap.r, (rgba[so] - mr / c) * 0.8)))
        repaired[o + 1] = clamp01(g + min(cap.g, max(-cap.g, (rgba[so + 1] - mg / c) * 0.8)))
        repaired[o + 2] = clamp01(b + min(cap.b, max(-cap.b, (rgba[so + 2] - mb / c) * 0.8)))
        return true
    }

    static func grainSigmaRGB(_ rgba: [Float], damaged: [Bool], width: Int, height: Int,
                              minX: Int, maxX: Int, minY: Int, maxY: Int)
        -> (r: Float, g: Float, b: Float) {
        let pad = 4
        let x0 = max(1, minX - pad)
        let x1 = min(width - 2, maxX + pad)
        let y0 = max(1, minY - pad)
        let y1 = min(height - 2, maxY + pad)
        guard x1 >= x0, y1 >= y0 else { return (0, 0, 0) }

        var sum = (r: Float(0), g: Float(0), b: Float(0))
        var count: Float = 0
        for y in y0...y1 {
            for x in x0...x1 {
                let p = y * width + x
                guard !damaged[p] else { continue }
                guard let mean = localMeanRGB(rgba, damaged: damaged, width: width, x: x, y: y) else { continue }
                let o = p * 4
                sum.r += abs(rgba[o] - mean.r)
                sum.g += abs(rgba[o + 1] - mean.g)
                sum.b += abs(rgba[o + 2] - mean.b)
                count += 1
            }
        }
        guard count > 8 else { return (0, 0, 0) }
        return (min(0.05, sum.r / count * 1.25),
                min(0.05, sum.g / count * 1.25),
                min(0.05, sum.b / count * 1.25))
    }

    private static func localMeanRGB(_ rgba: [Float], damaged: [Bool], width: Int, x: Int, y: Int)
        -> (r: Float, g: Float, b: Float)? {
        var r: Float = 0
        var g: Float = 0
        var b: Float = 0
        var c: Float = 0
        for ny in (y - 1)...(y + 1) {
            for nx in (x - 1)...(x + 1) {
                let q = ny * width + nx
                guard !damaged[q] else { continue }
                let o = q * 4
                r += rgba[o]
                g += rgba[o + 1]
                b += rgba[o + 2]
                c += 1
            }
        }
        return c > 0 ? (r / c, g / c, b / c) : nil
    }

    private static func nextNoise(_ state: inout UInt64) -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return (Float(state >> 40) / Float(1 << 24) * 2 - 1) * 1.23
    }
}
