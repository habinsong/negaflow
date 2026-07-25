import Foundation

extension SourceMetadataReader {
    static func parseEXIFDate(
        dateTimeRaw: String?,
        offsetRaw: String?,
        subsecondRaw: String?
    ) -> Date? {
        guard case let .valid(value, _) = parseEXIFContentDate(
            dateTimeRaw: dateTimeRaw,
            offsetRaw: offsetRaw,
            subsecondRaw: subsecondRaw
        ) else { return nil }
        return value.instant
    }

    static func parseXMPDate(_ raw: String?) -> Date? {
        guard case let .valid(value, _) = parseXMPContentDate(raw) else { return nil }
        return value.instant
    }

    static func parseEXIFContentDate(
        dateTimeRaw: String?,
        offsetRaw: String?,
        subsecondRaw: String?
    ) -> SourceContentDateParseResult {
        guard let dateTimeRaw else { return .absent }
        if dateTimeRaw == exifUnknownDatePlaceholder { return .absent }
        guard let components = exifDateComponents(dateTimeRaw) else { return .invalid }

        var hadInvalidSupplementalValue = false
        let nanosecond: Int?
        if let subsecondRaw {
            let digits = subsecondRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            if digits.isEmpty {
                nanosecond = nil
            } else if !isASCIIDigits(digits) {
                nanosecond = nil
                hadInvalidSupplementalValue = true
            } else {
                nanosecond = nanoseconds(fromFractionDigits: digits)
            }
        } else {
            nanosecond = nil
        }

        guard let wallClock = SourceWallClockDateTime(
            year: components.year,
            month: components.month,
            day: components.day,
            hour: components.hour,
            minute: components.minute,
            second: components.second,
            nanosecond: nanosecond
        ) else { return .invalid }

        let offsetSeconds: Int?
        if let offsetRaw {
            if offsetRaw == exifUnknownOffsetPlaceholder {
                offsetSeconds = nil
            } else if offsetRaw != "Z",
                      offsetRaw != "z",
                      let parsed = timeZoneOffsetSeconds(offsetRaw) {
                offsetSeconds = parsed
            } else {
                offsetSeconds = nil
                hadInvalidSupplementalValue = true
            }
        } else {
            offsetSeconds = nil
        }
        guard let value = SourceContentDateValue(
            wallClock: wallClock,
            utcOffsetSeconds: offsetSeconds
        ) else { return .invalid }
        return .valid(value, hadInvalidSupplementalValue: hadInvalidSupplementalValue)
    }

    static func parseXMPContentDate(_ raw: String?) -> SourceContentDateParseResult {
        guard let raw else { return .absent }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .absent }
        guard let regex = xmpContentDateRegex,
              let match = regex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
              ),
              match.numberOfRanges == 9 else {
            return .invalid
        }
        func capture(_ index: Int) -> String? {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
        guard let year = capture(1).flatMap(Int.init) else { return .invalid }
        let month = capture(2).flatMap(Int.init)
        let day = capture(3).flatMap(Int.init)
        let hour = capture(4).flatMap(Int.init)
        let minute = capture(5).flatMap(Int.init)
        let second = capture(6).flatMap(Int.init)
        let nanosecond = capture(7).map(nanoseconds(fromFractionDigits:))
        guard let wallClock = SourceWallClockDateTime(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second,
            nanosecond: nanosecond
        ) else { return .invalid }

        let offsetSeconds: Int?
        if let offset = capture(8) {
            if let parsed = timeZoneOffsetSeconds(offset) {
                offsetSeconds = parsed
            } else {
                return .invalid
            }
        } else {
            offsetSeconds = nil
        }
        guard let contentDate = SourceContentDateValue(
            wallClock: wallClock,
            utcOffsetSeconds: offsetSeconds
        ) else { return .invalid }
        return .valid(
            contentDate,
            hadInvalidSupplementalValue: false
        )
    }

    static func exifDateComponents(
        _ raw: String
    ) -> (year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int)? {
        guard let regex = exifDateRegex,
              let match = regex.firstMatch(
                in: raw,
                range: NSRange(raw.startIndex..., in: raw)
              ),
              match.numberOfRanges == 7 else {
            return nil
        }
        let values = (1..<7).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: raw) else { return nil }
            return Int(raw[range])
        }
        guard values.count == 6 else { return nil }
        return (values[0], values[1], values[2], values[3], values[4], values[5])
    }

    static func nanoseconds(fromFractionDigits digits: String) -> Int {
        let firstNine = String(digits.prefix(9))
        let padded = firstNine + String(repeating: "0", count: 9 - firstNine.count)
        return Int(padded) ?? 0
    }

    static func isASCIIDigits(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value)
        }
    }

    static func timeZoneOffsetSeconds(_ raw: String) -> Int? {
        if raw == "Z" || raw == "z" { return 0 }
        guard let regex = timeZoneOffsetRegex,
              let match = regex.firstMatch(
                in: raw,
                range: NSRange(raw.startIndex..., in: raw)
              ),
              let signRange = Range(match.range(at: 1), in: raw),
              let hourRange = Range(match.range(at: 2), in: raw),
              let minuteRange = Range(match.range(at: 3), in: raw),
              let hour = Int(raw[hourRange]),
              let minute = Int(raw[minuteRange]),
              hour <= 14,
              minute < 60,
              hour < 14 || minute == 0 else {
            return nil
        }
        let sign = raw[signRange] == "-" ? -1 : 1
        return sign * ((hour * 60 + minute) * 60)
    }
}
