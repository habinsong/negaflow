import CoreGraphics
import CoreImage
import Foundation

// MARK: - RescueGrade (EXPIRED target)

/// EXPIRED is a conservative, evidence-gated correction rather than a fixed look.
///
/// The source image alone does not prove that reduced range, low contrast, grain, or a colour cast
/// was caused by expired film. Consequently this stage never stretches endpoints, adds a contrast
/// curve, or runs noise reduction. It applies only a bounded neutral-axis correction when the image
/// supplies repeatable neutral evidence across luminance and space. If that gate fails, the exact
/// input `CIImage` is returned.
public enum RescueGrade {
    static let minimumEligibleBandCount = 3
    static let minimumCoveredTileCount = 6
    /// 밴드가 앉은 자리로부터 이만큼 안쪽을 "중립이어야 할 것들" 로 본다. 원점에서의 거리가
    /// 아니라 **쏠린 자리에서의 거리**다 — 그래야 캐스트 크기와 무관해진다.
    static let maximumNeutralOffset = 18.0
    static let minimumNeutralPopulationFraction = 0.80
    static let maximumBandMAD = 3.0
    static let maximumHoldoutDelta = 2.0
    static let minimumMeasuredDrift = 1.5
    /// 되돌릴 수 있는 쏠림의 상한.
    ///
    /// 12 는 약한 캐스트만 염두에 둔 값이라 오래된 필름의 노란 쏠림에서는 절반도 못 폈다.
    /// 30 은 전역 캐스트가 물리적으로 닿을 수 있는 범위다 — 중성 면이 텅스텐과 주광 사이에서
    /// 움직이는 폭이 대략 이만큼이다. 그보다 크게 옮기면 캐스트를 걷는 것이 아니라 피사체의
    /// 색을 바꾸는 것이 된다.
    ///
    /// 이것은 **마지막 방어선**이다. 사진 전체가 진짜로 한 색인 경우(노란 벽 한 장) 앞의 증거
    /// 검사들이 그것을 캐스트로 볼 수 있는데, 그때 얼마나 망가질 수 있는지를 이 값이 묶는다.
    static let maximumDriftLab = 30.0
    static let bandEdges: [Double] = [0.06, 0.20, 0.34, 0.48, 0.62, 0.76, 0.92]

    struct Recovery: Equatable, Hashable, Sendable {
        var bins: [ScannerTargetGrade.NeutralBin]
        var eligibleBandCount: Int
        var coveredTileCount: Int
        var trainingSampleCount: Int
        var holdoutSampleCount: Int
        var maximumObservedMAD: Double
        var maximumObservedHoldoutDelta: Double
        var holdoutValidated: Bool

        var isEligible: Bool {
            holdoutValidated
                && eligibleBandCount >= minimumEligibleBandCount
                && bins.count >= minimumEligibleBandCount
                && coveredTileCount >= minimumCoveredTileCount
        }

        static let identity = Recovery(
            bins: [],
            eligibleBandCount: 0,
            coveredTileCount: 0,
            trainingSampleCount: 0,
            holdoutSampleCount: 0,
            maximumObservedMAD: 0,
            maximumObservedHoldoutDelta: 0,
            holdoutValidated: false
        )
    }

    private struct Sample {
        var x: Int
        var y: Int
        var luma: Double
        var a: Double
        var b: Double
        var chroma: Double
    }

    private struct SampleGrid {
        var width: Int
        var height: Int
        var samples: [Sample]
    }

    /// `recoverRange` is retained for source compatibility. Range recovery is intentionally no
    /// longer performed: without an external before/after reference, endpoint expansion cannot be
    /// distinguished from destroying legitimate scene range.
    public static func apply(
        to image: CIImage,
        sampleColorSpace: CGColorSpace,
        filmType: FilmType = .colorNegative,
        recoverRange: Bool = true
    ) -> CIImage {
        var recovery: Recovery?
        return apply(to: image, sampleColorSpace: sampleColorSpace,
                     filmType: filmType, recoverRange: recoverRange,
                     recovery: &recovery)
    }

