import Foundation
import Chromabase

extension DevelopTarget {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .main:
            return AppLocalization.text(AppLocalizedPhrase.developTargetMain, language: language)
        case .print:
            return AppLocalization.text(AppLocalizedPhrase.developTargetPrint, language: language)
        default:
            return displayName
        }
    }
}

extension ScannerProfile {
    /// 좁은 사이드바에서도 필름을 구분할 수 있게 제조사 접두어를 뗀 이름.
    /// "kodak ektachrome 100d" -> "Ektachrome 100D". 제조사를 빼면 코드만 남는 두 토막
    /// 이름("fuji c200")은 이미 짧으므로 그대로 둔다.
    var compactFilmName: String {
        let words = filmKey.split(separator: " ")
        guard words.count > 2 else { return filmKey.capitalized }
        return words.dropFirst().joined(separator: " ").capitalized
    }
}

extension FilmType {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .colorNegative:
            return AppLocalization.text(AppLocalizedPhrase.filmTypeColorNegative, language: language)
        case .colorPositive:
            return AppLocalization.text(AppLocalizedPhrase.filmTypeSlide, language: language)
        case .bwNegative:
            return AppLocalization.text(AppLocalizedPhrase.filmTypeBWNegative, language: language)
        case .bwPositive:
            return AppLocalization.text(AppLocalizedPhrase.filmTypeBWPositive, language: language)
        }
    }

    var developmentProcessName: String {
        switch self {
        case .colorNegative:
            return "C-41/ECN-2"
        case .colorPositive:
            return "E-6"
        case .bwNegative:
            return "D-76"
        case .bwPositive:
            return "B&W Reversal"
        }
    }
}

extension ScannerProfileValidationStatus {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .draft:
            return AppLocalization.text(
                AppLocalizedPhrase.scannerProfileStatusDraft,
                language: language
            )
        case .realOnly:
            return AppLocalization.text(
                AppLocalizedPhrase.scannerProfileStatusRealOnly,
                language: language
            )
        case .pairedSmoke:
            return AppLocalization.text(
                AppLocalizedPhrase.scannerProfileStatusPairedSmoke,
                language: language
            )
        case .pairedValidated:
            return AppLocalization.text(
                AppLocalizedPhrase.scannerProfileStatusPairedValidated,
                language: language
            )
        }
    }
}

extension DevelopSettingsPasteScope {
    func displayName(language: AppLanguage) -> String {
        guard !isFullDevelopScope else {
            return AppLocalization.text(AppLocalizedPhrase.allSettings, language: language)
        }
        var groups: [String] = []
        if inputGamma { groups.append(AppLocalization.text(.inputGamma, language: language)) }
        if baseScale { groups.append(AppLocalization.text(.baseScale, language: language)) }
        if base { groups.append(AppLocalization.text(AppLocalizedPhrase.baseSection, language: language)) }
        if tone { groups.append(AppLocalization.text(AppLocalizedPhrase.basicTone, language: language)) }
        if color { groups.append(AppLocalization.text(AppLocalizedPhrase.color, language: language)) }
        if detail { groups.append(AppLocalization.text(AppLocalizedPhrase.detailEffects, language: language)) }
        if geometry { groups.append(AppLocalization.text(AppLocalizedPhrase.geometry, language: language)) }
        return groups.isEmpty
            ? AppLocalization.text(AppLocalizedPhrase.none, language: language)
            : groups.joined(separator: "/")
    }
}

extension AppModel {
    func text(_ key: AppLocalizedPhrase) -> String {
        AppLocalization.text(key, language: appLanguage)
    }

    func text(_ key: AppLocalizedPhrase, _ arguments: CVarArg...) -> String {
        AppLocalization.format(key, language: appLanguage, arguments: arguments)
    }
}

extension DevelopTargetFamily {
    var displayName: String {
        switch self {
        case .custom: return "CS"
        default: return selection(from: .main).displayName
        }
    }
}
