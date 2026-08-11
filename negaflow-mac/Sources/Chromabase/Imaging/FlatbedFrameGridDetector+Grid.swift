import Foundation

/// 5단계 — 구획 안에 프레임 격자를 세운다.
///
/// 여백을 **가설로 훑지 않고 잰다.** 예전에는 1.0~3.0mm 를 0.25mm 씩 대입해 보고 경계마다 행
/// 하나를 찍은 점수로 골랐다. 실측에서 같은 필름의 세 스트립이 37.0 / 37.5 / 38.0mm 로 제각각
/// 나왔고 첫 컷을 통째로 놓치는 스트립이 생겼다. 이제는
///   1. 여백 **폭 전체**를 적분하는 빗살을 (피치, 위상) 평면에서 직접 최적화하고,
///   2. 구획을 얼마나 덮는지를 함께 봐서 컷을 적게 잡는 쪽이 이기지 못하게 하고,
///   3. 경계마다 국소 보정을 걸어 필름 수축과 이송 오차를 흡수한다.
///
/// 여백을 가리는 홀더도 있다. 스트립을 끼우면 컷 사이가 마스크로 덮여 밝은 베이스 대신 검은
/// 리브가 보인다. 밝기의 부호를 미리 정하지 않고 양쪽을 다 재는 이유가 이것이다 — 마스크는
/// "어두운 여백"일 뿐이고, 경계의 에지 쌍은 오히려 더 또렷해진다.
extension FlatbedFrameGridDetector {

    /// 격자를 인정하는 최소 증거. 프로파일 자체의 상위 폭으로 나눈 무차원 값이다.
    static let gridEvidenceFloor = 0.15

    struct StripGrid {
        /// 구획 기준 여백 중심 위치(px). 오름차순.
        let boundaries: [Double]
        let pitch: Double
        let gapWidth: Double
        let contrast: Double
        let confidence: Double
    }

    /// 격자를 채점하는 데 쓰는 프로파일들.
    struct GapEvidence {
        /// 여백을 얼마나 닮았는지 — 좁은 극값이면서 가로로 균일한 정도.
        let plateau: [Double]
        /// 밝기의 세로 변화량. 컷 경계에는 반드시 단차가 있다.
        let edge: [Double]
        /// 행마다 가로로 얼마나 그림이 있는지. **컷 안에는 있고 여백에는 없다** — 이 대비가
        /// 격자를 고르는 1차 근거다. 밝기 부호(네거티브/슬라이드), 여백을 가리는 마스크,
        /// 홀더 색깔 어느 것에도 휘둘리지 않는 유일한 신호다.
        let content: [Double]
        private let prefix: [Double]
        private let contentPrefix: [Double]

        init(plateau: [Double], edge: [Double], content: [Double]) {
            self.plateau = plateau
            self.edge = edge
            self.content = content
            var prefix = [Double](repeating: 0, count: plateau.count + 1)
            for index in plateau.indices { prefix[index + 1] = prefix[index] + plateau[index] }
            self.prefix = prefix
            var contentPrefix = [Double](repeating: 0, count: content.count + 1)
            for index in content.indices {
                contentPrefix[index + 1] = contentPrefix[index] + content[index]
            }
            self.contentPrefix = contentPrefix
        }

        var count: Int { plateau.count }

        /// `from..<to` 구간의 그림 양. 구간이 프로파일 밖으로 나가면 겹치는 부분만 센다.
        func contentSum(from: Double, to: Double) -> (sum: Double, length: Double) {
            let lower = max(0, Int(from.rounded()))
            let upper = min(count, Int(to.rounded()))
            guard upper > lower else { return (0, 0) }
            return (contentPrefix[upper] - contentPrefix[lower], Double(upper - lower))
        }

