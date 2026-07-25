import Foundation

struct AppLocalization {

    static func text(_ key: AppLocalizedText, language: AppLanguage) -> String {
        let resolved = language.resolved
        return table[resolved]?[key] ?? table[.english]?[key] ?? String(describing: key)
    }

    static func hasTranslation(_ key: AppLocalizedText, language: AppLanguage) -> Bool {
        table[language.resolved]?[key] != nil
    }

    static let table: [AppLanguage: [AppLocalizedText: String]] = [
        .english: englishTextTable,
        .korean: koreanTextTable,
        .japanese: japaneseTextTable,
        .simplifiedChinese: simplifiedChineseTextTable,
        .french: frenchTextTable,
        .german: germanTextTable,
    ]
}
