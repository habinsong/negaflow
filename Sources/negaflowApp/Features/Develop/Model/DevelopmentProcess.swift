import Chromabase

/// 현상 프로세스 목록에 표시하는 항목. 필름 4종은 FilmType 그대로이고, 디지털 사진 2종은
/// 같은 포지티브 파이프라인(E-6 / B&W Reversal)을 그대로 쓰면서 이름만 구분한다.
enum DevelopmentProcess: CaseIterable, Hashable {
    case c41
    case e6
    case d76
    case bwReversal
    case digitalColor
    case digitalBW

    static func film(_ filmType: FilmType) -> DevelopmentProcess {
        switch filmType {
        case .colorNegative: .c41
        case .colorPositive: .e6
        case .bwNegative: .d76
        case .bwPositive: .bwReversal
        }
    }

    init(filmType: FilmType, isDigitalSource: Bool?) {
        switch (filmType, isDigitalSource) {
        case (.colorPositive, true): self = .digitalColor
        case (.bwPositive, true): self = .digitalBW
        // 디지털 표시는 포지티브 경로에만 있다. 네거티브에 플래그가 남아 있으면 필름으로 읽는다.
        default: self = Self.film(filmType)
        }
    }

    var filmType: FilmType {
        switch self {
        case .c41: .colorNegative
        case .e6, .digitalColor: .colorPositive
        case .d76: .bwNegative
        case .bwReversal, .digitalBW: .bwPositive
        }
    }

    var isDigitalSource: Bool {
        switch self {
        case .digitalColor, .digitalBW: true
        case .c41, .e6, .d76, .bwReversal: false
        }
    }

    /// 기존 4종과 같이 번역하지 않는 기술 이름을 그대로 쓴다.
    var displayName: String {
        switch self {
        case .digitalColor: "Digital Color"
        case .digitalBW: "Digital B&W"
        case .c41, .e6, .d76, .bwReversal: filmType.developmentProcessName
        }
    }
}
