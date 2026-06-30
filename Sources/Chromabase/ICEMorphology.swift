import Foundation

// 순수 [Float] 배열 연산. 결함 검출 단계들이 공유하는 저수준 유틸.
// CoreImage 의존 없음 — 다운스케일된 작은 버퍼에서만 돈다.
enum ICEMorphology {
    /// 그레이스케일 opening = dilation(erosion). SE보다 작은 밝은 구조를 제거한다.
    static func opening(_ src: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        morphMax(morphMin(src, width: width, height: height, radius: radius),
                 width: width, height: height, radius: radius)
    }

    /// 그레이스케일 closing = erosion(dilation). SE보다 작은 어두운 구조를 메운다.
    static func closing(_ src: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        morphMin(morphMax(src, width: width, height: height, radius: radius),
                 width: width, height: height, radius: radius)
    }

    /// 분리형 국소 최소(erosion). O(N·r).
    static func morphMin(_ src: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        separable(src, width: width, height: height, radius: radius, seed: .greatestFiniteMagnitude) {
            $1 < $0 ? $1 : $0
        }
    }

    /// 분리형 국소 최대(dilation). O(N·r).
    static func morphMax(_ src: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        separable(src, width: width, height: height, radius: radius, seed: -.greatestFiniteMagnitude) {
            $1 > $0 ? $1 : $0
        }
    }

    /// 적분영상 기반 박스 평균. O(N).
    static func boxMean(_ src: [Float], width w: Int, height h: Int, radius r: Int) -> [Float] {
        let iw = w + 1
        var integral = [Double](repeating: 0, count: iw * (h + 1))
        for y in 0..<h {
            var rowSum = 0.0
            let srcRow = y * w, intRow = (y + 1) * iw, intPrev = y * iw
            for x in 0..<w {
                rowSum += Double(src[srcRow + x])
                integral[intRow + x + 1] = integral[intPrev + x + 1] + rowSum
            }
        }
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let y0 = max(0, y - r), y1 = min(h - 1, y + r)
            for x in 0..<w {
                let x0 = max(0, x - r), x1 = min(w - 1, x + r)
                let sum = integral[(y1 + 1) * iw + (x1 + 1)] - integral[y0 * iw + (x1 + 1)]
                    - integral[(y1 + 1) * iw + x0] + integral[y0 * iw + x0]
                out[y * w + x] = Float(sum / Double((y1 - y0 + 1) * (x1 - x0 + 1)))
            }
        }
        return out
    }

    /// 분리형(수평→수직) 누적 연산 공통 구현.
    private static func separable(_ src: [Float], width w: Int, height h: Int, radius r: Int,
                                  seed: Float, _ combine: (Float, Float) -> Float) -> [Float] {
        var tmp = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let base = y * w
            for x in 0..<w {
                var acc = seed
                let x0 = max(0, x - r), x1 = min(w - 1, x + r)
                var xx = x0
                while xx <= x1 { acc = combine(acc, src[base + xx]); xx += 1 }
                tmp[base + x] = acc
            }
        }
        var out = [Float](repeating: 0, count: w * h)
        for x in 0..<w {
            for y in 0..<h {
                var acc = seed
                let y0 = max(0, y - r), y1 = min(h - 1, y + r)
                var yy = y0
                while yy <= y1 { acc = combine(acc, tmp[yy * w + x]); yy += 1 }
                out[y * w + x] = acc
            }
        }
        return out
    }
}
