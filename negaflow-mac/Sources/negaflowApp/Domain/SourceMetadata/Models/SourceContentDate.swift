import Foundation

struct SourceWallClockDateTime: Codable, Equatable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int?
    let day: Int?
    let hour: Int?
    let minute: Int?
    let second: Int?
    let nanosecond: Int?

    init?(
        year: Int,
        month: Int? = nil,
        day: Int? = nil,
        hour: Int? = nil,
        minute: Int? = nil,
        second: Int? = nil,
        nanosecond: Int? = nil
    ) {
        guard (1...9_999).contains(year),
              month.map({ (1...12).contains($0) }) ?? true,
              day.map({ (1...31).contains($0) }) ?? true,
              hour.map({ (0...23).contains($0) }) ?? true,
              minute.map({ (0...59).contains($0) }) ?? true,
              second.map({ (0...59).contains($0) }) ?? true,
              nanosecond.map({ (0...999_999_999).contains($0) }) ?? true,
              (month != nil || day == nil),
              (day != nil || hour == nil),
              (hour == nil) == (minute == nil),
              (minute != nil || second == nil),
              (second != nil || nanosecond == nil) else {
            return nil
        }
        if let month, let day {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "en_US_POSIX")
            calendar.timeZone = .gmt
            guard let date = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: .gmt,
                year: year,
                month: month,
                day: day,
                hour: hour ?? 0,
                minute: minute ?? 0,
                second: second ?? 0
            )) else { return nil }
            let roundTrip = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date
            )
            guard roundTrip.year == year,
                  roundTrip.month == month,
                  roundTrip.day == day,
                  hour.map({ roundTrip.hour == $0 }) ?? true,
                  minute.map({ roundTrip.minute == $0 }) ?? true,
                  second.map({ roundTrip.second == $0 }) ?? true else {
                return nil
            }
        }
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.nanosecond = nanosecond
    }

    static func < (lhs: SourceWallClockDateTime, rhs: SourceWallClockDateTime) -> Bool {
        let lhsValues = [
            lhs.year,
            lhs.month ?? -1,
            lhs.day ?? -1,
            lhs.hour ?? -1,
            lhs.minute ?? -1,
            lhs.second ?? -1,
            lhs.nanosecond ?? -1,
        ]
        let rhsValues = [
            rhs.year,
            rhs.month ?? -1,
            rhs.day ?? -1,
            rhs.hour ?? -1,
            rhs.minute ?? -1,
            rhs.second ?? -1,
            rhs.nanosecond ?? -1,
        ]
        return lhsValues.lexicographicallyPrecedes(rhsValues)
    }

    private enum CodingKeys: String, CodingKey {
        case year, month, day, hour, minute, second, nanosecond
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let value = SourceWallClockDateTime(
            year: try container.decode(Int.self, forKey: .year),
            month: try container.decodeIfPresent(Int.self, forKey: .month),
            day: try container.decodeIfPresent(Int.self, forKey: .day),
            hour: try container.decodeIfPresent(Int.self, forKey: .hour),
            minute: try container.decodeIfPresent(Int.self, forKey: .minute),
            second: try container.decodeIfPresent(Int.self, forKey: .second),
            nanosecond: try container.decodeIfPresent(Int.self, forKey: .nanosecond)
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .day,
                in: container,
                debugDescription: "유효하지 않은 원본 wall-clock 시각입니다"
            )
        }
        self = value
    }
}

struct SourceContentDateValue: Codable, Equatable, Sendable {
    let wallClock: SourceWallClockDateTime
    /// 원문에 `Z` 또는 유효한 명시적 offset이 있을 때만 존재한다.
    let utcOffsetSeconds: Int?

    init?(wallClock: SourceWallClockDateTime, utcOffsetSeconds: Int?) {
        if let utcOffsetSeconds {
            let absolute = utcOffsetSeconds.magnitude
            guard wallClock.hour != nil,
                  wallClock.minute != nil,
                  absolute <= UInt(14 * 60 * 60),
                  absolute < UInt(14 * 60 * 60) || absolute.isMultiple(of: UInt(60 * 60)),
                  utcOffsetSeconds.isMultiple(of: 60) else {
                return nil
            }
        }
        self.wallClock = wallClock
        self.utcOffsetSeconds = utcOffsetSeconds
    }

    var instant: Date? {
        guard let utcOffsetSeconds,
              let month = wallClock.month,
              let day = wallClock.day,
              let hour = wallClock.hour,
              let minute = wallClock.minute,
              let second = wallClock.second,
              let timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        guard let wholeSecond = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: wallClock.year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )) else { return nil }
        return wholeSecond.addingTimeInterval(Double(wallClock.nanosecond ?? 0) / 1_000_000_000)
    }

    private enum CodingKeys: String, CodingKey {
        case wallClock
        case utcOffsetSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let wallClock = try container.decode(SourceWallClockDateTime.self, forKey: .wallClock)
        let offset = try container.decodeIfPresent(Int.self, forKey: .utcOffsetSeconds)
        guard let value = SourceContentDateValue(
            wallClock: wallClock,
            utcOffsetSeconds: offset
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .utcOffsetSeconds,
                in: container,
                debugDescription: "유효하지 않은 원본 timezone offset입니다"
            )
        }
        self = value
    }
}

enum SourceContentDateParseResult: Equatable, Sendable {
    case absent
    case valid(SourceContentDateValue, hadInvalidSupplementalValue: Bool)
    case invalid
}