        /// 여백 중심이 `center`, 폭이 `2*half` 라고 할 때의 점수.
        ///
        /// 평탄한 여백만 보면 네거티브의 맑은 암부가 여백과 구별되지 않는다(실측에서 그 때문에
        /// 격자가 컷 한가운데에 섰다). 여백은 **양쪽에 단차가 있는** 평탄면이므로, 두 에지의
        /// 기하평균을 함께 본다 — 한쪽이 미노광 컷이라 약해도 완전히 죽지는 않는다.
        func score(center: Double, half: Double) -> Double? {
            let lower = Int((center - half).rounded())
            let upper = Int((center + half).rounded())
            guard lower >= 0, upper <= count, upper > lower else { return nil }
            let flat = (prefix[upper] - prefix[lower]) / Double(upper - lower)
            let leading = edge[max(0, min(count - 1, lower))]
            let trailing = edge[max(0, min(count - 1, upper - 1))]
            return 0.5 * flat + 0.5 * (leading * trailing).squareRoot()
        }
    }

    /// 여백은 **좁다**(35mm 는 2mm). 밝기를 그대로 쓰면 20mm 짜리 하늘이 여백과 같은 점수를
    /// 받아 위상이 엉뚱한 데로 끌려간다. 그래서 여백 폭짜리 톱햇으로 "이웃 컷 안쪽보다 얼마나
    /// 튀는가"를 재서, 넓은 밝기 흐름은 빼고 여백 크기의 극값만 남긴다.
    static func gapEvidence(
        rows: RowProfiles,
        band: Range<Int>,
        geometry: FrameGeometry
    ) -> GapEvidence {
        let mean = Array(rows.mean[band])
        let count = mean.count
        guard count > 8 else {
            return GapEvidence(
                plateau: [Double](repeating: 0, count: count),
                edge: [Double](repeating: 0, count: count),
                content: [Double](repeating: 0, count: count)
            )
        }
        var prefix = [Double](repeating: 0, count: count + 1)
        for index in 0..<count { prefix[index + 1] = prefix[index] + mean[index] }
        func windowMean(_ center: Int, half: Int) -> Double? {
            let lower = center - half
            let upper = center + half + 1
            guard lower >= 0, upper <= count else { return nil }
            return (prefix[upper] - prefix[lower]) / Double(upper - lower)
        }

        let half = max(1, Int((geometry.gapMinPixelsY * 0.6).rounded()))
        let offset = half + max(2, Int(geometry.alongPixelsY * 0.12))
        var bright = [Double](repeating: 0, count: count)
        var dark = [Double](repeating: 0, count: count)
        for y in 0..<count {
            guard let center = windowMean(y, half: half) else { continue }
            let left = windowMean(y - offset, half: half)
            let right = windowMean(y + offset, half: half)
            let sides: Double
            switch (left, right) {
            case let (value?, other?): sides = (value + other) / 2
            case let (value?, nil): sides = value
            case let (nil, other?): sides = other
            case (nil, nil): continue
            }
            bright[y] = center - sides
            dark[y] = sides - center
        }

        // 그림이 있는 행은 여백이 아니다. 균일함을 곱해 결을 가진 극값을 눌러 둔다.
        let uniformity = robustNormalized(Array(rows.detail[band])).map { 1 - $0 }
        let brightScore = zip(robustNormalized(bright), uniformity).map(*)
        let darkScore = zip(robustNormalized(dark), uniformity).map(*)
        func peakedness(_ values: [Double]) -> Double {
            quantile(values, 0.95) - quantile(values, 0.5)
        }
        let chosen = peakedness(brightScore) >= peakedness(darkScore) ? brightScore : darkScore
        let smoothing = max(1, Int(geometry.gapMinPixelsY / 8))

        var edge = [Double](repeating: 0, count: count)
        let step = max(1, Int((geometry.gapMinPixelsY * 0.25).rounded()))
        for y in step..<(count - step) {
            edge[y] = abs(mean[y + step] - mean[y - step])
        }

        return GapEvidence(
            plateau: movingAverage(chosen, radius: smoothing),
            edge: robustNormalized(movingAverage(edge, radius: smoothing)),
            content: movingAverage(Array(rows.detail[band]), radius: smoothing)
        )
    }

