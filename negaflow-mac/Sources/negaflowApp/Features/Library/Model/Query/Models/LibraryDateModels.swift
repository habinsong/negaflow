import Foundation
import Chromabase
import ScannerKit

enum LibraryDateField: String, Codable, Equatable, Sendable {
    /// 명시적 timezone이 있는 원본 콘텐츠 절대시각. 달력 날짜 검색과 혼동하지 않는다.
    case contentInstant
    /// negaflow catalog에 스캔 또는 가져온 시각.
    case scannedOrImportedDate
}

enum LibraryDatePredicate: Codable, Equatable, Sendable {
    case before(Date)
    case after(Date)
    case range(startInclusive: Date, endExclusive: Date)

    private enum Kind: String, Codable { case before, after, range }
    private enum CodingKeys: String, CodingKey { case kind, date, startInclusive, endExclusive }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .before:
            self = .before(try container.decode(Date.self, forKey: .date))
        case .after:
            self = .after(try container.decode(Date.self, forKey: .date))
        case .range:
            self = .range(
                startInclusive: try container.decode(Date.self, forKey: .startInclusive),
                endExclusive: try container.decode(Date.self, forKey: .endExclusive)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .before(date):
            try container.encode(Kind.before, forKey: .kind)
            try container.encode(date, forKey: .date)
        case let .after(date):
            try container.encode(Kind.after, forKey: .kind)
            try container.encode(date, forKey: .date)
        case let .range(startInclusive, endExclusive):
            try container.encode(Kind.range, forKey: .kind)
            try container.encode(startInclusive, forKey: .startInclusive)
            try container.encode(endExclusive, forKey: .endExclusive)
        }
    }
}

struct LibraryDateCondition: Codable, Equatable, Sendable {
    var field: LibraryDateField
    var predicate: LibraryDatePredicate
}

/// 원본 metadata에 기록된 달력 날짜다. 시간대가 없는 EXIF도 임의의 timezone을
/// 추정하지 않고 날짜별 검색에 사용할 수 있도록 절대시각과 분리한다.
struct LibraryCalendarDate: Codable, Equatable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        guard Self.isValid(year: year, month: month, day: day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    static func < (lhs: LibraryCalendarDate, rhs: LibraryCalendarDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    private static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard (1...9_999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: .gmt,
            year: year,
            month: month,
            day: day
        )) else { return false }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        return roundTrip.year == year && roundTrip.month == month && roundTrip.day == day
    }

    private enum CodingKeys: String, CodingKey {
        case year
        case month
        case day
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        let day = try container.decode(Int.self, forKey: .day)
        guard let value = LibraryCalendarDate(year: year, month: month, day: day) else {
            throw DecodingError.dataCorruptedError(
                forKey: .day,
                in: container,
                debugDescription: "유효하지 않은 달력 날짜입니다"
            )
        }
        self = value
    }
}

enum LibraryCalendarDateField: String, Codable, Equatable, Sendable {
    case contentDate
}

enum LibraryCalendarDatePredicate: Codable, Equatable, Sendable {
    case before(LibraryCalendarDate)
    case after(LibraryCalendarDate)
    case range(startInclusive: LibraryCalendarDate, endExclusive: LibraryCalendarDate)

    private enum Kind: String, Codable { case before, after, range }
    private enum CodingKeys: String, CodingKey { case kind, date, startInclusive, endExclusive }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .before:
            self = .before(try container.decode(LibraryCalendarDate.self, forKey: .date))
        case .after:
            self = .after(try container.decode(LibraryCalendarDate.self, forKey: .date))
        case .range:
            self = .range(
                startInclusive: try container.decode(
                    LibraryCalendarDate.self,
                    forKey: .startInclusive
                ),
                endExclusive: try container.decode(
                    LibraryCalendarDate.self,
                    forKey: .endExclusive
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .before(date):
            try container.encode(Kind.before, forKey: .kind)
            try container.encode(date, forKey: .date)
        case let .after(date):
            try container.encode(Kind.after, forKey: .kind)
            try container.encode(date, forKey: .date)
        case let .range(startInclusive, endExclusive):
            try container.encode(Kind.range, forKey: .kind)
            try container.encode(startInclusive, forKey: .startInclusive)
            try container.encode(endExclusive, forKey: .endExclusive)
        }
    }
}

struct LibraryCalendarDateCondition: Codable, Equatable, Sendable {
    var field: LibraryCalendarDateField
    var predicate: LibraryCalendarDatePredicate
}

/// 정밀도가 낮은 원본 날짜가 가리킬 수 있는 모든 달력 날짜다.
/// 검색은 이 구간 전체가 조건을 만족할 때만 positive로 판정한다.
struct LibraryCalendarDateInterval: Equatable, Sendable {
    let firstInclusive: LibraryCalendarDate
    let lastInclusive: LibraryCalendarDate

    init?(firstInclusive: LibraryCalendarDate, lastInclusive: LibraryCalendarDate) {
        guard firstInclusive <= lastInclusive else { return nil }
        self.firstInclusive = firstInclusive
        self.lastInclusive = lastInclusive
    }

    init(_ date: LibraryCalendarDate) {
        firstInclusive = date
        lastInclusive = date
    }
}
