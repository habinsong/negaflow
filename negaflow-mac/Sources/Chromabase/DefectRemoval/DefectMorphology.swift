import Accelerate
import Foundation

// 순수 [Float] 배열 연산. 결함 검출 단계들이 공유하는 저수준 유틸.
// CoreImage 의존 없음 — 다운스케일된 작은 버퍼에서만 돈다.
enum DefectMorphology {
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

    /// 국소 최소(erosion, 플랫 사각 SE). vImage SIMD 경로 우선(min 은 정확 연산이라 결과가
    /// deque 구현과 비트 동일), 커널이 이미지보다 크거나 실패하면 deque 로 폴백한다.
    static func morphMin(_ src: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        vImageExtreme(src, width: width, height: height, radius: radius, isMax: false)
            ?? separableExtreme(src, width: width, height: height, radius: radius, isMax: false)
    }

    /// 국소 최대(dilation, 플랫 사각 SE). vImage SIMD 경로 우선 + deque 폴백(출력 동일).
    static func morphMax(_ src: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        vImageExtreme(src, width: width, height: height, radius: radius, isMax: true)
            ?? separableExtreme(src, width: width, height: height, radius: radius, isMax: true)
    }

    /// vImageMin/Max_PlanarF — 플랫 사각 SE 전용 고속(min/max) 경로. Apple 헤더가 플랫 SE 의
    /// erode/dilate 대신 쓰라고 명시한 함수로, 경계는 이미지 안 픽셀만 사용(클램프 윈도우)이라
    /// separableExtreme 과 결과가 동일하다(DefectMorphologyExactTests 가 naive 대조로 보증).
    /// 커널이 한 변이라도 이미지보다 크면 nil — 호출측이 deque 로 폴백한다.
    private static func vImageExtreme(_ src: [Float], width w: Int, height h: Int,
                                      radius r: Int, isMax: Bool) -> [Float]? {
        let kernel = 2 * r + 1
        guard r > 0, w > 0, h > 0, kernel <= w, kernel <= h else { return nil }
        var out = [Float](repeating: 0, count: w * h)
        let error: vImage_Error = src.withUnsafeBufferPointer { source in
            out.withUnsafeMutableBufferPointer { destination in
                var srcBuffer = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: source.baseAddress!),
                    height: vImagePixelCount(h), width: vImagePixelCount(w),
                    rowBytes: w * MemoryLayout<Float>.size
                )
                var dstBuffer = vImage_Buffer(
                    data: destination.baseAddress!,
                    height: vImagePixelCount(h), width: vImagePixelCount(w),
                    rowBytes: w * MemoryLayout<Float>.size
                )
                return isMax
                    ? vImageMax_PlanarF(&srcBuffer, &dstBuffer, nil, 0, 0,
                                        vImagePixelCount(kernel), vImagePixelCount(kernel),
                                        vImage_Flags(kvImageNoFlags))
                    : vImageMin_PlanarF(&srcBuffer, &dstBuffer, nil, 0, 0,
                                        vImagePixelCount(kernel), vImagePixelCount(kernel),
                                        vImage_Flags(kvImageNoFlags))
            }
        }
        return error == kvImageNoError ? out : nil
    }

    /// 적분영상 기반 박스 평균. O(N).
    ///
    /// 풀해상도 평면에서 전체 적분영상([Double] (w+1)×(h+1) ≈ 8·N bytes — 55MP 에서 440MB)을
    /// 잡지 않도록, 적분 행을 (2r+2)행 링 버퍼로만 유지한다. 각 적분 행은 기존 구현과 동일한
    /// 순서(행 누적합 + 직전 행 가산)로 계산하고 사각합/나눗셈 식도 동일해 출력이 비트 동일하다
    /// (DefectBoxMeanRollingEquivalenceTests 가 전체 적분 경로와 대조로 보증).
    static func boxMean(_ src: [Float], width w: Int, height h: Int, radius r: Int) -> [Float] {
        let iw = w + 1
        let ringRows = 2 * r + 2
        // 링이 전체 적분영상 크기에 근접하면 이득이 없다 — 기존 전체 적분 경로 사용.
        guard r >= 0, ringRows < h + 1 else { return boxMeans(src, width: w, height: h, radii: [r])[0] }
        var ring = [Double](repeating: 0, count: ringRows * iw)   // ring[row % ringRows]
        var out = [Float](repeating: 0, count: w * h)
        var built = 1   // 다음에 만들 적분 행 인덱스(행 0 = 전부 0, 링 초기값으로 유효).

        // 적분 행 rowIndex(=y+1)를 직전 행에서 만든다 — 전체 적분영상과 동일한 값.
        func buildRow(_ rowIndex: Int) {
            let y = rowIndex - 1
            let srcRow = y * w
            let currentBase = (rowIndex % ringRows) * iw
            let previousBase = ((rowIndex - 1) % ringRows) * iw
            var rowSum = 0.0
            ring[currentBase] = 0
            for x in 0..<w {
                rowSum += Double(src[srcRow + x])
                ring[currentBase + x + 1] = ring[previousBase + x + 1] + rowSum
            }
        }

        for y in 0..<h {
            let y0 = max(0, y - r), y1 = min(h - 1, y + r)
            // 필요한 적분 행 [y0, y1+1] 은 y 오름차순에서 단조 증가 — 링 재사용 슬롯은 항상
            // y0 보다 오래된 행이라 덮어써도 안전하다.
            while built <= y1 + 1 {
                buildRow(built)
                built += 1
            }
            let topBase = (y0 % ringRows) * iw
            let bottomBase = ((y1 + 1) % ringRows) * iw
            for x in 0..<w {
                let x0 = max(0, x - r), x1 = min(w - 1, x + r)
                let sum = ring[bottomBase + (x1 + 1)] - ring[topBase + (x1 + 1)]
                    - ring[bottomBase + x0] + ring[topBase + x0]
                out[y * w + x] = Float(sum / Double((y1 - y0 + 1) * (x1 - x0 + 1)))
            }
        }
        return out
    }

    /// Bool 마스크 팽창(플랫 사각 SE, 클램프 윈도우) — morphMax(0/1 Float) > 0.5 와 동일한
    /// 결과를 Float 임시 평면(8·N bytes) 없이 낸다. 분리형 슬라이딩 카운트, O(N).
    static func dilateMask(_ src: [Bool], width w: Int, height h: Int, radius r: Int) -> [Bool] {
        guard r > 0, w > 0, h > 0 else { return src }
        var tmp = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            let base = y * w
            var count = 0
            for x in 0...min(w - 1, r) where src[base + x] { count += 1 }
            for x in 0..<w {
                tmp[base + x] = count > 0
                let add = x + r + 1
                if add < w, src[base + add] { count += 1 }
                let drop = x - r
                if drop >= 0, src[base + drop] { count -= 1 }
            }
        }
        var out = [Bool](repeating: false, count: w * h)
        for x in 0..<w {
            var count = 0
            for y in 0...min(h - 1, r) where tmp[y * w + x] { count += 1 }
            for y in 0..<h {
                out[y * w + x] = count > 0
                let add = y + r + 1
                if add < h, tmp[add * w + x] { count += 1 }
                let drop = y - r
                if drop >= 0, tmp[drop * w + x] { count -= 1 }
            }
        }
        return out
    }

    /// 같은 입력의 여러 반경 박스 평균. 적분영상은 한 번만 만들고, 반경별 출력 계산은 필요하면
    /// 병렬화한다. 각 출력의 사각합 산술 순서는 boxMean 기존 구현과 동일하다.
    static func boxMeans(_ src: [Float], width w: Int, height h: Int,
                         radii: [Int], parallel: Bool = false) -> [[Float]] {
        guard !radii.isEmpty else { return [] }
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
        let integralValues = integral

        guard parallel, radii.count > 1 else {
            return radii.map {
                boxMeanOutput(
                    integral: integralValues, width: w, height: h,
                    integralWidth: iw, radius: $0
                )
            }
        }
        let results = ConcurrentResultStore<[Float]>(count: radii.count)
        DispatchQueue.concurrentPerform(iterations: radii.count) { index in
            results.set(
                boxMeanOutput(
                    integral: integralValues, width: w, height: h,
                    integralWidth: iw, radius: radii[index]
                ),
                at: index
            )
        }
        return results.snapshot().map { $0 ?? [] }
    }

    private static func boxMeanOutput(
        integral: [Double],
        width w: Int,
        height h: Int,
        integralWidth iw: Int,
        radius r: Int
    ) -> [Float] {
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
        src.withUnsafeBufferPointer { srcBuffer in
            dst.withUnsafeMutableBufferPointer { dstBuffer in
                deque.withUnsafeMutableBufferPointer { dequeBuffer in
                    // private 호출부가 src/dst 크기와 deque 길이를 보장한다. 포인터 루프는 같은
                    // 인덱스 순서를 유지하면서 픽셀마다 반복되던 Swift Array 경계 검사를 없앤다.
                    let source = srcBuffer.baseAddress!
                    let destination = dstBuffer.baseAddress!
                    let indices = dequeBuffer.baseAddress!
                    var head = 0, tail = 0          // deque 점유 구간 [head, tail)
                    var addIdx = 0
                    for x in 0..<n {
                        let hi = min(n - 1, x + r)
                        while addIdx <= hi {
                            let v = source[base + addIdx * stride]
                            if isMax {
                                while tail > head && source[base + indices[tail - 1] * stride] <= v {
                                    tail -= 1
                                }
                            } else {
                                while tail > head && source[base + indices[tail - 1] * stride] >= v {
                                    tail -= 1
                                }
                            }
                            indices[tail] = addIdx
                            tail += 1
                            addIdx += 1
                        }
                        let lo = max(0, x - r)
                        while indices[head] < lo { head += 1 }
                        destination[base + x * stride] = source[base + indices[head] * stride]
                    }
                }
            }
        }
    }
}
