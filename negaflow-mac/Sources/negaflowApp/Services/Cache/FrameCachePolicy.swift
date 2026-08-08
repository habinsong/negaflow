import Dispatch

enum FrameCachePressureLevel: String, Sendable, Equatable {
    case normal
    case warning
    case critical

    init(event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.critical) {
            self = .critical
        } else if event.contains(.warning) {
            self = .warning
        } else {
            self = .normal
        }
    }
}

struct FrameCacheLimits: Sendable, Equatable {
    let cleanedRaw: Int
    let developed: Int

    init(cleanedRaw: Int, developed: Int) {
        self.cleanedRaw = max(0, cleanedRaw)
        self.developed = max(1, developed)
    }
}

struct FrameCachePolicy: Sendable, Equatable {
    let normalLimits: FrameCacheLimits

    init(normalLimits: FrameCacheLimits = FrameCacheLimits(cleanedRaw: 2, developed: 3)) {
        self.normalLimits = normalLimits
    }

    func limits(for pressure: FrameCachePressureLevel) -> FrameCacheLimits {
        switch pressure {
        case .normal:
            normalLimits
        case .warning:
            FrameCacheLimits(
                cleanedRaw: min(normalLimits.cleanedRaw, 1),
                developed: min(normalLimits.developed, 2)
            )
        case .critical:
            FrameCacheLimits(cleanedRaw: 0, developed: 1)
        }
    }
}
