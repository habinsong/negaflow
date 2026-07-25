import Chromabase

enum InfraredFilmCompatibility: Equatable {
    case supportedColorNegative
    case unverifiedColorPositive
    case unverifiedBlackAndWhite

    init(filmType: FilmType) {
        switch filmType {
        case .colorNegative:
            self = .supportedColorNegative
        case .colorPositive:
            self = .unverifiedColorPositive
        case .bwNegative, .bwPositive:
            self = .unverifiedBlackAndWhite
        }
    }

    var allowsAutomaticCorrection: Bool {
        self == .supportedColorNegative
    }
}
