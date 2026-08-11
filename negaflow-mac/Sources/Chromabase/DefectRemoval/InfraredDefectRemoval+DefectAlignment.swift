import Foundation

// MARK: - 결함 신호 기반 IR↔raw 정합
//
// IR 패스는 본 스캔과 별개의 캐리지 왕복이라 두 이미지가 몇 px 어긋난다. 어긋난 양은
// 스캐너·필름·컷마다 다르므로 상수로 둘 수 없다 — 같은 롤 같은 스캐너에서도 실측이
// (-5,-3) / (-2,+1) / (-1,+1) / (-1,+2) / (0,+1) 로 컷마다 달랐다.
//
// 장면 누설(염료가 IR 로 새는 성분)로 맞추면 안 된다. 누설은 부드러운 저주파라 몇 px
// 안에서 상관이 평평하다: 실측에서 최고점 0.47665, 차점 0.47649 로 사실상 무승부였고
// 그렇게 고른 오프셋은 참값과 5~6px 어긋났다. 그 어긋남이 "검출은 되는데 제거가 안 된다"의
// 원인이다 — 마스크가 결함 옆의 깨끗한 필름에 놓여, 복원이 멀쩡한 픽셀을 덮고 결함은 남는다.
//
// 결함은 반대로 뾰족하다. IR 에서 빛을 막은 자리는 가시광에서도 막혀 있어야 하므로,
// "IR 결함점 위의 raw 국소 어두움"이 최대가 되는 정수 이동이 참 정합이다. 실측에서 이 점수는
// 참값에서 무이동 대비 1.1~2.0 배로 솟는 단봉이었다.
extension InfraredDefectRemoval {

    struct DefectAlignment {
        let offsetX: Int
        let offsetY: Int
        let peak: Double
        let runnerUp: Double
        let pointCount: Int
        /// 최적점이 탐색 경계면에 걸렸는가(더 큰 오프셋이 숨어 있을 수 있다).
        let atSearchLimit: Bool
    }

    /// 결함 신호가 충분할 때만 값을 돌려준다. 부족하면 nil — 호출측이 누설 상관으로 물러난다.
    static func estimateDefectAlignment(
        infrared: [Float],
        red: [Float],
        width: Int,
        height: Int,
        searchRadius: Int
    ) -> DefectAlignment? {
        guard searchRadius > 0, width > 4 * searchRadius, height > 4 * searchRadius else { return nil }
        let inset = max(searchRadius + 2, min(width, height) / 32)
        guard width > 2 * inset, height > 2 * inset else { return nil }

        // 필름 자신의 IR 분포에서 결함 문턱을 세운다(절대값 금지 — 기준선은 롤 안에서도 움직인다).
        var sample: [Float] = []
        sample.reserveCapacity(((width - 2 * inset) / 3 + 1) * ((height - 2 * inset) / 3 + 1))
        var y = inset
        while y < height - inset {
            let row = y * width
            var x = inset
            while x < width - inset { sample.append(infrared[row + x]); x += 3 }
            y += 3
        }
        guard sample.count > 64 else { return nil }
        sample.sort()
        let base = sample[Int(0.90 * Double(sample.count - 1))]
        let median = sample[sample.count / 2]
        let spread = base - median
        // 투과가 완전히 균일하면(합성 평면 등) 결함 문턱을 세울 수 없다.
        guard base > 1e-4, spread > base * 1e-3 else { return nil }
        let cut = base - 4 * spread

        var points: [Int] = []
        var weights: [Float] = []
        y = inset
        while y < height - inset {
            let row = y * width
            for x in inset..<(width - inset) where infrared[row + x] < cut {
                points.append(row + x)
                weights.append((base - infrared[row + x]) / base)
            }
            y += 1
        }
        guard points.count >= 16 else { return nil }
        // 점이 많아도 정합 정확도는 더 오르지 않는다 — 강한 것부터 상한까지만 쓴다.
        let limit = 20_000
        if points.count > limit {
            let order = (0..<points.count).sorted { weights[$0] > weights[$1] }.prefix(limit)
            points = order.map { points[$0] }
            weights = order.map { weights[$0] }
        }

        // raw 의 국소 어두움: 결함은 주변보다 어둡다. 밝기 자체가 아니라 국소 대비를 본다.
        let radius = max(4, min(24, min(width, height) / 200))
        var darkness = DefectMorphology.boxMean(red, width: width, height: height, radius: radius)
        for i in 0..<(width * height) { darkness[i] = max(0, darkness[i] - red[i]) }

        let totalWeight = Double(weights.reduce(0, +))
        guard totalWeight > 0 else { return nil }

        var best = (score: -Double.infinity, dx: 0, dy: 0)
        var scoreSum = 0.0
        var scoreCount = 0.0
        var scores: [Int: Double] = [:]
        darkness.withUnsafeBufferPointer { dark in
            points.withUnsafeBufferPointer { pts in
                weights.withUnsafeBufferPointer { wts in
                    for dy in -searchRadius...searchRadius {
                        for dx in -searchRadius...searchRadius {
                            var sum = 0.0
                            for i in 0..<pts.count {
                                let p = pts[i]
                                let px = p % width + dx
                                let py = p / width + dy
                                guard px >= 0, px < width, py >= 0, py < height else { continue }
                                sum += Double(dark[py * width + px] * wts[i])
                            }
                            let score = sum / totalWeight
                            scores[(dy + searchRadius) * (2 * searchRadius + 1) + (dx + searchRadius)] = score
                            scoreSum += score
                            scoreCount += 1
                            if score > best.score { best = (score, dx, dy) }
                        }
                    }
                }
            }
        }
        guard best.score > 0, scoreCount > 0 else { return nil }

        // 차점은 최적점에서 2px 넘게 떨어진 것 중 최대 — 봉우리가 넓은 것과 봉우리가 둘인 것을 가른다.
        var runnerUp = -Double.infinity
        for (key, score) in scores {
            let dx = key % (2 * searchRadius + 1) - searchRadius
            let dy = key / (2 * searchRadius + 1) - searchRadius
            if abs(dx - best.dx) <= 2 && abs(dy - best.dy) <= 2 { continue }
            runnerUp = max(runnerUp, score)
        }
        let mean = scoreSum / scoreCount
        // 봉우리가 평균 대비 뚜렷하지 않으면 결함 신호로 판정할 근거가 없다.
        guard mean > 0, best.score >= mean * 1.10 else { return nil }

        // probe 좌표(= raw 가 IR 대비 어디에 있는가)를 정합 오프셋으로 뒤집는다.
        // shiftPlane 은 out(x,y) = ir(x+dx, y+dy) 라, raw(X,Y) ↔ ir(X-best.dx, Y-best.dy) 이면
        // dx = -best.dx, dy = -best.dy 다.
        return DefectAlignment(
            offsetX: -best.dx,
            offsetY: -best.dy,
            peak: best.score,
            runnerUp: runnerUp.isFinite ? runnerUp : 0,
            pointCount: points.count,
            atSearchLimit: abs(best.dx) == searchRadius || abs(best.dy) == searchRadius
        )
    }
}
