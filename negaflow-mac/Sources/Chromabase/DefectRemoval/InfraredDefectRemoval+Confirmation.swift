import Foundation

// MARK: - 가시광 대조 확인 (결함 하나하나를 사진에서 확인하고, 가린 양을 직접 잰다)
//
// IR 이 어둡다는 것만으로 지우면 안 된다. 실측(GT-X900 컬러 네거티브 18컷)에서:
//   • 어떤 컷은 IR 결함의 94~100% 가 사진에서 ±1px 안에 그대로 있었고,
//   • 어떤 컷은 가장 진한 IR 결함 20개 중 **단 1개**만 사진에 대응물이 있었다.
// 두 패스는 별개의 캐리지 왕복이고 초점·정합이 컷마다 다르기 때문이다. 전역 정수 이동 하나로는
// 원리적으로 못 맞춘다 — 그 컷의 결함 87개 중 전역 이동에 맞는 것은 9% 뿐이었다.
//
// 그래서 IR 은 **후보를 제안**만 하고, 최종 판단과 보정량은 **사진에서** 잰다:
//   1) 후보마다 그 결함만 가장 잘 맞는 국소 이동을 찾는다(정합이 프레임 안에서 변해도 따라간다).
//   2) 봉우리가 잡음 위로 솟았는지 z 로 검정한다. 못 솟으면 **버린다** — 사진에 없는 것은
//      지울 것도 없다. 장면 고스트·IR 잡음·정합 실패가 여기서 전부 걸러진다.
//   3) 배율 k(가시광 밀도 ÷ IR 밀도)를 그 결함에서 최소자승으로 잰다. 전역 상수가 아니다.
extension InfraredDefectRemoval {

    struct ConfirmedDefect {
        let offsetX: Int
        let offsetY: Int
        /// 가시광 밀도 = gain × IR 밀도. 그 결함에서 실측한 값.
        let gain: Float
        /// 봉우리가 잡음 대비 몇 σ 인가.
        let significance: Float
    }

    /// 후보 하나를 사진에서 확인한다. 확인되지 않으면 nil(= 보정하지 않음).
    ///
    /// - pixels: 후보 픽셀(IR 좌표 = 이미 전역 이동이 적용된 격자).
    /// - weights: 각 픽셀의 IR 밀도(바닥을 뺀 값). 깊은 곳이 정합과 배율을 지배해야 한다.
    /// - visible: 부호 있는 가시광 밀도 평면.
    /// - search: 국소 이동 탐색 반경(px). 결함의 **좁은 쪽 반지름**보다 넉넉히 커야 한다.
    /// - extent: 결함의 좁은 쪽 반지름(px). 이보다 많이 밀면 결함에서 벗어난다 — 귀무 표본의 기준.
    /// - origin: 탐색 중심(합의 이동). 결함마다의 잔차만 그 둘레에서 찾는다.
    static func confirmDefect(
        pixels: [Int],
        weights: [Float],
        visible: [Float],
        width: Int,
        height: Int,
        search: Int,
        extent: Int,
        originX: Int = 0,
        originY: Int = 0,
        minimumSignificance: Float
    ) -> ConfirmedDefect? {
        guard pixels.count == weights.count, !pixels.isEmpty, search >= 0 else { return nil }
        var weightSum: Double = 0
        var weightSquareSum: Double = 0
        for w in weights {
            weightSum += Double(w)
            weightSquareSum += Double(w) * Double(w)
        }
        guard weightSum > 0, weightSquareSum > 0 else { return nil }

        let side = 2 * search + 1
        var scores = [Double](repeating: 0, count: side * side)
        var best = (score: -Double.infinity, index: 0)
        pixels.withUnsafeBufferPointer { points in
            weights.withUnsafeBufferPointer { w in
                visible.withUnsafeBufferPointer { vis in
                    for dy in -search...search {
                        for dx in -search...search {
                            var sum: Double = 0
                            for i in 0..<points.count {
                                let p = points[i]
                                let x = p % width + dx + originX
                                let y = p / width + dy + originY
                                guard x >= 0, x < width, y >= 0, y < height else { continue }
                                sum += Double(w[i]) * Double(vis[y * width + x])
                            }
                            let index = (dy + search) * side + (dx + search)
                            scores[index] = sum
                            if sum > best.score { best = (sum, index) }
                        }
                    }
                }
            }
        }
        guard best.score > 0 else { return nil }

        // 귀무 분포는 **결함과 겹칠 수 없는 이동**에서만, 중앙값과 MAD 로 잡는다.
        //
        // 중앙값·MAD 인 이유: 평균·표준편차를 쓰면 곧은 스크래치가 자기 자신을 귀무로 삼는다.
        // 축 방향으로 밀어도 여전히 스크래치 위라 점수가 안 떨어져 봉우리가 능선이 되고, 산포가
        // 부풀어 진짜 스크래치가 통째로 기각된다(실측: 픽스처의 스크래치 2개 전부 기각).
        //
        // 겹치는 이동을 빼는 이유: 결함이 탐색 상자만큼 크면 **어디로 밀어도 여전히 결함 위**라
        // 중앙값이 봉우리 가까이 올라간다. 그러면 잰 배율이 절반으로 줄어 큰 먼지가 옅게 남는다
        // (실측 GT-X900 2400dpi: 좁은쪽 반지름 12~17px 결함의 중심 제거율 73%, 같은 컷의
        // 3~4px 먼지는 80%). 좁은쪽 지름(2·extent)보다 멀리 민 이동만 쓰면 그 오염이 사라진다.
        // 상자 안에 그런 이동이 모자라면 상자 밖 고리를 더 잰다 — 큰 결함에서만 드는 비용이다.
        //
        // 중앙값은 "이 자리에 결함이 없었다면 사진의 결만으로 나왔을 점수"이기도 하다. 그걸
        // 빼야 배율이 결함이 가린 양이 된다(실측: 안 빼면 결함 48개 중 22개가 과보정).
        let nullInner = 2 * extent + 2
        var nullSamples: [Double] = []
        nullSamples.reserveCapacity(side * side)
        for dy in -search...search {
            for dx in -search...search where max(abs(dx), abs(dy)) >= nullInner {
                nullSamples.append(scores[(dy + search) * side + (dx + search)])
            }
        }
        var ring = max(nullInner, search + 1)
        let ringLimit = ring + 2 * extent + 8
        while nullSamples.count < minimumNullSamples, ring <= ringLimit {
            appendRingScores(radius: ring, pixels: pixels, weights: weights, visible: visible,
                             width: width, height: height,
                             originX: originX, originY: originY, into: &nullSamples)
            ring += 1
        }
        // 귀무를 잴 표본이 없으면 판정하지 않는다 — "잡음보다 높은가"에 답할 수 없다.
        guard nullSamples.count >= 32 else { return nil }
        nullSamples.sort()
        let mean = nullSamples[nullSamples.count / 2]
        var spread = nullSamples.map { abs($0 - mean) }
        spread.sort()
        let deviation = 1.4826 * spread[spread.count / 2]
        // 배경 산포가 정확히 0 이면(완전 합성 평면) 잡음이 없다는 뜻이다. 그때는 봉우리가
        // 조금이라도 배경 위면 확실한 결함이다 — 불확실하다고 기각하면 정반대로 판단하는 것이다.
        let significance = deviation > 0
            ? Float((best.score - mean) / deviation)
            : Float.greatestFiniteMagnitude
        guard significance >= minimumSignificance else { return nil }
        // 봉우리는 탐색면의 **최대값**이라 잡음이 우연히 보태진 만큼 위로 뜬다(승자의 저주).
        // 그 편향은 잡음 1σ 규모이므로 함께 뺀다 — 덜 지운 자국은 옅게 남을 뿐이지만
        // 과보정은 없던 밝은 얼룩을 만든다.
        let signal = best.score - mean - deviation
        guard signal > 0 else { return nil }

        let gain = Float(signal / weightSquareSum)
        guard gain.isFinite, gain > 0 else { return nil }
        return ConfirmedDefect(
            offsetX: best.index % side - search + originX,
            offsetY: best.index / side - search + originY,
            gain: gain,
            significance: significance
        )
    }

