import Foundation

/// 검출이 쓰는 1차원 프로파일과 그 위의 공통 연산.
///
/// **밝기는 필름을 가려내는 기준이 될 수 없다.** 실측(GT-X900):
///   - 정품 홀더 3슬롯 전부 채운 컷: 홀더 0.002, 필름 0.12 — 필름이 더 밝다.
///   - 한 슬롯만 채운 컷: 빈 창 0.92, 필름 0.10 — **빈 창이 필름보다 9배 밝다.**
///   - 사제 홀더: 바탕 자체가 1.00(흰색) — 극성이 통째로 뒤집힌다.
/// 밝기로 가르면 앞의 두 경우에서 빈 창을 필름으로 집고 진짜 필름을 버린다.
///
/// 반면 **질감은 필름에만 있다.** 그레인과 그림이 만드는 세로 방향 |ΔI| 평균은 같은 실측에서
/// 필름 열 0.0044~0.032, 홀더·빈 창·흰 바탕 열 0.00005~0.001 로 한 자릿수 이상 벌어졌고,
/// 필름 종류·홀더 종류·극성이 무엇이든 부호가 뒤집히지 않았다.
extension FlatbedFrameGridDetector {

    /// 이미지 전체에 대한 열 방향 요약.
    struct ColumnProfiles {
        /// 열마다 세로 방향 |ΔI| 평균. 필름이 있는 열에서만 살아난다.
        let detail: [Double]
        /// 열 평균 밝기.
        let mean: [Double]

        init(preview: Preview) {
            let width = preview.width
            let height = preview.height
            var detail = [Double](repeating: 0, count: width)
            var mean = [Double](repeating: 0, count: width)
            preview.luminance.withUnsafeBufferPointer { pixels in
                for y in 0..<height {
                    let rowStart = y * width
                    let nextStart = rowStart + width
                    let hasNextRow = y + 1 < height
                    for x in 0..<width {
                        let value = pixels[rowStart + x]
                        mean[x] += value
                        if hasNextRow {
                            detail[x] += abs(pixels[nextStart + x] - value)
                        }
                    }
                }
            }
            let rows = Double(height)
            let steps = Double(max(1, height - 1))
            for x in 0..<width {
                mean[x] /= rows
                detail[x] /= steps
            }
            self.detail = detail
            self.mean = mean
        }
    }

    /// 슬롯 하나를 세로로 훑은 행 방향 요약. 슬롯 가장자리는 홀더 그림자가 섞이므로 안쪽만 본다.
    struct RowProfiles {
        /// 행 평균 밝기.
        let mean: [Double]
        /// 행마다 가로 방향 |ΔI| 평균. 프레임 사이 여백은 균일해서 여기서 골이 된다.
        let detail: [Double]
        /// 행마다 세로 방향 |ΔI| 평균 = 그레인.
        ///
        /// 필름에만 있다. 가로 방향 질감([detail])은 홀더의 곡선 경계에도 반응하지만(실측:
        /// 사제 홀더 상단의 둥근 마스크가 행마다 다른 x 에서 흑백을 가르는 바람에, 필름이 없는
        /// 자리에 컷이 하나 헛나갔다) 세로 방향은 평평한 면에서 정확히 0 이다.
        let grain: [Double]
        /// **같은 행에서** 슬롯 바로 옆(홀더 쪽) 밝기.
        ///
        /// 필름이 있는지는 절대 밝기로 못 가른다. 사제 홀더는 흰 바탕(1.00)과 검은 플라스틱이
        /// 섞여 있어 "홀더는 이 값"이라는 기준 하나가 서지 않는다(실측에서 필름이 없는 위쪽
        /// 영역에 컷이 하나 헛나갔다). 필름은 옆의 홀더와 **다르고**, 필름이 없는 자리는 옆과
        /// 같다 — 행마다 옆을 보면 기준값이 필요 없다.
        let surround: [Double]

        init(preview: Preview, slot: Range<Int>) {
            let inset = max(1, slot.count / 10)
            let inner = (slot.lowerBound + inset)..<max(slot.lowerBound + inset + 1, slot.upperBound - inset)
            let width = preview.width
            var mean = [Double](repeating: 0, count: preview.height)
            var detail = [Double](repeating: 0, count: preview.height)
            var grain = [Double](repeating: 0, count: preview.height)
            preview.luminance.withUnsafeBufferPointer { pixels in
                for y in 0..<preview.height {
                    let rowStart = y * width
                    let nextStart = rowStart + width
                    let hasNextRow = y + 1 < preview.height
                    var sum = 0.0
                    var vertical = 0.0
                    var steps = 0.0
                    var previous = pixels[rowStart + inner.lowerBound]
                    for x in inner {
                        let value = pixels[rowStart + x]
                        mean[y] += value
                        sum += abs(value - previous)
                        previous = value
                        steps += 1
                        if hasNextRow { vertical += abs(pixels[nextStart + x] - value) }
                    }
                    mean[y] /= Double(inner.count)
                    detail[y] = sum / max(1, steps - 1)
                    grain[y] = vertical / Double(inner.count)
                }
            }
            self.mean = mean
            self.detail = detail
            self.grain = grain
            self.surround = Self.surroundMeans(preview: preview, slot: slot, fallback: mean)
        }

