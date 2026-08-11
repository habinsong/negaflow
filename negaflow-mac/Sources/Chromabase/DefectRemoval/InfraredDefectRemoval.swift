import Foundation
import CoreGraphics
import CoreImage

// MARK: - InfraredDefectRemoval (하드웨어 IR 채널 기반 결함 검출)
//
// 원리(공개된 적외선 물리): 컬러 필름 염료는 적외선을 거의 통과시키고, 먼지·스크래치는
// 적외선을 가린다. 따라서 IR 채널에서 "주변보다 어두운" 픽셀이 물리 결함이다.
// 은염 흑백 필름은 은 입자가 IR도 차단하므로 이 방식이 성립하지 않는다(호출측에서 게이트).
//
// 파이프라인(외부 plugin이 제공한 정렬 전 IR plane을 처리하는 독자 Swift 구현):
//   1) 씨앗 정렬  — IR 패스는 별개의 캐리지 왕복이라 raw 와 몇 px 어긋난다. 결함 신호로 전역
//                 정수 오프셋을 잡는다. 이건 **국소 탐색의 출발점**일 뿐이고, 최종 위치는
//                 결함마다 따로 정한다(실측: 한 컷은 결함 87개 중 9%만 전역 이동에 맞았다).
//   2) 다크 마진 제외 — 필름 홀더/리베이트는 IR 에서 통째로 어둡다. 테두리에 연결된 어두운
//                 영역을 flood-fill 로 제외해 홀더가 "결함"으로 잡히지 않게 한다.
//   3) 국소 기준선 — closing 으로 결함만 메운 기준선을 만들고 광학 밀도 log(기준선/값)를 얻는다.
//                 장면 고스트(시안 염료의 근적외 흡수)는 결함보다 훨씬 넓어 기준선에 함께
//                 실려 사라진다 — 전역 회귀도, 필름별 상수도 필요 없다.
//   4) 후보 추출  — 문턱은 그 스캔 자신의 밀도 분포(중앙값과 사분위)에서 세운다. 픽셀 하나의
//                 유의성이 모자라도 **면적으로 채워지면** 후보다 — 옅고 넓은 먼지가 그렇다.
//   5) 가시광 확인 — 후보마다 사진에서 대응하는 어두운 자국을 국소로 찾아 정합을 맞추고,
//                 봉우리가 잡음 위로 솟는지 검정한다. 못 솟으면 **버린다**. 고스트·IR 잡음·
//                 정합 실패가 여기서 걸러진다. 동시에 가린 양(배율 k)을 그 결함에서 실측한다.
//   6) 보정      — 확인된 결함만, 잰 만큼 되돌린다(raw ÷ 투과율). 되돌릴 수 없을 만큼 완전히
//                 막힌 심만 기존 SoftwareDefectRemoval.repair 가 메운다.
public enum InfraredDefectRemoval {

    public struct Parameters: Sendable, Equatable {
        /// 검출 민감도 0..1 (0.5 기본). 높을수록 옅은 결함까지 잡는다(적응 임계 배수 k 를 낮춤).
        public var sensitivity: Double
        /// 마스크 팽창 반경(px). 결함 가장자리의 복원 경계까지 덮는다.
        public var dilateRadius: Int
        /// 이 픽셀 수 미만의 연결요소는 노이즈로 버린다.
        public var minArea: Int
        /// 결함 마스크가 유효 면적의 이 비율을 넘으면 적용을 포기한다(흑백 은염/코다크롬/정렬 실패 보호).
        public var maxCoverage: Double
        /// IR↔raw 정수 정렬 탐색 반경(px, 풀해상도 기준).
        public var alignmentSearchRadius: Int
        /// 클러스터 타일 한 변(px)과 복원 컨텍스트 패딩(px).
        public var clusterTile: Int
        public var clusterPadding: Int

        public init(sensitivity: Double = 0.5,
                    dilateRadius: Int = 1,
                    minArea: Int = 2,
                    maxCoverage: Double = 0.05,
                    alignmentSearchRadius: Int = 32,
                    clusterTile: Int = 768,
                    clusterPadding: Int = 40) {
            self.sensitivity = Self.clamped(sensitivity, lower: 0, upper: 1, fallback: 0.5)
            self.dilateRadius = max(dilateRadius, 0)
            self.minArea = max(minArea, 1)
            self.maxCoverage = Self.clamped(maxCoverage, lower: 0, upper: 1, fallback: 0.05)
            self.alignmentSearchRadius = max(alignmentSearchRadius, 0)
            self.clusterTile = max(clusterTile, 1)
            self.clusterPadding = max(clusterPadding, 0)
        }

