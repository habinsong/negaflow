import Foundation

enum LibraryCatalogReadResult {
    case missing
    case unreadable
    case invalid
    case unsupportedVersion(Int)
    case unsupportedStorageVersion(Int)
    case loaded(catalog: LibraryCatalog, sourceVersion: Int)
}

enum LibraryCatalogOpenFailure: Equatable {
    case lockedByAnotherProcess
    case lockUnavailable
    case unreadable
    case corrupt
    case unsupportedVersion(Int)
    case unsupportedStorageVersion(Int)
    case missingAuthoritativeData
    case writeFailed
    case pendingRestoreFailed
}

enum LibraryCatalogOpenResult {
    case newLibrary
    case loaded(
        catalog: LibraryCatalog,
        recoveredFromBackup: Bool,
        migratedFromVersion: Int?
    )
    case blocked(LibraryCatalogOpenFailure)
}

enum LibraryCatalogCommitError: Error, Equatable {
    case invalidCatalog
    case encodingFailed
    case writeFailed
    case readbackFailed
    case rollbackFailed
}
