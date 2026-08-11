import Foundation

/// 2~3단계 — 슬롯(홀더가 필름을 보여주려고 뚫어 둔 세로 창) 중에서 **실제로 필름이 들어 있는**
/// 창만 골라낸다.
extension FlatbedFrameGridDetector {

    struct Slot {
        /// 질감이 살아 있는 실측 구간. 행 프로파일은 여기서 뽑는다.
        let measured: Range<Int>
        /// 규격 폭으로 맞춘 출력 구간. 컷의 좌우 경계는 실측 중심 + 규격 폭으로 정한다 —
        /// 필름 폭은 물리적으로 정해져 있고, 측정된 폭은 평평한 그림에서 좁게 잡힌다.
        let snapped: Range<Int>
    }

    /// 질감이 있는 열만 슬롯으로 인정한다. 빈 창·흰 바탕·홀더 마스크는 모두 균일하므로 여기서
    /// 걸러진다 — 밝기로는 셋을 구분할 수 없다([ColumnProfiles] 참고).
    static func slots(
        preview: Preview,
        profiles: ColumnProfiles,
        geometry: FrameGeometry
    ) -> [Slot] {
        guard let otsu = splitThreshold(of: profiles.detail) else { return [] }
        let expected = geometry.acrossPixelsX
        let background = quantile(profiles.detail, 0.1)
        // 홀더 가장자리나 먼지도 질감을 조금은 낸다(실측 4.7mm 폭). 규격 폭에 한참 못 미치는
        // 심지는 넓히지 않는다 — 넓히면 잡음이 슬롯 크기까지 자라 빈 창이 되살아난다.
        func cores(above level: Double) -> [Range<Int>] {
            runs(of: profiles.detail) { $0 > level }
                .filter { Double($0.count) >= expected * 0.4 }
        }
        // 판별분석 경계는 두 무리가 뚜렷할 때만 옳다. 여백이 최대 밀도로 검은 슬라이드처럼
        // 분포가 한쪽으로 몰리면 경계가 필름 무리 안쪽에 서서 슬롯이 조각난다. 그때는 홀더
        // 잡음 바닥을 기준으로 한 번 더 낮춰 본다 — 헛집은 슬롯은 뒤의 격자 판정이 걸러낸다.
        var threshold = otsu
        var found = cores(above: threshold)
        if found.isEmpty {
            threshold = max(background * 2.5, otsu * 0.3)
            found = cores(above: threshold)
        }
        guard !found.isEmpty else { return [] }
        let cores = found

        // 판별분석 경계는 질감이 강한 부분만 남긴다. 평평한 하늘이나 저노광부는 그 아래로
        // 떨어져 슬롯이 실제보다 좁아지므로(실측 20.6mm vs 실제 24mm), 낮은 문턱으로 넓힌다.
        //
        // 넓히기를 멈추는 자리는 **홀더의 잡음 바닥**이어야 한다. 판별분석 경계에 비례해서
        // 잡으면 잡음이 큰 스캔에서 바닥 아래로 내려가 슬롯이 화면 끝까지 자란다.
        var grown: [Range<Int>] = []
        for core in cores {
            let coreLevel = core.reduce(0.0) { $0 + profiles.detail[$1] } / Double(core.count)
            let floor = max(background * 2, coreLevel * 0.15)
            let limit = Int((expected * 1.45).rounded())
            var lower = core.lowerBound
            var upper = core.upperBound
            while lower > 0, upper - lower < limit, profiles.detail[lower - 1] >= floor {
                lower -= 1
            }
            while upper < preview.width, upper - lower < limit, profiles.detail[upper] >= floor {
                upper += 1
            }
            if let last = grown.last, lower <= last.upperBound {
                grown[grown.count - 1] = last.lowerBound..<max(last.upperBound, upper)
            } else {
                grown.append(lower..<upper)
            }
        }

        return grown.compactMap { range in
            // 스캔 영역에 걸려 잘린 슬롯은 본 스캔이 엉뚱한 데를 찍게 되므로 내보내지 않는다.
            // 사제 홀더가 스캔 영역보다 넓을 때 좌우 끝에서 실제로 일어난다.
            guard range.lowerBound > 0, range.upperBound < preview.width else { return nil }
            let width = Double(range.count)
            guard width >= expected * 0.7, width <= expected * 1.45 else { return nil }
            let center = Double(range.lowerBound + range.upperBound) / 2
            var lower = Int((center - expected / 2).rounded())
            var upper = lower + Int(expected.rounded())
            if lower < 0 { upper -= lower; lower = 0 }
            if upper > preview.width {
                lower -= upper - preview.width
                upper = preview.width
            }
            guard lower >= 0, upper > lower else { return nil }
            return Slot(measured: range, snapped: lower..<upper)
        }
    }