        func sanitized(width: Int, height: Int) -> Parameters {
            var result = Parameters(
                sensitivity: sensitivity,
                dilateRadius: dilateRadius,
                minArea: minArea,
                maxCoverage: maxCoverage,
                alignmentSearchRadius: alignmentSearchRadius,
                clusterTile: clusterTile,
                clusterPadding: clusterPadding
            )
            let maxDimension = max(1, max(width, height))
            result.dilateRadius = min(result.dilateRadius, maxDimension)
            result.alignmentSearchRadius = min(result.alignmentSearchRadius, maxDimension)
            result.clusterTile = min(result.clusterTile, maxDimension)
            result.clusterPadding = min(result.clusterPadding, maxDimension)
            return result
        }

        private static func clamped(_ value: Double, lower: Double, upper: Double,
                                    fallback: Double) -> Double {
            guard value.isFinite else { return fallback }
            return min(max(value, lower), upper)
        }
    }

    /// 검출된 결함 하나(미리보기/요약용 요약 정보만 — 픽셀 전체는 클러스터 마스크에 있다).
    public struct Component: Sendable {
        public let classification: DefectClass
        public let confidence: Double
        public let area: Int
        /// raw 픽셀 좌표(y-down) 다운샘플 점 — 오버레이 표시용.
        public let previewPoints: [CGPoint]
    }

    /// 복원 단위. roiYup 은 raw CIImage(y-up) 픽셀 rect, 마스크는 클러스터 로컬 RGBA8(흰=제거).
    ///
    /// `attenuationR16` 은 같은 창의 **가시광 감쇠**(16bit, 65535 = 빛을 100% 잃음)다. 결함은
    /// 대부분 빛을 부분적으로만 가리므로, 그 부분은 도려내지 않고 가려진 만큼 되돌린다
    /// (raw ÷ (1 − 감쇠)). `maskRGBA8` 은 나눗셈으로 되돌릴 수 없을 만큼 완전히 막힌 심에만
    /// 켜지고, 그 자리만 기존 복원 코어가 메운다. 예전 기록에는 감쇠가 없어 nil 이다.
    public struct Cluster: Sendable, Equatable {
        public let roiYup: CGRect
        public let maskRGBA8: Data
        public let attenuationR16: Data?
        public let width: Int
        public let height: Int

        public init(roiYup: CGRect, maskRGBA8: Data, attenuationR16: Data? = nil,
                    width: Int, height: Int) {
            self.roiYup = roiYup
            self.maskRGBA8 = maskRGBA8
            self.attenuationR16 = attenuationR16
            self.width = width
            self.height = height
        }
    }

    public struct Detection: Sendable {
        public let clusters: [Cluster]
        public let components: [Component]
        /// 유효(마진 제외) 면적 대비 결함 픽셀 비율.
        public let coverage: Double
        /// 씨앗으로 쓴 전역 IR→raw 정렬 오프셋(참고용 — 최종 위치는 결함마다 다르다).
        public let offsetX: Int
        public let offsetY: Int
        public let alignment: AlignmentDiagnostics
        /// IR 이 제안한 후보 수와 그중 사진에서 확인돼 실제로 보정된 수. 진단·로그용.
        /// 둘의 차이가 크면 IR 패스가 본 스캔과 다른 것을 보고 있다는 뜻이다.
        public let candidateCount: Int
        public let confirmedCount: Int
        /// 확인된 결함들에서 실측한 배율(가시광 밀도 ÷ IR 밀도)의 중앙값.
        public let medianGain: Double
        public let width: Int
        public let height: Int
    }

    public enum Failure: Error, Equatable, Sendable {
        case unreadable            // 입력 로드/렌더 실패
        case tooSmall              // 이미지가 너무 작음
        case alignmentUnreliable(AlignmentDiagnostics)
        case coverageTooHigh(Double)  // 마스크 과대 — IR 불투과 필름/비정상 입력 의심
        case noDefects             // 결함 없음(성공적 무결과)
        case cancelled             // 호출측 취소 훅이 중단 요청
    }

    // MARK: - 코어 (순수 배열 — 합성 픽스처로 테스트)

