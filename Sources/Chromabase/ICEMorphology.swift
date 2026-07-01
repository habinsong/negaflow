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

    /// 분리형 국소 최소(erosion). monotonic-deque sliding min 으로 반경 무관 O(N).
    static func morphMin(_ src: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        separableExtreme(src, width: width, height: height, radius: radius, isMax: false)
    }

    /// 분리형 국소 최대(dilation). monotonic-deque sliding max 로 반경 무관 O(N).
    static func morphMax(_ src: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        separableExtreme(src, width: width, height: height, radius: radius, isMax: true)
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

    /// 분리형(수평→수직) 국소 극값. van Herk/Gil-Werman 계열의 monotonic-deque sliding
    /// min/max — 창 크기(2r+1)와 무관하게 픽셀당 amortized 상수 연산이다(O(N)). 결과는 기존
    /// naïve 구현과 **동일**: 각 위치에서 클램프 윈도우 [max(0,i-r), min(n-1,i+r)]의 극값.
    private static func separableExtreme(_ src: [Float], width w: Int, height h: Int,
                                         radius r: Int, isMax: Bool) -> [Float] {
        var tmp = [Float](repeating: 0, count: w * h)
        var deque = [Int](repeating: 0, count: max(w, h))   // 단조 deque(라인마다 재사용)
        for y in 0..<h {
            sweepLine(src, &tmp, base: y * w, n: w, stride: 1, r: r, deque: &deque, isMax: isMax)
        }
        var out = [Float](repeating: 0, count: w * h)
        for x in 0..<w {
            sweepLine(tmp, &out, base: x, n: h, stride: w, r: r, deque: &deque, isMax: isMax)
        }
        return out
    }

    /// 한 라인(길이 n, stride 간격)에서 클램프 윈도우 sliding min/max. deque 는 라인 인덱스를
    /// 값 단조 순으로 유지 — front 가 현재 윈도우 극값이다.
    private static func sweepLine(_ src: [Float], _ dst: inout [Float],
                                  base: Int, n: Int, stride: Int, r: Int,
                                  deque: inout [Int], isMax: Bool) {
        var head = 0, tail = 0          // deque 점유 구간 [head, tail)
        var addIdx = 0
        for x in 0..<n {
            let hi = min(n - 1, x + r)
            while addIdx <= hi {
                let v = src[base + addIdx * stride]
                if isMax {
                    while tail > head && src[base + deque[tail - 1] * stride] <= v { tail -= 1 }
                } else {
                    while tail > head && src[base + deque[tail - 1] * stride] >= v { tail -= 1 }
                }
                deque[tail] = addIdx; tail += 1
                addIdx += 1
            }
            let lo = max(0, x - r)
            while deque[head] < lo { head += 1 }
            dst[base + x * stride] = src[base + deque[head] * stride]
        }
    }
}
