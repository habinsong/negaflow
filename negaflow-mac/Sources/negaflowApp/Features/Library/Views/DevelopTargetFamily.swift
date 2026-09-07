import Chromabase

// UI 갈래입니다. CS를 카탈로그나 렌더러의 새 타깃으로 저장하지 않습니다.
enum DevelopTargetFamily: CaseIterable {
    case main, hs, sp, f135, hr, custom

    init(target: DevelopTarget) {
        if target.isCustom {
            self = .custom
        } else {
            switch target {
            case .noritsu: self = .hs
            case .sp3000: self = .sp
            case .f135: self = .f135
            case .hr: self = .hr
            default: self = .main
            }
        }
    }

    func selection(from current: DevelopTarget) -> DevelopTarget {
        guard Self(target: current) != self else { return current }
        switch self {
        case .main: return .main
        case .hs: return .noritsu
        case .sp: return .sp3000
        case .f135: return .f135
        case .hr: return .hr
        case .custom: return .emulsion
        }
    }
}
