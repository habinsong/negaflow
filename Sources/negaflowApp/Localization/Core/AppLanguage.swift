import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case korean = "ko"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .korean: return "한국어"
        case .japanese: return "日本語"
        case .simplifiedChinese: return "简体中文"
        case .french: return "Français"
        case .german: return "Deutsch"
        }
    }

    var resolved: AppLanguage {
        guard self == .system else { return self }
        let identifier = Locale.current.language.languageCode?.identifier ?? "en"
        switch identifier {
        case "ko": return .korean
        case "ja": return .japanese
        case "zh": return .simplifiedChinese
        case "fr": return .french
        case "de": return .german
        default: return .english
        }
    }
}
