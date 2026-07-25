import Foundation

/// 상주 프레임 한도 설정(자동/수동). 값은 UserDefaults 에 남아 앱을 껐다 켜도 유지된다.
@MainActor
final class FrameCacheResidencyStore: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case automatic
        case manual

        var id: Self { self }
    }

    private enum Keys {
        static let mode = "cache.residency.mode"
        static let cleanedRaw = "cache.residency.cleanedRaw"
        static let developed = "cache.residency.developed"
    }

    let physicalMemoryBytes: UInt64
    private let defaults: UserDefaults
    /// 한도가 바뀔 때마다 호출된다(AppModel 이 FrameCacheManager 에 반영).
    var onLimitsChange: ((FrameCacheLimits) -> Void)?

    @Published var mode: Mode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Keys.mode)
            notifyLimitsChange()
        }
    }

    @Published var manualCleanedRaw: Int {
        didSet {
            let clamped = clampedManualCleanedRaw(manualCleanedRaw)
            if clamped != manualCleanedRaw {
                manualCleanedRaw = clamped
                return
            }
            guard manualCleanedRaw != oldValue else { return }
            defaults.set(manualCleanedRaw, forKey: Keys.cleanedRaw)
            notifyLimitsChange()
        }
    }

    @Published var manualDeveloped: Int {
        didSet {
            let clamped = clampedManualDeveloped(manualDeveloped)
            if clamped != manualDeveloped {
                manualDeveloped = clamped
                return
            }
            guard manualDeveloped != oldValue else { return }
            defaults.set(manualDeveloped, forKey: Keys.developed)
            notifyLimitsChange()
        }
    }

    init(
        defaults: UserDefaults = .standard,
        physicalMemoryBytes: UInt64 = FrameCacheBudget.physicalMemoryBytes
    ) {
        self.defaults = defaults
        self.physicalMemoryBytes = physicalMemoryBytes
        let automatic = FrameCacheBudget.automaticLimits(physicalMemoryBytes: physicalMemoryBytes)
        mode = (defaults.string(forKey: Keys.mode).flatMap(Mode.init(rawValue:))) ?? .automatic
        // 저장된 수동값이 없으면 자동값에서 시작한다 — 수동으로 바꿔도 값이 튀지 않는다.
        let storedCleanedRaw = defaults.object(forKey: Keys.cleanedRaw) as? Int
        let storedDeveloped = defaults.object(forKey: Keys.developed) as? Int
        manualCleanedRaw = storedCleanedRaw ?? automatic.cleanedRaw
        manualDeveloped = storedDeveloped ?? automatic.developed
        manualCleanedRaw = clampedManualCleanedRaw(manualCleanedRaw)
        manualDeveloped = clampedManualDeveloped(manualDeveloped)
    }

    var automaticLimits: FrameCacheLimits {
        FrameCacheBudget.automaticLimits(physicalMemoryBytes: physicalMemoryBytes)
    }

    var manualMaximumLimits: FrameCacheLimits {
        FrameCacheBudget.manualMaximumLimits(physicalMemoryBytes: physicalMemoryBytes)
    }

    /// 지금 실제로 적용되는 한도.
    var effectiveLimits: FrameCacheLimits {
        switch mode {
        case .automatic:
            return automaticLimits
        case .manual:
            return FrameCacheLimits(cleanedRaw: manualCleanedRaw, developed: manualDeveloped)
        }
    }

    var estimatedResidentMegabytes: Double {
        FrameCacheBudget.estimatedResidentMegabytes(effectiveLimits)
    }

    var estimatedResidentFraction: Double {
        FrameCacheBudget.residentMemoryFraction(
            effectiveLimits,
            physicalMemoryBytes: physicalMemoryBytes
        )
    }

    /// 수동 값을 현재 자동값으로 되돌린다.
    func resetManualToAutomatic() {
        let automatic = automaticLimits
        manualCleanedRaw = automatic.cleanedRaw
        manualDeveloped = automatic.developed
    }

    private func clampedManualCleanedRaw(_ value: Int) -> Int {
        min(max(value, FrameCacheBudget.minimumCleanedRaw), manualMaximumLimits.cleanedRaw)
    }

    private func clampedManualDeveloped(_ value: Int) -> Int {
        min(max(value, FrameCacheBudget.minimumDeveloped), manualMaximumLimits.developed)
    }

    private func notifyLimitsChange() {
        onLimitsChange?(effectiveLimits)
    }
}
