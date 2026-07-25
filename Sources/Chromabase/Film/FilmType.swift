import Foundation

// MARK: - FilmType (현상 도메인)
//
// plan §7.4. ScannerKit과 Chromabase 양쪽에서 쓰이지만, 현상 도메인의 타입이므로
// Chromabase가 소유한다. ScannerKit은 아래 typealias로 같은 정의를 재노출한다.
public enum FilmType: String, Codable, Sendable, CaseIterable {
    case colorNegative
    case colorPositive      // Slide
    case bwNegative
    case bwPositive

    public var displayName: String {
        switch self {
        case .colorNegative: return "Color Negative"
        case .colorPositive: return "Slide"
        case .bwNegative:    return "B&W Negative"
        case .bwPositive:    return "B&W Positive"
        }
    }

    /// 반전이 필요한 네거티브 계열인지 (plan §8.6).
    public var requiresInversion: Bool {
        switch self {
        case .colorNegative, .bwNegative: return true
        case .colorPositive, .bwPositive: return false
        }
    }
}
