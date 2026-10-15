import Combine
import Foundation

enum LibraryBackupSchedule: String, CaseIterable, Codable, Sendable {
    case manual
    /// 실행 중 저장 뒤 백그라운드로 만든다. 예전 "종료할 때" 설정값을 그대로 이어받는다 —
    /// 종료가 백업을 기다리느라 몇 초씩 멈췄다.
    case automatic = "onTermination"
    case daily
    case weekly
}

@MainActor
final class LibraryBackupScheduleStore: ObservableObject {
    private enum Keys {
        static let schedule = "library.backup.schedule"
        static let lastAttempt = "library.backup.lastAttempt"
        static let lastSuccess = "library.backup.lastSuccess"
        static let lastDrill = "library.backup.lastRestoreDrill"
    }

    @Published var schedule: LibraryBackupSchedule {
        didSet { defaults.set(schedule.rawValue, forKey: Keys.schedule) }
    }
    @Published private(set) var lastAttemptAt: Date?
    @Published private(set) var lastSuccessAt: Date?
    @Published private(set) var lastRestoreDrill: LibraryBackupRestoreDrillResult?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 기본값은 자동. 수동이 기본이면 설정을 한 번도 열지 않은 사용자는 백업이
        // 0 개인 채로 지내다가, 카탈로그가 어긋나는 순간 되돌릴 것이 하나도 없게 된다.
        schedule = defaults.string(forKey: Keys.schedule)
            .flatMap(LibraryBackupSchedule.init(rawValue:)) ?? .automatic
        lastAttemptAt = defaults.object(forKey: Keys.lastAttempt) as? Date
        lastSuccessAt = defaults.object(forKey: Keys.lastSuccess) as? Date
        if let data = defaults.data(forKey: Keys.lastDrill) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            lastRestoreDrill = try? decoder.decode(LibraryBackupRestoreDrillResult.self, from: data)
        }
    }

    func isDue(at date: Date = Date()) -> Bool {
        let interval: TimeInterval
        switch schedule {
        case .manual, .automatic: return false
        case .daily: interval = 24 * 60 * 60
        case .weekly: interval = 7 * 24 * 60 * 60
        }
        guard let lastAttemptAt else { return true }
        return date.timeIntervalSince(lastAttemptAt) >= interval
    }

    func recordAttempt(at date: Date = Date()) {
        lastAttemptAt = date
        defaults.set(date, forKey: Keys.lastAttempt)
    }

    func recordSuccess(_ drill: LibraryBackupRestoreDrillResult, at date: Date = Date()) {
        lastSuccessAt = date
        lastRestoreDrill = drill
        defaults.set(date, forKey: Keys.lastSuccess)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try? encoder.encode(drill), forKey: Keys.lastDrill)
    }

    func recordFailedDrill(_ drill: LibraryBackupRestoreDrillResult) {
        lastRestoreDrill = drill
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try? encoder.encode(drill), forKey: Keys.lastDrill)
    }
}