    /// 이미 잰 복구 증거가 있으면 다시 재지 않는 변형(DevelopSceneMeasurements).
    static func apply(
        to image: CIImage,
        sampleColorSpace: CGColorSpace,
        filmType: FilmType = .colorNegative,
        recoverRange: Bool = true,
        recovery cachedRecovery: inout Recovery?
    ) -> CIImage {
        _ = recoverRange
        let alignChannels = filmType == .colorNegative || filmType == .colorPositive
        let recovery = cachedRecovery ?? measureRecovery(
            in: image,
            sampleColorSpace: sampleColorSpace,
            alignChannels: alignChannels
        )
        cachedRecovery = recovery
        // EXPIRED = 열화 필름 **복구** 타겟(창의적 aged 룩이 아니다). 측정된 중립축 캐스트 증거가
        // 있을 때만 bounded 보정을 적용하고, 건강한 필름은 그대로(no-op = MAIN)다 — 복구할
        // 열화가 없으므로 아무것도 굽지 않는 것이 올바른 동작이다.
        guard recovery.isEligible else { return image }
        return applyRelativeCorrection(to: image, recovery: recovery)
    }

    /// Measures neutral-axis evidence with a deterministic train/holdout split.
    ///
    /// A luminance band is accepted only when it contains a low-chroma population in multiple
    /// spatial tiles, its Lab a/b scatter is small, and an independent holdout subset agrees with
    /// the training median and becomes materially more neutral under that correction. At least
    /// three accepted luminance bands and six image tiles are required for the result to be usable.
    static func measureRecovery(
        in image: CIImage,
        sampleColorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!,
        alignChannels: Bool = true
    ) -> Recovery {
        guard alignChannels,
              let grid = sampleGrid(image, fallbackColorSpace: sampleColorSpace),
              grid.samples.count >= 512 else { return .identity }

        let minimumBandSamples = max(32, grid.samples.count / 320)
        var bins: [ScannerTargetGrade.NeutralBin] = []
        var acceptedTileIDs = Set<Int>()
        var trainingSampleCount = 0
        var holdoutSampleCount = 0
        var maximumObservedMAD = 0.0
        var maximumObservedHoldoutDelta = 0.0

        for band in 0..<(bandEdges.count - 1) {
            let lower = bandEdges[band]
            let upper = bandEdges[band + 1]
            let members = grid.samples.filter { $0.luma >= lower && $0.luma < upper }
            guard members.count >= minimumBandSamples else { continue }

            // 후보를 **원점에서의 거리**로 고르면 캐스트가 셀수록 아무도 못 들어온다. 노랗게
            // 쏠린 사진에서는 원래 회색이던 벽도 원점에서 멀어지기 때문이다 — 세게 쏠린 사진
            // 일수록 걷어낼 수 없게 되는 자기모순이고, 유통기한이 한참 지난 필름에서 EXPIRED
            // 가 아무 일도 하지 않던 까닭이다.
            //
            // 그래서 **밴드가 실제로 앉은 자리**를 먼저 찾고, 그 주변에 얼마나 뭉쳐 있는지를
            // 본다. 쏠린 거리와 무관해진다. 색이 있는 사진을 지켜 주는 것은 원점 상한이 아니라
            // 아래의 검사들이다 — 여러 밝기대가 같은 방향이어야 하고(부호 변화 ≤1), 흩어짐이
            // 작아야 하고(MAD), 떼어 둔 표본과 일치해야 한다. 노을은 그쪽에서 걸린다.
            let centerA = median(members.map(\.a))
            let centerB = median(members.map(\.b))
            func offset(_ sample: Sample) -> Double { hypot(sample.a - centerA, sample.b - centerB) }
            let sortedOffset = members.map(offset).sorted()
            let lowerQuartile = sortedOffset[sortedOffset.count / 4]
            let neutralCeiling = min(maximumNeutralOffset, max(5.0, lowerQuartile * 1.35))
            let neutral = members.filter { offset($0) <= neutralCeiling }
            guard neutral.count >= minimumBandSamples,
                  Double(neutral.count) / Double(members.count) >= minimumNeutralPopulationFraction else {
                continue
            }

            let training = neutral.filter { !isHoldout($0) }
            let holdout = neutral.filter(isHoldout)
            guard training.count >= minimumBandSamples * 3 / 4,
                  holdout.count >= max(8, minimumBandSamples / 6) else { continue }

            let trainingA = median(training.map(\.a))
            let trainingB = median(training.map(\.b))
            let driftMagnitude = hypot(trainingA, trainingB)
            guard driftMagnitude >= minimumMeasuredDrift else { continue }

            let madA = median(training.map { abs($0.a - trainingA) })
            let madB = median(training.map { abs($0.b - trainingB) })
            let bandMAD = max(madA, madB)
            guard bandMAD <= maximumBandMAD else { continue }

            let holdoutA = median(holdout.map(\.a))
            let holdoutB = median(holdout.map(\.b))
            let holdoutDelta = hypot(holdoutA - trainingA, holdoutB - trainingB)
            guard holdoutDelta <= maximumHoldoutDelta else { continue }

            let before = median(holdout.map(\.chroma))
            let after = median(holdout.map { hypot($0.a - trainingA, $0.b - trainingB) })
            guard after + 0.75 <= before, after <= before * 0.72 else { continue }

            let tileIDs = Set(neutral.map { tileID(for: $0, grid: grid) })
            guard tileIDs.count >= 2 else { continue }

            bins.append(ScannerTargetGrade.NeutralBin(
                luma: median(neutral.map(\.luma)),
                a: clamp(trainingA, -maximumDriftLab, maximumDriftLab),
                b: clamp(trainingB, -maximumDriftLab, maximumDriftLab)
            ))
            acceptedTileIDs.formUnion(tileIDs)
            trainingSampleCount += training.count
            holdoutSampleCount += holdout.count
            maximumObservedMAD = max(maximumObservedMAD, bandMAD)
            maximumObservedHoldoutDelta = max(maximumObservedHoldoutDelta, holdoutDelta)
        }

        bins.sort { $0.luma < $1.luma }
        let coherentAcrossLuminance = signChangeCount(bins.map(\.a)) <= 1
            && signChangeCount(bins.map(\.b)) <= 1
        let holdoutValidated = bins.count >= minimumEligibleBandCount
            && acceptedTileIDs.count >= minimumCoveredTileCount
            && holdoutSampleCount >= 24
            && coherentAcrossLuminance
        return Recovery(
            bins: holdoutValidated ? bins : [],
            eligibleBandCount: bins.count,
            coveredTileCount: acceptedTileIDs.count,
            trainingSampleCount: trainingSampleCount,
            holdoutSampleCount: holdoutSampleCount,
            maximumObservedMAD: maximumObservedMAD,
            maximumObservedHoldoutDelta: maximumObservedHoldoutDelta,
            holdoutValidated: holdoutValidated
        )
    }

