import Foundation
import Chromabase

struct LibraryRecoveryDiagnostics: Equatable {
    let appVersion: String
    let failureCode: String
    let lifecycleCode: String
    let catalogPath: String
    let backupDirectoryPath: String
    let pendingRestoreID: String?
    let generations: [LibraryBackupGeneration]

    var text: String {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines = [
            "negaflow.library-recovery.v1",
            "appVersion=\(appVersion)",
            "failure=\(failureCode)",
            "lifecycle=\(lifecycleCode)",
            "catalog=\(catalogPath)",
            "backupDirectory=\(backupDirectoryPath)",
            "pendingRestore=\(pendingRestoreID ?? "none")",
            "backupCount=\(generations.count)",
        ]
        lines.append(contentsOf: generations.enumerated().map { index, generation in
            let timestamp = generation.createdAt.map(iso8601.string(from:)) ?? "unknown"
            return [
                "backup[\(index)].id=\(generation.id)",
                "backup[\(index)].state=\(generation.state.rawValue)",
                "backup[\(index)].createdAt=\(timestamp)",
                "backup[\(index)].frames=\(generation.frameCount.map(String.init) ?? "unknown")",
                "backup[\(index)].recipes=\(generation.defectRecipeCount.map(String.init) ?? "unknown")",
            ].joined(separator: " ")
        })
        return lines.joined(separator: "\n")
    }
}

extension LibraryCatalogOpenFailure {
    var diagnosticCode: String {
        switch self {
        case .lockedByAnotherProcess: "lockedByAnotherProcess"
        case .lockUnavailable: "lockUnavailable"
        case .unreadable: "unreadable"
        case .corrupt: "corrupt"
        case let .unsupportedVersion(version): "unsupportedVersion:\(version)"
        case let .unsupportedStorageVersion(version): "unsupportedStorageVersion:\(version)"
        case .missingAuthoritativeData: "missingAuthoritativeData"
        case .writeFailed: "writeFailed"
        case .pendingRestoreFailed: "pendingRestoreFailed"
        }
    }
}

extension LibraryLifecycleState {
    var diagnosticCode: String {
        switch self {
        case .idle: "idle"
        case .restoring: "restoring"
        case .ready: "ready"
        case .blocked: "blocked"
        }
    }
}
