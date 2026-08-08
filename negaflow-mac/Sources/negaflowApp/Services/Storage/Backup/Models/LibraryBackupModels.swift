import Foundation
import CryptoKit

struct LibraryBackupFileRecord: Codable, Equatable {
    var relativePath: String
    var byteCount: Int64
    var sha256: String
}

struct LibraryBackupManifest: Codable, Equatable {
    static let checksummedVersion = 2
    static let currentVersion = 3

    var version: Int = currentVersion
    var sequence: UInt64? = nil
    var createdAt: Date
    var frameCount: Int
    var defectFrameIDs: [UUID]
    /// optional 필드라 기존 manifest v1 세대를 계속 읽을 수 있다.
    var catalogVersion: Int?
    var files: [LibraryBackupFileRecord]?
}

enum LibraryBackupIntegrity: Equatable {
    case legacyStructureOnly
    case checksummed
}

enum LibraryBackupGenerationState: String, Codable, Equatable {
    case checksummed
    case legacyStructureOnly
    case incompatible
    case damaged

    var isRestorable: Bool {
        self == .checksummed || self == .legacyStructureOnly
    }
}

struct LibraryBackupGeneration: Identifiable, Equatable {
    var id: String
    var sequence: UInt64? = nil
    var createdAt: Date?
    var frameCount: Int?
    var defectRecipeCount: Int?
    var catalogVersion: Int?
    var state: LibraryBackupGenerationState
}

struct LibraryBackupSnapshot {
    let directoryURL: URL
    let manifest: LibraryBackupManifest
    let catalog: LibraryCatalog
    let sourceCatalogVersion: Int
    let integrity: LibraryBackupIntegrity
}

enum LibraryBackupError: Error {
    case invalidCatalog
    case missingDefectSidecar(UUID)
    case invalidSnapshot
    case unsupportedCatalogVersion(Int)
    case unsupportedStorageVersion(Int)
    case sequenceExhausted
}

/// 카탈로그와 authoritative defect recipe를 하나의 검증 가능한 세대로 보관한다.
/// 썸네일과 cleaned raw는 재생성 가능하므로 백업에서 제외한다.