    private static func isHoldout(_ sample: Sample) -> Bool {
        ((sample.x &* 31) &+ (sample.y &* 17)) % 5 == 0
    }

    private static func signChangeCount(_ values: [Double]) -> Int {
        let signs = values.compactMap { value -> Int? in
            guard abs(value) >= 0.75 else { return nil }
            return value < 0 ? -1 : 1
        }
        guard var previous = signs.first else { return 0 }
        var changes = 0
        for sign in signs.dropFirst() where sign != previous {
            changes += 1
            previous = sign
        }
        return changes
    }

    private static func tileID(for sample: Sample, grid: SampleGrid) -> Int {
        let tileX = min(3, sample.x * 4 / max(grid.width, 1))
        let tileY = min(2, sample.y * 3 / max(grid.height, 1))
        return tileY * 4 + tileX
    }

    private static func sampleGrid(
        _ image: CIImage,
        fallbackColorSpace: CGColorSpace
    ) -> SampleGrid? {
        let extent = image.extent.integral
        guard extent.width > 8, extent.height > 8 else { return nil }

        let width = 192
        let scale = Double(width) / Double(extent.width)
        let height = max(1, Int((Double(extent.height) * scale).rounded()))
        let normalized = image.transformed(by: CGAffineTransform(
            translationX: -extent.minX,
            y: -extent.minY
        ))
        let scaled = normalized.transformed(by: CGAffineTransform(
            scaleX: CGFloat(scale),
            y: CGFloat(scale)
        ))
        let extendedLinear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
            ?? CGColorSpace(name: CGColorSpace.linearSRGB)
            ?? fallbackColorSpace
        var bitmap = [Float](repeating: 0, count: width * height * 4)
        SamplingContextPool.context(workingColorSpace: extendedLinear).render(
            scaled,
            toBitmap: &bitmap,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: extendedLinear
        )

        var samples: [Sample] = []
        samples.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let linear = SIMD3(
                    Double(bitmap[offset]),
                    Double(bitmap[offset + 1]),
                    Double(bitmap[offset + 2])
                )
                guard linear.x.isFinite, linear.y.isFinite, linear.z.isFinite,
                      linear.min() > 0.01, linear.max() < 0.99 else { continue }
                let rgb = SIMD3(
                    ScannerTargetGrade.srgbEncode(linear.x),
                    ScannerTargetGrade.srgbEncode(linear.y),
                    ScannerTargetGrade.srgbEncode(linear.z)
                )
                let luma = 0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
                let lab = ScannerTargetGrade.srgbToLab(r: rgb.x, g: rgb.y, b: rgb.z)
                let chroma = hypot(lab.a, lab.b)
                samples.append(Sample(x: x, y: y, luma: luma, a: lab.a, b: lab.b, chroma: chroma))
            }
        }
        return SampleGrid(width: width, height: height, samples: samples)
    }

    static let cubeDimension = 64

    private static let cubeCacheLock = NSLock()
    private nonisolated(unsafe) static var cubeCache: [Recovery: Data] = [:]

    /// Applies only the measured neutral-axis delta. The existing bounded kernel restores the
    /// original sample whenever any input channel lies outside the measured [0,1] cube domain.
    static func applyRelativeCorrection(to image: CIImage, recovery: Recovery) -> CIImage {
        guard recovery.isEligible,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let kernel = ChromabaseMetalKernels.colorKernel(named: "boundedRelativeGrade") else {
            return image
        }
        let extent = image.extent
        let graded = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": cubeDimension,
            "inputCubeData": cubeData(recovery: recovery),
            "inputColorSpace": srgb,
        ]).cropped(to: extent)
        return kernel.apply(extent: extent, arguments: [image, graded])?
            .cropped(to: extent) ?? image
    }

    /// Retained as an internal compatibility shim for focused tests and callers in this target.
    static func applyToneAndCast(to image: CIImage, recovery: Recovery) -> CIImage {
        applyRelativeCorrection(to: image, recovery: recovery)
    }

    static func cubeData(recovery: Recovery) -> Data {
        cubeCacheLock.lock()
        if let cached = cubeCache[recovery] {
            cubeCacheLock.unlock()
            return cached
        }
        cubeCacheLock.unlock()
        let data = makeCubeData(recovery: recovery, dimension: cubeDimension)
        cubeCacheLock.lock()
        if cubeCache.count >= 8 { cubeCache.removeAll(keepingCapacity: true) }
        cubeCache[recovery] = data
        cubeCacheLock.unlock()
        return data
    }

    static func makeCubeData(recovery: Recovery, dimension: Int) -> Data {
        let bins = recovery.bins.sorted { $0.luma < $1.luma }
        var cube = [Float](repeating: 0, count: dimension * dimension * dimension * 4)

        for bi in 0..<dimension {
            let b0 = Double(bi) / Double(dimension - 1)
            for gi in 0..<dimension {
                let g0 = Double(gi) / Double(dimension - 1)
                for ri in 0..<dimension {
                    let r0 = Double(ri) / Double(dimension - 1)
                    var r = r0
                    var g = g0
                    var b = b0
                    if recovery.isEligible {
                        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                        var lab = ScannerTargetGrade.srgbToLab(r: r, g: g, b: b)
                        let drift = ScannerTargetGrade.neutralDrift(at: luma, bins: bins)
                        let endpointWeight = ScannerTargetGrade.smoothstep(0.04, 0.12, luma)
                            * (1.0 - ScannerTargetGrade.smoothstep(0.88, 0.96, luma))
                        lab.a -= clamp(drift.a, -maximumDriftLab, maximumDriftLab) * endpointWeight
                        lab.b -= clamp(drift.b, -maximumDriftLab, maximumDriftLab) * endpointWeight
                        (r, g, b) = ScannerTargetGrade.labToSRGB(l: lab.l, a: lab.a, b: lab.b)
                    }
                    let offset = ((bi * dimension + gi) * dimension + ri) * 4
                    cube[offset] = Float(clamp(r, 0.0, 1.0))
                    cube[offset + 1] = Float(clamp(g, 0.0, 1.0))
                    cube[offset + 2] = Float(clamp(b, 0.0, 1.0))
                    cube[offset + 3] = 1
                }
            }
        }
        return Data(bytes: cube, count: cube.count * MemoryLayout<Float>.size)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