    /// 슬롯 **밖**(=홀더 마스크)에서 잰 세로 질감. 필름이 아닌 곳의 값이므로 스캐너·해상도가
    /// 만들어 내는 잡음 바닥 그 자체다.
    static func noiseFloor(profiles: ColumnProfiles, slots: [Slot], width: Int) -> Double {
        let outside = (0..<width)
            .filter { x in !slots.contains { $0.measured.contains(x) } }
            .map { profiles.detail[$0] }
        // 중앙값이 아니라 하위 사분위다. 슬롯 밖에는 홀더 마스크뿐 아니라 빛이 그대로 지나가는
        // 빈 창도 있고, 빈 창은 마스크보다 잡음이 크다. 가장 조용한 쪽이 바닥이다.
        return outside.isEmpty ? 0 : quantile(outside, 0.25)
    }

    /// 행마다 "여기에 필름이 있는가". 옆 홀더와 다른가(밝기) **또는** 그림이 있는가(질감)의
    /// 합이다. 밝기만 보면 슬라이드의 밀도 높은 컷이 홀더와 같은 값으로 눌려 스트립이 조각나고,
    /// 질감만 보면 여백과 평평한 컷이 빠져 구획이 컷마다 끊어진다.
    static func filmness(rows: RowProfiles, height: Int) -> [Double] {
        let difference = (0..<height).map { abs(rows.mean[$0] - rows.surround[$0]) }
        let brightnessScale = max(quantile(difference, 0.9), 1e-4)
        let detailScale = max(quantile(rows.detail, 0.9), 1e-5)
        return (0..<height).map { y in
            max(difference[y] / brightnessScale, rows.detail[y] / detailScale)
        }
    }

    /// 4단계 — 슬롯 안에서 필름이 실제로 놓인 세로 구간. 한 슬롯이 위아래로 나뉜 홀더도
    /// 있으므로 개수를 가정하지 않는다.
    static func filmBands(
        preview: Preview,
        slot: Slot,
        rows: RowProfiles,
        geometry: FrameGeometry
    ) -> [Range<Int>] {
        let filmness = filmness(rows: rows, height: preview.height)
        // 문턱은 정규화된 값에 대한 고정 비율이다. 여기에 판별분석을 걸면 안 된다 — 슬롯 안은
        // 거의 전부 필름이라 낮은 무리가 없어서 경계가 필름 한가운데에 선다.
        //
        // 넉넉하게 잡는다. 홀더는 정의상 0 근처라 새지 않고, 반대로 빡빡하게 잡으면 밀도 높은
        // 첫 컷이 구획 밖으로 밀려 통째로 누락된다(실측: 슬라이드 구획이 17mm 가 아니라 25.9mm
        // 에서 시작해 첫 컷을 잃었다).
        let candidates = runs(of: filmness) { $0 > 0.07 }
        // 컷 하나가 통째로 불투명하거나 평평해도 스트립은 이어져 있다. 그보다 넉넉히 잇는다.
        let merged = bridging(candidates, maximumGap: Int(geometry.alongPixelsY * 1.3))
        let minimumRows = Int(geometry.alongPixelsY * 0.55)
        return merged
            .filter { $0.count >= max(4, minimumRows) }
            .map { trimmed($0, rows: rows, geometry: geometry) }
            .filter { $0.count >= max(4, minimumRows) }
    }

    /// 구획 양끝에서 **결이 없는** 부분을 걷어낸다.
    ///
    /// 평판 스캔의 위아래 끝에는 필름과 무관한 밝은 띠가 남는다(실측: 4mm 주기 밴딩). 밝기만
    /// 보는 구획 판정은 그것을 필름으로 삼키고, 구획이 13mm 길어진 만큼 빗살이 잘못된 피치로
    /// 맞아 들어간다(실측에서 38.0mm 대신 37.2mm 가 뽑혀 컷이 뒤로 갈수록 밀렸다). 필름에는
    /// 그레인이 있고 그 띠에는 없으므로 질감으로 자른다.
    private static func trimmed(
        _ band: Range<Int>,
        rows: RowProfiles,
        geometry: FrameGeometry
    ) -> Range<Int> {
        let inside = band.map { rows.detail[$0] }
        let floor = median(inside) * 0.25
        guard floor > 0 else { return band }
        // 밀도 높은 첫 컷을 통째로 먹지 않도록 한 컷 길이까지만 자른다.
        let limit = Int(geometry.alongPixelsY)
        var lower = band.lowerBound
        var upper = band.upperBound
        while lower < upper, lower - band.lowerBound < limit, rows.detail[lower] < floor {
            lower += 1
        }
        while upper > lower, band.upperBound - upper < limit, rows.detail[upper - 1] < floor {
            upper -= 1
        }
        return lower..<upper
    }
}
