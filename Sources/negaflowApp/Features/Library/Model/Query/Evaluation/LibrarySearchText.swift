import Foundation
import Chromabase
import ScannerKit

enum LibrarySearchText {
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func normalize(_ value: String) -> String {
        let canonical = value.precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: locale
            )
            .precomposedStringWithCanonicalMapping
        return canonical.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func normalizeValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = normalize(value)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    static func removingWhitespace(_ normalized: String) -> String {
        normalized.filter { !$0.isWhitespace }
    }

    static func matches(
        values: [String],
        rule: LibraryTextMatchRule,
        query: String,
        knowledgeIsComplete: Bool = true
    ) -> Bool {
        let normalizedValues = normalizeValues(values)
        return LibraryPreparedTextPredicate(
            LibraryTextCondition(field: .anySearchable, rule: rule, value: query)
        ).matches(normalizedValues, knowledgeIsComplete: knowledgeIsComplete)
    }

    static func substringTerms(_ normalizedQuery: String) -> [String] {
        wordTokens(normalizedQuery)
    }

    static func wordTokens(_ normalized: String) -> [String] {
        var tokens: [String] = []
        var scalars = String.UnicodeScalarView()
        func flush() {
            guard !scalars.isEmpty else { return }
            tokens.append(String(scalars))
            scalars = String.UnicodeScalarView()
        }
        for scalar in normalized.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        return stableUnique(tokens)
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
