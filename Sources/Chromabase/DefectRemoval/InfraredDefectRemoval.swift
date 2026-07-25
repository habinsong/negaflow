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
//   1) 정렬     — IR 패스는 별도 스캔이라 raw 와 수 픽셀 어긋날 수 있다. 염료의 IR 누설
//                 (주로 시안=red 채널과 상관)을 단서로 정수 오프셋을 추정해 IR 을 raw 격자에 맞춘다.
//   2) 장면 누설 보정 — log(red) 구간별 IR 절사 평균으로 비모수 곡선을 만들고, 구간 사이를
//                 보간해 RGB 장면 구조만 제거한다. 희소한 어두운 결함은 절사 표본에서 빠진다.
//   3) 다크 마진 제외 — 필름 홀더/리베이트는 IR 에서 통째로 어둡다. 테두리에 연결된 어두운
//                 영역을 flood-fill 로 제외해 홀더가 "결함"으로 잡히지 않게 한다.
//   4) 상대 대비 임계 — (국소평균 − 값) / 국소평균의 한쪽 고주파 잔차와 그 주변 평균을
//                 비교해 조명 밝기와 무관한 결함 후보를 뽑는다.
//   5) 컴포넌트/분류 — 연결요소 → PCA 주축으로 dust/scratch(H/V/대각) 분류, confidence 산출.
//   6) 클러스터   — 결함 픽셀을 (팽창 포함) 타일 클러스터 마스크(RGBA8, 흰=제거)로 렌더한다.
//                 복원은 기존 SoftwareDefectRemoval.repair(DefectScratchRepairer)가 담당한다 — 검출만 IR 로 바꾼다.
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
    public struct Cluster: Sendable, Equatable {
        public let roiYup: CGRect
        public let maskRGBA8: Data
        public let width: Int
        public let height: Int

        public init(roiYup: CGRect, maskRGBA8: Data, width: Int, height: Int) {
            self.roiYup = roiYup
            self.maskRGBA8 = maskRGBA8
            self.width = width
            self.height = height
        }
    }

    public struct Detection: Sendable {
        public let clusters: [Cluster]
        public let components: [Component]
        /// 유효(마진 제외) 면적 대비 결함 픽셀 비율.
        public let coverage: Double
        /// 적용된 IR→raw 정렬 오프셋(참고용).
        public let offsetX: Int
        public let offsetY: Int
        public let alignment: AlignmentDiagnostics
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
        guard alignment.isAccepted else {
            return .failure(.alignmentUnreliable(alignment))
        }
        if cancelled() { return .failure(.cancelled) }
        // IR 을 raw 격자로 이동(범위 밖은 제외 마킹).
        var excluded = [Bool](repeating: false, count: n)
        var ir = shiftPlane(infrared, width: width, height: height,
                            dx: alignment.offsetX, dy: alignment.offsetY, outOfBounds: &excluded)
        infrared = []   // 이후 미사용 — 조기 반납(55MP에서 4·N bytes)

        // 2) 다크 마진 제외: 테두리 연결 어두운 영역(홀더/리베이트) + 림 완충.
        //    반드시 스펙트럴 클린 **앞**에서 한다 — 홀더는 red 도 어두워 ln(red) 보정이
        //    마진을 되레 밝혀 마진 검출을 망가뜨린다.
        let r1 = max(4, min(24, min(width, height) / 200))
        let p95 = percentile(ir, excluded: excluded, q: 0.95)
        guard p95 > 1e-4 else { return .failure(.unreadable) }
        markBorderConnectedDark(ir, width: width, height: height,
                                threshold: p95 * 0.2, rim: r1, excluded: &excluded)
        if cancelled() { return .failure(.cancelled) }

        // 3) 장면 누설 보정: log(red) 구간별 절사 평균 곡선으로 RGB 구조만 제거한다.
        removeSceneLeakage(ir: &ir, red: red, excluded: excluded, n: n)
        red = []        // 이후 미사용 — 조기 반납
        if cancelled() { return .failure(.cancelled) }

        // 4) 상대 대비 임계: 한쪽 고주파 잔차를 국소 밝기로 나눠 비네팅/노출 변화에 둔감하게 한다.
        var dev = [Float](repeating: 0, count: n)
        do {
            let localMean = DefectMorphology.boxMean(ir, width: width, height: height, radius: r1)
            for i in 0..<n {
                dev[i] = max(0, localMean[i] - ir[i]) / max(localMean[i], 0.05)
            }
        }   // localMean 반납
        ir = []         // 이후 미사용 — 조기 반납
        if cancelled() { return .failure(.cancelled) }
        let contrastFloor: Float = 0.035
        let strongContrast: Float = 0.18
        // 큰 결함 자체가 주변 노이즈 추정치를 끌어올려 같은 결함의 어두운 쪽 픽셀을
        // 가리지 않도록, 노이즈 입력은 최소 검출 대비에서 자른다.
        var noiseInput = dev
        for i in 0..<n {
            noiseInput[i] = min(noiseInput[i], contrastFloor)
        }
        var noise = DefectMorphology.boxMean(
            noiseInput,
            width: width,
            height: height,
            radius: r1 * 2
        )
        noiseInput = []
        let k = Float(5.0 + 10.0 * (1.0 - min(max(parameters.sensitivity, 0), 1)))
        var mask = [Bool](repeating: false, count: n)
        var maskCount = 0
        var excludedCount = 0
        for i in 0..<n {
            if excluded[i] { excludedCount += 1; continue }
            let adaptiveThreshold = max(contrastFloor, k * noise[i])
            if dev[i] > strongContrast || dev[i] > adaptiveThreshold {
                mask[i] = true
                maskCount += 1
            }
        }
        noise = []
        excluded = []
        let validArea = max(1, n - excludedCount)
        let coverage = Double(maskCount) / Double(validArea)
        guard coverage <= parameters.maxCoverage else {
            return .failure(.coverageTooHigh(coverage))
        }
        if cancelled() { return .failure(.cancelled) }

        // 5) 연결요소 + 분류.
        let rawComponents = labelComponents(mask: mask, width: width, height: height,
                                            minArea: parameters.minArea)
        mask = []
        guard !rawComponents.isEmpty else { return .failure(.noDefects) }
        if cancelled() { return .failure(.cancelled) }
        var components: [Component] = []
        var defectPixels: [Int] = []
        defectPixels.reserveCapacity(maskCount)
        for comp in rawComponents {
            let filled = fillHoles(comp, width: width, height: height)
            defectPixels.append(contentsOf: filled)
            components.append(
                summarize(comp, pixels: filled, dev: dev, bCeil: strongContrast, width: width)
            )
        }
        dev = []

        // 6) 클러스터 마스크 렌더(팽창 포함).
        let clusters = renderClusters(defectPixels: defectPixels, width: width, height: height,
                                      dilate: parameters.dilateRadius,
                                      tile: parameters.clusterTile,
                                      padding: parameters.clusterPadding)
        return .success(Detection(clusters: clusters, components: components,
                                  coverage: coverage,
                                  offsetX: alignment.offsetX, offsetY: alignment.offsetY,
                                  alignment: alignment,
                                  width: width, height: height))
    }
}