    /// (피치, 위상) 평면 전체를 훑어 여백 빗살이 가장 잘 맞는 자리를 찾는다.
    ///
    /// 자기상관으로 피치만 먼저 재는 방법은 실측에서 40.9mm 같은 엉뚱한 주기에 물렸다 — 필름
    /// 내용에도 주기가 있기 때문이다. 우리가 원하는 값은 "여백에 가장 잘 얹히는 빗살"이므로
    /// 그것을 직접 최적화한다.
    static func fitGrid(
        evidence: GapEvidence,
        geometry: FrameGeometry
    ) -> StripGrid? {
        guard evidence.count > 8 else { return nil }
        let length = Double(evidence.count)
        let range = geometry.pitchRangePixelsY
        guard range.upperBound > range.lowerBound, range.lowerBound > 2 else { return nil }
        let pitchStep = max(0.05 * geometry.pixelsPerMillimeterY, 0.25)
        let phaseStep = max(0.35, geometry.gapMinPixelsY / 6)
        // 점수가 0 에 닿으면 기하평균이 통째로 0 이 된다. 미노광 컷 옆의 약한 경계 하나가
        // 격자를 통째로 버리게 두지 않으려고, 분포 하위에서 바닥을 가져온다.
        let nominalHalf = gapHalfWidth(
            pitch: (range.lowerBound + range.upperBound) / 2,
            geometry: geometry
        )
        let everywhere = (0..<evidence.count).compactMap {
            evidence.score(center: Double($0), half: nominalHalf)
        }
        guard !everywhere.isEmpty else { return nil }
        let floor = max(quantile(everywhere, 0.10), 1e-4)

        var best: (score: Double, pitch: Double, phase: Double, separation: Double)?
        var pitch = range.lowerBound
        while pitch <= range.upperBound {
            let half = gapHalfWidth(pitch: pitch, geometry: geometry)
            // 이 피치로 구획에 들어갈 수 있는 컷 수. 마지막 컷은 뒤쪽 여백이 필요 없으므로
            // 길이를 피치로 그냥 나누면 한 컷을 잃고, 그만큼 작은 피치에 커버리지 보너스가
            // 붙어 격자가 짧은 주기로 끌려간다(실측에서 피치가 탐색 하한에 붙었다).
            let frames = max(1, Int(((length - geometry.alongPixelsY) / pitch).rounded(.down)) + 1)
            let coverage = min(1, geometry.alongPixelsY * Double(frames) / length)
            var phase = 0.0
            while phase < pitch {
                // 1차 근거: **컷 안의 그림 양 − 여백의 그림 양.** 여백 밝기만 보면 네거티브의
                // 맑은 암부가 여백 행세를 하고(실측에서 격자가 컷 한가운데에 섰다), 슬라이드는
                // 부호가 뒤집히고, 마스크 홀더는 아예 밝기가 반대다. "그림이 있느냐"는 그 셋을
                // 전부 통과한다.
                var gapSum = 0.0
                var gapLength = 0.0
                var frameSum = 0.0
                var frameLength = 0.0
                var plateauLog = 0.0
                var boundaries = 0
                var index = 0
                while true {
                    let center = phase + pitch * Double(index)
                    if center > length { break }
                    let gap = evidence.contentSum(from: center - half, to: center + half)
                    gapSum += gap.sum
                    gapLength += gap.length
                    plateauLog += Foundation.log(
                        max(evidence.score(center: center, half: half) ?? floor, floor)
                    )
                    boundaries += 1
                    // 경계 사이가 컷이다. 경계에 붙은 부분은 흐릿하므로 여백 폭만큼 물러난다.
                    let interior = evidence.contentSum(
                        from: center + half * 2,
                        to: center + pitch - half * 2
                    )
                    frameSum += interior.sum
                    frameLength += interior.length
                    index += 1
                }
                guard boundaries >= 2, gapLength > 0, frameLength > 0 else {
                    phase += phaseStep
                    continue
                }
                let gapMean = gapSum / gapLength
                let frameMean = frameSum / frameLength
                let separation = (frameMean - gapMean) / (frameMean + gapMean + 1e-9)
                // 2차 근거: 여백다움(평탄한 극값 + 양쪽 단차). 기하평균이라 경계 하나라도
                // 빗나가면 크게 깎인다 — 우연히 두어 개만 맞은 격자가 이기지 못한다.
                let plateau = Foundation.exp(plateauLog / Double(boundaries))
                let score = (separation * 0.75 + plateau * 0.25) * coverage
                if best == nil || score > best!.score {
                    best = (score, pitch, phase, separation)
                }
                phase += phaseStep
            }
            pitch += pitchStep
        }
        // 주기성의 증거가 없으면 격자를 세우지 않는다. 빈 창은 그림이 없어 컷과 여백의 대비가
        // 0 에 붙으므로 여기서 떨어진다 — 예전에는 점수 하한이 없어 첫 후보가 그대로 당선됐고,
        // 필름을 한 슬롯만 끼운 홀더에서 빈 창 두 개에 격자를 세웠다.
        //
        // 대비는 (컷 − 여백)/(컷 + 여백) 이라 필름 종류·스캐너·홀더가 달라도 같은 자다.
        let contrast = best?.separation ?? 0
        guard let fit = best, contrast >= gridEvidenceFloor else { return nil }
        let half = gapHalfWidth(pitch: fit.pitch, geometry: geometry)

        // 경계마다 국소 보정한 **뒤 다시 등간격으로 맞춘다.** 보정값을 그대로 쓰면 컷마다
        // ±1mm 씩 따로 움직여 같은 스트립의 피치가 37.5~38.7mm 로 흔들렸다(같은 필름을 두 번
        // 스캔하면 결과가 달라지는 원인). 필름의 컷은 등간격이므로, 보정된 자리들에 직선을
        // 맞춰 전체 수축과 위상만 흡수하고 개별 흔들림은 버린다.
        let searchRadius = max(1.0, half * 0.9)
        var samples: [(index: Double, position: Double)] = []
        var index = 0
        while true {
            let center = fit.phase + fit.pitch * Double(index)
            if center - half > length { break }
            samples.append((
                Double(index),
                refined(center, evidence: evidence, radius: searchRadius, half: half)
            ))
            index += 1
        }
        guard samples.count >= 2, let line = fitLine(samples) else { return nil }
        // 한 경계가 크게 튀면(미노광 컷, 마스크 자국) 직선을 끌어당긴다. 한 번 걷어내고 다시 맞춘다.
        let tolerance = max(half * 0.6, 1)
        let kept = samples.filter { abs($0.position - (line.intercept + line.slope * $0.index)) <= tolerance }
        let refit = kept.count >= max(2, samples.count / 2) ? (fitLine(kept) ?? line) : line
        let spacing = refit.slope > 1 ? refit.slope : fit.pitch

        // 첫 컷과 끝 컷의 바깥쪽 여백은 구획 밖에 있어 잴 수 없다. 가상 경계를 양끝에 세워
        // 두고, 그 컷을 실제로 내보낼지는 구획과 얼마나 겹치는지가 정한다.
        let boundaries = (-1...(samples.count)).map {
            refit.intercept + spacing * Double($0)
        }

        return StripGrid(
            boundaries: boundaries,
            pitch: spacing,
            gapWidth: half * 2,
            contrast: contrast,
            confidence: min(1, 0.5 + contrast * 0.5)
        )
    }

