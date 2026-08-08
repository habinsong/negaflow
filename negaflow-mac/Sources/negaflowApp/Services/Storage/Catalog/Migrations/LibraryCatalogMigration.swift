import Foundation
import Chromabase
import ScannerKit

extension LibraryCatalogFile {
    static func migrateV1ToV6(_ legacy: LibraryCatalogV1) -> LibraryCatalog {
        migrateLegacy(folders: legacy.folders, frames: legacy.frames.map(\.currentRecord))
    }

    static func migrateV2ToV6(_ legacy: LibraryCatalogV2) -> LibraryCatalog {
        migrateLegacy(folders: legacy.folders, frames: legacy.frames.map(\.currentRecord))
    }

    static func migrateV3ToV6(_ legacy: LibraryCatalogV3) -> LibraryCatalog {
        LibraryCatalog(
            version: LibraryCatalog.currentVersion,
            minimumReaderVersion: LibraryCatalog.oldestReaderVersion,
            folders: legacy.folders,
            frames: legacy.frames.map(\.currentRecord),
            rolls: legacy.rolls,
            activeRollID: legacy.activeRollID,
            scanSessions: legacy.scanSessions,
            scanRollAssignments: legacy.scanRollAssignments
        )
    }

    static func migrateV4ToV6(_ legacy: LibraryCatalogV4) -> LibraryCatalog {
        LibraryCatalog(
            version: LibraryCatalog.currentVersion,
            minimumReaderVersion: LibraryCatalog.oldestReaderVersion,
            folders: legacy.folders,
            frames: legacy.frames.map(\.currentRecord),
            rolls: legacy.rolls,
            activeRollID: legacy.activeRollID,
            scanSessions: legacy.scanSessions,
            scanRollAssignments: legacy.scanRollAssignments
        )
    }

    static func migrateV5ToV6(_ legacy: LibraryCatalogV5) -> LibraryCatalog {
        LibraryCatalog(
            version: LibraryCatalog.currentVersion,
            minimumReaderVersion: LibraryCatalog.oldestReaderVersion,
            folders: legacy.folders,
            frames: legacy.frames,
            rolls: legacy.rolls,
            activeRollID: legacy.activeRollID,
            scanSessions: legacy.scanSessions,
            scanRollAssignments: legacy.scanRollAssignments,
            manualCollections: legacy.manualCollections,
            smartCollections: legacy.smartCollections,
            savedSearches: legacy.savedSearches,
            stacks: []
        )
    }

    static func migrateLegacy(
        folders: [String],
        frames: [LibraryFrameRecord]
    ) -> LibraryCatalog {
        LibraryCatalog(
            version: LibraryCatalog.currentVersion,
            minimumReaderVersion: LibraryCatalog.oldestReaderVersion,
            folders: folders,
            frames: frames,
            scanSessions: [],
            scanRollAssignments: []
        )
    }

}
