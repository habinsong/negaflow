import Foundation

enum AppDiagnosticCategory: String, Codable, CaseIterable, Sendable {
    case `import`
    case develop
    case defects
    case export
    case catalog
}

enum AppDiagnosticOperation: String, Codable, Sendable {
    case importFiles
    case developFrame
    case regionDefect
    case infraredDefect
    case cleanedRawBuild
    case cleanedRawRebuild
    case exportFrame
    case catalogRestore
    case catalogSave

    var signpostName: StaticString {
        switch self {
        case .importFiles: "Import Files"
        case .developFrame: "Develop Frame"
        case .regionDefect: "Region Defect Removal"
        case .infraredDefect: "Infrared Defect Removal"
        case .cleanedRawBuild: "Cleaned Raw Build"
        case .cleanedRawRebuild: "Cleaned Raw Rebuild"
        case .exportFrame: "Export Frame"
        case .catalogRestore: "Catalog Restore"
        case .catalogSave: "Catalog Save"
        }
    }
}

enum AppDiagnosticPhase: String, Codable, Sendable {
    case begin
    case event
    case end
    case error
}

enum AppDiagnosticSeverity: String, Codable, Sendable {
    case debug
    case info
    case notice
    case error
    case fault
}

struct AppDiagnosticEvent: Codable, Equatable, Sendable {
    let timestamp: Date
    let operationID: UUID
    let category: AppDiagnosticCategory
    let operation: AppDiagnosticOperation
    let phase: AppDiagnosticPhase
    let severity: AppDiagnosticSeverity
    /// 경로·파일명·사용자 metadata를 받지 않는 짧은 machine code만 저장한다.
    let code: String?
}

final class AppDiagnosticEventStore: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var events: [AppDiagnosticEvent] = []

    init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    func append(_ event: AppDiagnosticEvent) {
        lock.lock()
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
        lock.unlock()
    }

    func snapshot() -> [AppDiagnosticEvent] {
        lock.lock()
        let snapshot = events
        lock.unlock()
        return snapshot
    }

    func removeAll() {
        lock.lock()
        events.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