    /// infrared/red: 0..1 linear 평면(y-down 행 순서), 둘 다 width×height.
    /// isCancelled 훅은 단계 경계에서만 확인한다 — 검출 산술에는 영향이 없다.
    public static func detect(infrared: [Float], red: [Float],
                              width: Int, height: Int,
                              parameters: Parameters = Parameters(),
                              isCancelled: (() -> Bool)? = nil) -> Result<Detection, Failure> {
        var infrared = infrared
        var red = red
        return detectConsumingPlanes(infrared: &infrared, red: &red,
                                     width: width, height: height,
                                     parameters: parameters, isCancelled: isCancelled)
    }

    /// 평면 소유권을 넘겨받는 구현 — 각 평면을 마지막 사용 직후 비워 풀해상도(55MP)에서 동시
    /// 상주 평면 수를 최소화한다. 호출자가 평면의 유일한 소유자일 때(CI 렌더 경로) 실제로
    /// 스토리지가 반납된다. 검출 산술은 기존과 비트 동일(InfraredDefectAnchorTests 가 보증).
    static func detectConsumingPlanes(infrared: inout [Float], red: inout [Float],
                                      width: Int, height: Int,
                                      parameters: Parameters,
                                      isCancelled: (() -> Bool)? = nil) -> Result<Detection, Failure> {
        let parameters = parameters.sanitized(width: width, height: height)
        let n = width * height
        guard width >= 64, height >= 64 else { return .failure(.tooSmall) }
        guard infrared.count == n, red.count == n else { return .failure(.unreadable) }
        func cancelled() -> Bool { isCancelled?() == true }

        // 1) 정렬: IR 누설 텍스처가 있으면 정수 오프셋 추정, 없으면 (0,0).
        let alignment = estimateAlignment(
            infrared: infrared,
            red: red,
            width: width,
            height: height,
            searchRadius: parameters.alignmentSearchRadius
        )
        // 전역 정합은 **조언**이지 관문이 아니다. 결함마다 사진에서 다시 맞추고 확인하므로,
        // 씨앗이 틀렸다고 검출을 통째로 포기할 이유가 없다 — 포기하면 정합이 조금 어긋난
        // 스캔에서 아무것도 못 지운다(실측: 실기 2400dpi 한 쌍이 통째로 버려졌다).
        // 씨앗을 못 믿을 때는 이동 없이 시작하고 국소 탐색 범위를 넓힌다.
        let seedTrusted = alignment.isAccepted
        let seedX = seedTrusted ? alignment.offsetX : 0
        let seedY = seedTrusted ? alignment.offsetY : 0
        if cancelled() { return .failure(.cancelled) }
        // IR 을 raw 격자로 이동(범위 밖은 제외 마킹).
        var excluded = [Bool](repeating: false, count: n)
        var ir = shiftPlane(infrared, width: width, height: height,
                            dx: seedX, dy: seedY, outOfBounds: &excluded)
        infrared = []   // 이후 미사용 — 조기 반납(55MP에서 4·N bytes)

        // 2) 다크 마진 제외: 테두리 연결 어두운 영역(홀더/리베이트) + 림 완충.
        //    프레임 검출이 홀더를 조금 물거나 컷 사이 베이스 여백을 포함하는 일이 실제로
        //    있어서(사용자 확인), 이 단계는 국소 기준선보다 **먼저** 해야 한다. 홀더 경계는
        //    closing 기준선에서 거대한 밀도 계단을 만든다.
        let rim = max(4, min(24, min(width, height) / 200))
        let p95 = percentile(ir, excluded: excluded, q: 0.95)
        guard p95 > 1e-4 else { return .failure(.unreadable) }
        markBorderConnectedDark(ir, width: width, height: height,
                                threshold: p95 * 0.2, rim: rim, excluded: &excluded)
        var excludedCount = 0
        for i in 0..<n where excluded[i] { excludedCount += 1 }
        if cancelled() { return .failure(.cancelled) }

        // 3~4) 국소 기준선 → 광학 밀도 → 후보.
        //
        // 반지름은 관측으로 키우지 않는다. 관측은 이 기준선 자신으로 재는 것이라, 구조요소보다
        // 큰 결함은 밀도가 축소돼 **작게 보이고** 그래서 반지름을 못 키운다(실측: 좁은쪽 반지름
        // 18px 먼지가 있는 컷에서도 관측 상위 분위는 4px 이었다). 순환 논리다. 대신 해상도에서
        // 곧바로 정한다 — 먼지의 물리 크기는 스캔 설정과 무관하다.
        let radius = baselineRadius(width: width, height: height)
        var density = [Float]()
        do {
            var baseline = localBaseline(ir, width: width, height: height, radius: radius)
            density = opticalDensity(plane: ir, baseline: baseline, count: n)
            baseline = []
        }
        let statistics = signalStatistics(density, excluded: excluded,
                                          sensitivity: parameters.sensitivity)
        // 문턱은 픽셀 하나의 유의성이지만, 결함의 증거는 **면적에 쌓인다**. 옅고 넓은 먼지는
        // 픽셀 문턱을 하나도 못 넘으면서 합치면 압도적으로 유의하다(실측: 좁은쪽 반지름
        // 5~17px 인데 보정량이 정확히 0 인 먼지가 컷마다 있었다 — 사용자가 "뚱뚱한 먼지가
        // 남는다"고 한 것이 이것이다). 그래서 절반 높이에서 성분을 모으고 같은 유의수준을
        // 면적에 맞게 적용한다: Σ(밀도 − 바닥) ≥ mσ·√면적. 면적 1 이면 원래 픽셀 문턱과 같다.
        var candidates: [RawComponent] = []
        do {
            let excess = statistics.threshold - statistics.floor      // = mσ
            var mask = [Bool](repeating: false, count: n)
            for i in 0..<n where !excluded[i] && density[i] >= statistics.floor + 0.5 * excess {
                mask[i] = true
            }
            let pool = labelComponents(mask: mask, width: width, height: height,
                                       minArea: parameters.minArea)
            mask = []
            candidates = pool.filter { component in
                var sum = 0.0
                for pixel in component.pixels { sum += Double(density[pixel] - statistics.floor) }
                return sum >= Double(excess) * Double(component.pixels.count).squareRoot()
            }
        }
        ir = []         // 이후 미사용 — 조기 반납
        if cancelled() { return .failure(.cancelled) }
        guard !candidates.isEmpty else { return .failure(.noDefects) }

        // 5) 가시광 확인. 사진 쪽 밀도도 같은 방식으로 만든다 — 두 평면을 같은 자로 재야
        //    배율 k 가 물리량이 된다.
        let visibleBaseline = localBaseline(red, width: width, height: height, radius: radius)
        var visible = opticalDensity(plane: red, baseline: visibleBaseline, count: n)
        red = []        // 이후 미사용 — 조기 반납
        // closing 기준선은 창 안의 최대값이라 사진의 결(그레인·질감)만으로도 밀도가 양수로
        // 뜬다(실측 중앙값 ≈ 0.02~0.07). 그 바닥을 빼야 배율 k 가 "결함이 가린 양"이 되고,
        // 잡음 분포가 0 을 중심으로 놓여 z 검정이 성립한다.
        let visibleFloor = signalStatistics(visible, excluded: excluded,
                                            sensitivity: parameters.sensitivity).floor
        for i in 0..<n { visible[i] -= visibleFloor }
        if cancelled() { return .failure(.cancelled) }

        // 국소 탐색 반경: 전역 씨앗이 맞았다면 잔차는 몇 px 다.
        //
        // **0 으로 줄이면 안 된다.** 탐색면이 한 점이면 "이 봉우리가 잡음보다 높은가"를 잴
        // 표본이 없어 유의성 검정이 통째로 무력화되고, 밝기만 얼추 맞으면 통과한다
        // (실측: 그 경로에서 먼지 2개짜리 합성 장면에 후보 3개가 확인됐다 — 하나는 오검출).
        // 정합이 완벽하다고 가정하더라도 잡음 대비 검정을 위해 최소한의 창은 필요하다.
        let skirtFloor = statistics.skirtFloor
        // 되돌릴 양은 **필름 자신의 바닥**에서 잰다. 3σ 선(skirtFloor)은 "이 픽셀이 결함인가"를
        // 가르는 결정선이지, 결함이 가린 양의 기준이 아니다. 그 선을 기준으로 재면 결함마다
        // 정확히 3σ 만큼 덜 되돌리게 되고, 배율 k 가 그 불일치를 흡수하느라 물리적으로
        // 불가능한 값으로 부푼다(실측: k 중앙값 1.3~2.2 → 바닥 기준으로 재면 1.0~1.6, 가림이
        // 파장에 평평하다는 기대값 ≈1 에 붙는다). 중심 제거율도 컷마다 3~7pp 올라갔고
        // 심각한 과보정(<-0.06) 개수는 그대로였다.
        let magnitudeFloor = statistics.floor

        // 합의 이동: 강한 후보 몇 개를 넓게 확인해 그 중앙값을 탐색 중심으로 삼는다.
        //
        // 누설 상관 기반 전역 정합은 실기에서 판별력이 없었다(최고점 0.000177 / 차점 0.000174).
        // 반면 "결함이 사진 어디에 있나"는 결함마다 뚜렷하고, 그 답들의 중앙값은 흔들리지 않는다
        // (실측: 정합이 맞는 컷에서 결함의 94~100% 가 합의값 ±1px 안). 넓은 창을 결함 전부에
        // 쓰면 우연 일치가 늘고 승자의 저주도 커지므로, 넓게 보는 것은 합의를 세울 때 한 번뿐이다.
        // 창이 최소 9×9 는 돼야 귀무(중앙값·MAD)를 잴 표본이 생긴다.
        let coarseSearch = max(4, min(20, parameters.alignmentSearchRadius))
        var consensusX = 0, consensusY = 0
        if !seedTrusted, coarseSearch > 4 {
            var votesX: [Int] = [], votesY: [Int] = []
            for component in candidates.sorted(by: { $0.pixels.count > $1.pixels.count }).prefix(64) {
                let pixels = component.pixels
                var weights = [Float](repeating: 0, count: pixels.count)
                for (index, pixel) in pixels.enumerated() {
                    weights[index] = max(0, density[pixel] - magnitudeFloor)
                }
                let extent = min(component.maxX - component.minX,
                                 component.maxY - component.minY) / 2 + 1
                guard let match = confirmDefect(
                    pixels: pixels, weights: weights, visible: visible,
                    width: width, height: height, search: coarseSearch + extent,
                    extent: extent,
                    minimumSignificance: Float(minimumSignificance)
                ) else { continue }
                votesX.append(match.offsetX)
                votesY.append(match.offsetY)
            }
            if votesX.count >= 8 {
                votesX.sort(); votesY.sort()
                consensusX = votesX[votesX.count / 2]
                consensusY = votesY[votesY.count / 2]
            }
            if cancelled() { return .failure(.cancelled) }
        }
        // 창은 "정합 잔차 + 결함의 좁은 쪽 반지름"을 모두 덮어야 한다. 결함별로 정한다.
        let residualSearch = max(4, min(8, parameters.alignmentSearchRadius))
        var attenuation = [Float](repeating: 0, count: n)
        var confirmed: [RawComponent] = []
        var matches: [(pixels: [Int], offsetX: Int, offsetY: Int, gain: Float)] = []
        var visited = [Bool](repeating: false, count: n)
        let coreCut: Float = 0.5
        for component in candidates {
            if cancelled() { return .failure(.cancelled) }
            let pixels = fillHoles(component, width: width, height: height)
            var weights = [Float](repeating: 0, count: pixels.count)
            for (index, pixel) in pixels.enumerated() {
                weights[index] = max(0, density[pixel] - magnitudeFloor)
            }
            let extent = min(component.maxX - component.minX,
                             component.maxY - component.minY) / 2 + 1
            guard let match = confirmDefect(
                pixels: pixels, weights: weights, visible: visible,
                width: width, height: height,
                search: min(radius + residualSearch, residualSearch + extent + 3),
                extent: extent,
                originX: consensusX, originY: consensusY,
                minimumSignificance: Float(minimumSignificance)
            ) else { continue }
            confirmed.append(component)
            matches.append((pixels, match.offsetX, match.offsetY, clampGain(match.gain)))
        }
        guard !confirmed.isEmpty else { return .failure(.noDefects) }

        // 같은 컷의 결함들은 같은 물리(같은 두 패스, 같은 초점차)를 겪는다. 그러니 배율이 유독
        // 튀는 결함은 물리가 다른 게 아니라 적합 잡음이다. 그 스캔 자신의 중앙값과 중앙절대편차로
        // 위쪽 이상치만 눌러 준다 — 상수를 박지 않고 스캔이 스스로 상한을 정한다.
        let sortedGains = matches.map(\.gain).sorted()
        let medianGain = sortedGains[sortedGains.count / 2]
        var deviations = sortedGains.map { abs($0 - medianGain) }
        deviations.sort()
        let gainCeiling = medianGain + 2 * deviations[deviations.count / 2]

        for (component, match) in zip(confirmed, matches) {
            if cancelled() { return .failure(.cancelled) }
            let gain = min(match.gain, gainCeiling)
            // 보정은 후보 픽셀만이 아니라 그 둘레의 옅은 자락까지 덮는다. 자락을 버리면
            // 심만 지워지고 자국이 남는다. 다만 상자를 통째로 칠하면 결함과 이어지지도 않은
            // 잡음 픽셀까지 밝히게 되므로, 후보에서 **이어진 것만** 3σ 선까지 따라간다
            // (이력 임계). 자락의 최대 범위는 구조요소가 정한다 — 그보다 넓은 신호는 애초에
            // 기준선에 흡수돼 밀도가 0 이다.
            let x0 = max(0, component.minX - radius), x1 = min(width - 1, component.maxX + radius)
            let y0 = max(0, component.minY - radius), y1 = min(height - 1, component.maxY + radius)
            var frontier = match.pixels
            for pixel in match.pixels { visited[pixel] = true }
            var reached = match.pixels
            while let pixel = frontier.popLast() {
                let x = pixel % width, y = pixel / width
                for (nextX, nextY) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                    guard nextX >= x0, nextX <= x1, nextY >= y0, nextY <= y1 else { continue }
                    let next = nextY * width + nextX
                    guard !visited[next], density[next] > skirtFloor else { continue }
                    visited[next] = true
                    frontier.append(next)
                    reached.append(next)
                }
            }
            for pixel in reached {
                visited[pixel] = false
                let value = density[pixel] - magnitudeFloor
                guard value > 0 else { continue }
                let targetX = pixel % width + match.offsetX
                let targetY = pixel / width + match.offsetY
                guard targetX >= 0, targetX < width, targetY >= 0, targetY < height else { continue }
                // 밀도 → 감쇠. exp 는 발산하지 않으므로 나눗셈이 폭주하지 않는다.
                let occlusion = min(0.98, 1 - exp(-gain * value))
                let target = targetY * width + targetX
                if occlusion > attenuation[target] { attenuation[target] = occlusion }
            }
        }
        density = []
        visited = []