    /// 귀무 분포를 잴 최소 표본 수. 중앙값·MAD 가 사진의 결 하나에 끌려가지 않을 만큼.
    static let minimumNullSamples = 200

    /// 체비쇼프 반지름이 정확히 `radius` 인 이동들의 점수. 탐색 상자 밖에서 귀무를 보충한다.
    static func appendRingScores(
        radius: Int,
        pixels: [Int],
        weights: [Float],
        visible: [Float],
        width: Int,
        height: Int,
        originX: Int,
        originY: Int,
        into samples: inout [Double]
    ) {
        guard radius > 0 else { return }
        samples.reserveCapacity(samples.count + 8 * radius)
        pixels.withUnsafeBufferPointer { points in
            weights.withUnsafeBufferPointer { w in
                visible.withUnsafeBufferPointer { vis in
                    for dy in -radius...radius {
                        let step = abs(dy) == radius ? 1 : 2 * radius
                        var dx = -radius
                        while dx <= radius {
                            var sum: Double = 0
                            for i in 0..<points.count {
                                let p = points[i]
                                let x = p % width + dx + originX
                                let y = p / width + dy + originY
                                guard x >= 0, x < width, y >= 0, y < height else { continue }
                                sum += Double(w[i]) * Double(vis[y * width + x])
                            }
                            samples.append(sum)
                            dx += step
                        }
                    }
                }
            }
        }
    }

    /// 나눗셈으로 되돌릴 수 있는 배율의 상한/하한.
    ///
    /// 가림은 파장에 대해 거의 평평하므로 물리적 기대값은 1 근처지만, 두 패스의 초점이 다르면
    /// 같은 결함이 한쪽에서 더 퍼져 보인다. 그래서 넓게 열어 두고 **값은 결함마다 실측**한다.
    /// 이 범위는 필름·스캐너 상수가 아니라 나눗셈이 발산하지 않게 하는 안전선이다.
    static func clampGain(_ gain: Float) -> Float {
        min(max(gain, 0.2), 4)
    }
}
