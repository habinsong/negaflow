import Foundation

/// 상주 프레임 수 ↔ 메모리 예산 환산.
///
/// 한도는 "미리 잡아 두는 양"이 아니라 **상한**이다. 실제로 방문한 프레임만 버퍼를 갖고, 한도를
/// 넘으면 오래된 것부터 내려놓는다. 그래서 한도를 높인다고 곧바로 그만큼 쓰는 것은 아니지만,
/// 최악의 경우 상주량은 한도에 비례하므로 설치 메모리 기준으로 예산을 잡는다.
enum FrameCacheBudget {
    /// 프레임당 상주 추정치(MB). 24MP 원본 + 긴 변 3600px 현상 기준의 실무 근사값이다.
    ///  - cleaned raw: 원본 해상도 16bit RGBA 한 장(6000×4000 ≈ 183MB).
    ///  - developed: 현상본 + 변형-전 base + 정착 프록시 raw 등 파생 버퍼 합계.
    static let cleanedRawMegabytesPerFrame = 190.0
    static let developedMegabytesPerFrame = 170.0

    /// 자동 예산 비율은 설치 메모리에 따라 완만하게 오른다. 메모리가 작을수록 OS·다른 앱·현상
    /// 파이프라인의 일시 버퍼가 차지하는 비중이 커서, 같은 비율이라도 실제 여유가 훨씬 적다.
    /// 16GB에서 25%, 16GB 늘 때마다 2.5%p 올라 96GB 이상에서 35%로 멈춘다.
    static let automaticMinimumFraction = 0.25
    static let automaticMaximumFraction = 0.35
    private static let automaticFractionReferenceGigabytes = 16.0
    private static let automaticFractionStepGigabytes = 16.0
    private static let automaticFractionStep = 0.025
    /// 수동 모드에서 허용하는 상한 비율.
    static let manualMemoryFraction = 0.70

    /// 이 머신에 적용되는 자동 예산 비율.
    static func automaticMemoryFraction(physicalMemoryBytes: UInt64) -> Double {
        let gigabytes = Double(physicalMemoryBytes) / (1_024 * 1_024 * 1_024)
        let steps = (gigabytes - automaticFractionReferenceGigabytes) / automaticFractionStepGigabytes
        return min(
            automaticMaximumFraction,
            max(automaticMinimumFraction, automaticMinimumFraction + steps * automaticFractionStep)
        )
    }

    /// 어떤 설정에서도 내려가지 않는 최소 한도.
    static let minimumCleanedRaw = 2
    static let minimumDeveloped = 3
    /// 실용 상한. 한 세션에 이보다 많은 프레임을 되짚어 오갈 일은 사실상 없어 더 늘려도 효과가 없다.
    static let maximumCleanedRaw = 64
    static let maximumDeveloped = 128

    /// developed 는 cleaned raw 보다 자주 오가므로 자동 배분에서 두 배를 준다.
    static let developedPerCleanedRaw = 2

    /// 8GB 이하는 OS·앱 기본 사용량을 빼면 여유가 거의 없어 기존 보수값을 유지한다.
    static let conservativeMemoryCeilingBytes: UInt64 = 8 * 1_024 * 1_024 * 1_024

    static var physicalMemoryBytes: UInt64 { ProcessInfo.processInfo.physicalMemory }

    static func megabytes(_ bytes: UInt64) -> Double {
        Double(bytes) / (1_024 * 1_024)
    }

    /// 한도 한 "단위"(cleaned raw 1 + developed 2)의 메모리 비용(MB).
    private static var unitMegabytes: Double {
        cleanedRawMegabytesPerFrame + Double(developedPerCleanedRaw) * developedMegabytesPerFrame
    }

    /// 설치 메모리에 맞춘 자동 한도.
    static func automaticLimits(physicalMemoryBytes: UInt64) -> FrameCacheLimits {
        guard physicalMemoryBytes > conservativeMemoryCeilingBytes else {
            return FrameCacheLimits(cleanedRaw: minimumCleanedRaw, developed: minimumDeveloped)
        }
        return limits(
            forBudgetMegabytes: megabytes(physicalMemoryBytes)
                * automaticMemoryFraction(physicalMemoryBytes: physicalMemoryBytes)
        )
    }

    /// 수동 모드 슬라이더의 상한(설치 메모리의 manualMemoryFraction).
    static func manualMaximumLimits(physicalMemoryBytes: UInt64) -> FrameCacheLimits {
        let budgeted = limits(
            forBudgetMegabytes: megabytes(physicalMemoryBytes) * manualMemoryFraction
        )
        // 자동값보다 낮은 상한은 의미가 없다(자동 → 수동 전환 시 값이 잘리는 것을 막는다).
        let automatic = automaticLimits(physicalMemoryBytes: physicalMemoryBytes)
        return FrameCacheLimits(
            cleanedRaw: max(budgeted.cleanedRaw, automatic.cleanedRaw),
            developed: max(budgeted.developed, automatic.developed)
        )
    }

    private static func limits(forBudgetMegabytes budget: Double) -> FrameCacheLimits {
        let units = max(1, Int((budget / unitMegabytes).rounded(.down)))
        return FrameCacheLimits(
            cleanedRaw: min(maximumCleanedRaw, max(minimumCleanedRaw, units)),
            developed: min(maximumDeveloped, max(minimumDeveloped, units * developedPerCleanedRaw))
        )
    }

    /// 이 한도에서 최악의 경우 상주하는 추정 메모리(MB).
    static func estimatedResidentMegabytes(_ limits: FrameCacheLimits) -> Double {
        Double(limits.cleanedRaw) * cleanedRawMegabytesPerFrame
            + Double(limits.developed) * developedMegabytesPerFrame
    }

    /// 설치 메모리 대비 비율(0~1).
    static func residentMemoryFraction(
        _ limits: FrameCacheLimits,
        physicalMemoryBytes: UInt64
    ) -> Double {
        let total = megabytes(physicalMemoryBytes)
        guard total > 0 else { return 0 }
        return estimatedResidentMegabytes(limits) / total
    }
}
