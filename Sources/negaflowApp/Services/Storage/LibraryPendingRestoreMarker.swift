import Foundation

enum LibraryPendingRestorePhase: String, Codable, Equatable {
    case scheduled
    case applied
}

struct LibraryPendingRestoreMarker: Codable, Equatable {
    static let minimumSupportedVersion = 1
    static let currentVersion = 2

    var version: Int = currentVersion
    var directoryName: String
    var sourceGenerationID: String
    var scheduledAt: Date
    /// v1 marker에는 phase가 없다. 해당 세대는 예약 상태로 해석한다.
    var phase: LibraryPendingRestorePhase? = .scheduled

    var effectivePhase: LibraryPendingRestorePhase {
        phase ?? .scheduled
    }
}

enum LibraryPendingRestoreApplication: Equatable {
    case none
    case applied(sourceGenerationID: String)
    case cleanupOnly(sourceGenerationID: String)
    case cleanupPending(sourceGenerationID: String, didApplyRestore: Bool)

    var didApplyRestore: Bool {
        switch self {
        case .applied, .cleanupPending(_, true): true
        case .none, .cleanupOnly, .cleanupPending(_, false): false
        }
    }
}

enum LibraryPendingRestoreError: Error, Equatable {
    case invalidGeneration
    case invalidMarker
    case invalidPendingSnapshot
    case unsupportedCurrentCatalog(Int)
    case safetyBackupFailed
    case applyFailed
}

enum LibraryPendingRestoreMarkerCodec {
    static func encode(_ marker: LibraryPendingRestoreMarker) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(marker)
    }

    static func decode(_ data: Data) throws -> LibraryPendingRestoreMarker {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryPendingRestoreMarker.self, from: data)
    }
}
