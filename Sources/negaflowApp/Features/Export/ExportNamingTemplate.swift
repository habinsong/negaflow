import Foundation

struct ExportNamingContext: Equatable {
    let date: Date
    let timeZone: TimeZone
    let roll: String
    let frameIndex: Int
    let frameName: String
    let preset: String
    let sequence: Int
}

enum ExportNamingTemplate {
    static let defaultPattern = "{name}"
    static let photoNameSequencePattern = "{name}-{sequence}"
    static let sequenceOnlyPattern = "{sequence}"
    static let maximumPatternBytes = 160
    static let tokens = ["date", "roll", "frame", "name", "preset", "sequence"]

    static func usesSequence(_ pattern: String) -> Bool {
        normalized(pattern).contains("{sequence}")
    }

    static func migratedPattern(fromLegacyPrefix prefix: String) -> String {
        let sanitized = FrameStorageNaming.sanitizeComponent(prefix)
        return sanitized.isEmpty ? defaultPattern : "\(sanitized)-{name}"
    }

    static func normalized(_ pattern: String) -> String {
        var value = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.utf8.count > maximumPatternBytes { value.removeLast() }
        return value
    }

    static func isValid(_ pattern: String) -> Bool {
        let pattern = normalized(pattern)
        guard !pattern.isEmpty else { return false }
        var remainder = pattern[...]
        while let open = remainder.firstIndex(of: "{") {
            guard let close = remainder[open...].firstIndex(of: "}") else { return false }
            let token = String(remainder[remainder.index(after: open)..<close])
            guard tokens.contains(token) else { return false }
            remainder = remainder[remainder.index(after: close)...]
        }
        return !remainder.contains("}")
    }

    static func render(_ pattern: String, context: ExportNamingContext) -> String? {
        guard isValid(pattern) else { return nil }
        let values = [
            "date": dateString(context.date, timeZone: context.timeZone),
            "roll": context.roll,
            "frame": padded(context.frameIndex),
            "name": context.frameName,
            "preset": context.preset,
            "sequence": padded(context.sequence),
        ]
        var rendered = normalized(pattern)
        for token in tokens {
            rendered = rendered.replacingOccurrences(
                of: "{\(token)}",
                with: FrameStorageNaming.sanitizeComponent(values[token] ?? "")
            )
        }
        rendered = FrameStorageNaming.sanitizeComponent(rendered)
        while rendered.utf8.count > 200 { rendered.removeLast() }
        return rendered.isEmpty ? nil : rendered
    }

    private static func padded(_ value: Int) -> String {
        String(format: "%04d", max(0, value))
    }

    private static func dateString(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return FrameStorageNaming.dateFolderName(for: date, calendar: calendar)
    }
}
