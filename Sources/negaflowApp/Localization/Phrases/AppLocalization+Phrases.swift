import Foundation
import Chromabase

extension AppLocalization {

    static func text(_ key: AppLocalizedPhrase, language: AppLanguage) -> String {
        let resolved = language.resolved
        return phraseTable[resolved]?[key] ?? phraseTable[.english]?[key] ?? String(describing: key)
    }

    static func format(_ key: AppLocalizedPhrase, language: AppLanguage, _ arguments: CVarArg...) -> String {
        format(key, language: language, arguments: arguments)
    }

    static func format(_ key: AppLocalizedPhrase, language: AppLanguage, arguments: [CVarArg]) -> String {
        if let count = arguments.first as? Int {
            switch key {
            case .frameCountFormat:
                return AppStringCatalog.frameCount(count, language: language)
            case .defectsCountFormat:
                return AppStringCatalog.defectCount(count, language: language)
            default:
                break
            }
        }
        return String(format: text(key, language: language), arguments: arguments)
    }

    static func hasTranslation(_ key: AppLocalizedPhrase, language: AppLanguage) -> Bool {
        phraseTable[language.resolved]?[key] != nil
    }

    static let phraseTable: [AppLanguage: [AppLocalizedPhrase: String]] = [
        .english: englishPhraseTable,
        .korean: koreanPhraseTable,
        .japanese: japanesePhraseTable,
        .simplifiedChinese: simplifiedChinesePhraseTable,
        .french: frenchPhraseTable,
        .german: germanPhraseTable,
    ]
}