        // 6) 커버리지 점검과 코어(되돌릴 수 없는 완전 폐색) 추출.
        let significantCut = max(Float(1 - exp(-Double(3 * statistics.sigma))), 0.002)
        var significant = 0
        var corePixels: [Int] = []
        for i in 0..<n {
            let value = attenuation[i]
            if value >= significantCut { significant += 1 }
            if value >= coreCut { corePixels.append(i) }
        }
        let validArea = max(1, n - excludedCount)
        let coverage = Double(significant) / Double(validArea)
        guard coverage <= parameters.maxCoverage else {
            return .failure(.coverageTooHigh(coverage))
        }
        if cancelled() { return .failure(.cancelled) }

        // 7) 성분 요약(표시용) — 확인된 것만 센다.
        var components: [Component] = []
        components.reserveCapacity(confirmed.count)
        for component in confirmed {
            components.append(
                summarize(component, pixels: component.pixels, dev: attenuation,
                          bCeil: coreCut, width: width)
            )
        }

        // 8) 클러스터: 감쇠 창(16bit)과 코어 마스크를 같은 타일에 담는다.
        let clusters = renderCorrectionClusters(
            attenuation: attenuation,
            corePixels: corePixels,
            threshold: significantCut,
            width: width, height: height,
            dilate: parameters.dilateRadius,
            tile: parameters.clusterTile,
            padding: parameters.clusterPadding
        )
        guard !clusters.isEmpty else { return .failure(.noDefects) }
        return .success(Detection(clusters: clusters, components: components,
                                  coverage: coverage,
                                  offsetX: seedX + consensusX, offsetY: seedY + consensusY,
                                  alignment: alignment,
                                  candidateCount: candidates.count,
                                  confirmedCount: confirmed.count,
                                  medianGain: Double(medianGain),
                                  width: width, height: height))
    }

    /// 가시광 대조에서 "봉우리가 잡음이 아니다"라고 판정하는 기준(σ). 필름·스캐너 상수가 아니라
    /// 통계적 유의수준이다 — 탐색면 표본이 수십~수백 개이므로 4σ 면 우연 일치가 사실상 없다.
    static let minimumSignificance = 4.0
}
