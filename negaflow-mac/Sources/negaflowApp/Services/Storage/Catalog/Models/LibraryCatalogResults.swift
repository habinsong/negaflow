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
        migratedFromVersion: Int?,
        repairReport: LibraryCatalogRepairReport?
    )
    case blocked(LibraryCatalogOpenFailure)

    static func loaded(
        catalog: LibraryCatalog,
        recoveredFromBackup: Bool,
        migratedFromVersion: Int?
    ) -> LibraryCatalogOpenResult {
        .loaded(
            catalog: catalog,
            recoveredFromBackup: recoveredFromBackup,
            migratedFromVersion: migratedFromVersion,
            repairReport: nil
        )
    }
}

enum LibraryCatalogCommitError: Error, Equatable {
    case invalidCatalog
    case encodingFailed
    case writeFailed
    case readbackFailed
    case rollbackFailed
}