    private static func fitLine(
        _ samples: [(index: Double, position: Double)]
    ) -> (intercept: Double, slope: Double)? {
        guard samples.count >= 2 else { return nil }
        let count = Double(samples.count)
        let meanIndex = samples.reduce(0.0) { $0 + $1.index } / count
        let meanPosition = samples.reduce(0.0) { $0 + $1.position } / count
        var numerator = 0.0
        var denominator = 0.0
        for sample in samples {
            let delta = sample.index - meanIndex
            numerator += delta * (sample.position - meanPosition)
            denominator += delta * delta
        }
        guard denominator > 1e-9 else { return nil }
        let slope = numerator / denominator
        return (meanPosition - slope * meanIndex, slope)
    }

    private static func gapHalfWidth(pitch: Double, geometry: FrameGeometry) -> Double {
        let width = min(
            max(pitch - geometry.alongPixelsY, geometry.gapMinPixelsY),
            geometry.gapMaxPixelsY
        )
        return max(1, width / 2)
    }

    private static func refined(
        _ center: Double,
        evidence: GapEvidence,
        radius: Double,
        half: Double
    ) -> Double {
        var best = (position: center, value: -Double.infinity)
        var offset = -radius
        while offset <= radius {
            let position = center + offset
            if let value = evidence.score(center: position, half: half), value > best.value {
                best = (position, value)
            }
            offset += 0.5
        }
        return best.value.isFinite ? best.position : center
    }
}
