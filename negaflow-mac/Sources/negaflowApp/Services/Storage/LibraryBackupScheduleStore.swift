import Combine
import Foundation

enum LibraryBackupSchedule: String, CaseIterable, Codable, Sendable {
    case manual
    case onTermination
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
        schedule = defaults.string(forKey: Keys.schedule)
            .flatMap(LibraryBackupSchedule.init(rawValue:)) ?? .manual
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
        case .manual, .onTermination: return false
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
