import Foundation
import Chromabase

enum InputGammaValueInput {
    static let step = 0.1

    static func rounded(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    static func formatted(_ value: Double) -> String { String(format: "%.1f", rounded(value)) }

    static func accepts(_ text: String) -> Bool {
        guard validSyntax(text) else { return false }
        if text.isEmpty || text == "." || text == "0" || text == "0." { return true }
        if text.hasSuffix(".") {
            return Double(text.dropLast()).map { InputGammaInterpretation.range.contains($0) } == true
        }
        return value(text) != nil
    }

    static func value(_ text: String) -> InputGammaInterpretation? {
        guard validSyntax(text), !text.isEmpty, !text.hasSuffix("."),
              let value = Double(text) else { return nil }
        return try? .power(value)
    }

    private static func validSyntax(_ text: String) -> Bool {
        guard text.utf8.count <= 6,
              text.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }),
              text.filter({ $0 == "." }).count <= 1 else { return false }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count < 2 || parts[1].count <= 1
    }
}