        /// 슬롯 양옆에서 **결이 덜한 쪽**을 홀더로 본다. 옆이 또 다른 필름 슬롯일 수 있으므로
        /// 두 쪽을 섞지 않고 조용한 쪽 하나만 쓴다.
        private static func surroundMeans(
            preview: Preview,
            slot: Range<Int>,
            fallback: [Double]
        ) -> [Double] {
            let guardWidth = max(2, slot.count / 6)
            let sample = max(3, slot.count / 2)
            let left = (slot.lowerBound - guardWidth - sample)..<(slot.lowerBound - guardWidth)
            let right = (slot.upperBound + guardWidth)..<(slot.upperBound + guardWidth + sample)
            let sides = [left, right].filter { $0.lowerBound >= 0 && $0.upperBound <= preview.width }
            guard !sides.isEmpty else { return fallback }

            func profile(_ range: Range<Int>) -> (mean: [Double], texture: Double) {
                var mean = [Double](repeating: 0, count: preview.height)
                var texture = 0.0
                for y in 0..<preview.height {
                    let rowStart = y * preview.width
                    var sum = 0.0
                    var previous = preview.luminance[rowStart + range.lowerBound]
                    for x in range {
                        let value = preview.luminance[rowStart + x]
                        sum += value
                        texture += abs(value - previous)
                        previous = value
                    }
                    mean[y] = sum / Double(range.count)
                }
                return (mean, texture / Double(preview.height * range.count))
            }

            return sides.map(profile).min { $0.texture < $1.texture }.map(\.mean) ?? fallback
        }
    }

    // MARK: - 공통 연산

    /// 1차원 프로파일을 두 무리로 가르는 값(판별분석). **픽셀 히스토그램에 쓰면 안 된다** —
    /// 홀더가 화면의 절반을 넘고 밀도 높은 컷은 8-bit 에서 0 으로 잘려서, 경계가 두 무리
    /// 사이가 아니라 필름 분포 한가운데에 선다(실측 0.28~0.50).
    static func splitThreshold(of profile: [Double]) -> Double? {
        guard let low = profile.min(), let high = profile.max(), high - low > 1e-6 else {
            return nil
        }
        let binCount = 128
        var histogram = [Int](repeating: 0, count: binCount)
        for value in profile {
            let bin = Int((value - low) / (high - low) * Double(binCount - 1))
            histogram[min(binCount - 1, max(0, bin))] += 1
        }
        let total = profile.count
        let sum = histogram.enumerated().reduce(0.0) { $0 + Double($1.offset * $1.element) }
        var backgroundSum = 0.0
        var backgroundCount = 0
        var best = (variance: -1.0, bin: 0)
        for bin in 0..<binCount {
            backgroundCount += histogram[bin]
            if backgroundCount == 0 { continue }
            let foregroundCount = total - backgroundCount
            if foregroundCount == 0 { break }
            backgroundSum += Double(bin * histogram[bin])
            let backgroundMean = backgroundSum / Double(backgroundCount)
            let foregroundMean = (sum - backgroundSum) / Double(foregroundCount)
            let delta = backgroundMean - foregroundMean
            let variance = Double(backgroundCount) * Double(foregroundCount) * delta * delta
            if variance > best.variance { best = (variance, bin) }
        }
        // 고른 bin 까지가 낮은 무리다. bin 경계를 그대로 쓰면 그 bin 에 속한 값이 간발로 살아남는다.
        return low + (Double(best.bin) + 0.5) / Double(binCount) * (high - low)
    }

    static func runs(
        of profile: [Double],
        matching isIncluded: (Double) -> Bool
    ) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start: Int?
        for (index, value) in profile.enumerated() {
            if isIncluded(value), start == nil { start = index }
            if !isIncluded(value), let begin = start {
                result.append(begin..<index)
                start = nil
            }
        }
        if let begin = start { result.append(begin..<profile.count) }
        return result
    }

    /// 사이가 `maximumGap` 이하로 붙은 구간을 하나로 잇는다.
    static func bridging(_ ranges: [Range<Int>], maximumGap: Int) -> [Range<Int>] {
        guard maximumGap > 0, var current = ranges.first else { return ranges }
        var result: [Range<Int>] = []
        for range in ranges.dropFirst() {
            if range.lowerBound - current.upperBound <= maximumGap {
                current = current.lowerBound..<range.upperBound
            } else {
                result.append(current)
                current = range
            }
        }
        result.append(current)
        return result
    }

    /// 폭이 사실상 0인 신호는 정규화하지 않는다. 그대로 늘리면 부동소수 오차가 만점과
    /// 0점으로 갈라져 없는 구조를 만들어 낸다.
    static func normalized(_ values: [Double]) -> [Double] {
        guard let low = values.min(), let high = values.max(), high - low > 1e-9 else {
            return [Double](repeating: 0, count: values.count)
        }
        return values.map { ($0 - low) / (high - low) }
    }

    /// 이상치에 흔들리지 않는 0...1 정규화. min/max 로 늘이면 먼지 한 점이 최대값을 잡아
    /// 나머지를 전부 바닥으로 눌러 버린다.
    static func robustNormalized(_ values: [Double]) -> [Double] {
        let low = quantile(values, 0.02)
        let high = quantile(values, 0.98)
        guard high - low > 1e-9 else { return [Double](repeating: 0, count: values.count) }
        return values.map { min(max(($0 - low) / (high - low), 0), 1) }
    }

    static func quantile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * min(max(fraction, 0), 1)).rounded())
        return sorted[index]
    }
}
