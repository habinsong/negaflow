import Foundation
import ScannerKit
import Chromabase

extension LibraryCatalogHealthInspector {
    static func issue(
        _ code: LibraryCatalogHealthIssueCode,
        _ severity: LibraryCatalogHealthSeverity,
        frameID: UUID? = nil,
        frameIndex: Int? = nil,
        rollID: UUID? = nil,
        rollIndex: Int? = nil,
        sessionID: UUID? = nil,
        jobID: UUID? = nil,
        manifestID: UUID? = nil,
        folderIndex: Int? = nil,
        collectionID: UUID? = nil,
        collectionIndex: Int? = nil,
        savedSearchID: UUID? = nil,
        savedSearchIndex: Int? = nil,
        exportEventID: UUID? = nil,
        exportEventIndex: Int? = nil,
        stackID: UUID? = nil,
        stackIndex: Int? = nil
    ) -> LibraryCatalogHealthIssue {
        LibraryCatalogHealthIssue(
            code: code,
            severity: severity,
            frameID: frameID,
            frameIndex: frameIndex,
            rollID: rollID,
            rollIndex: rollIndex,
            sessionID: sessionID,
            jobID: jobID,
            manifestID: manifestID,
            folderIndex: folderIndex,
            collectionID: collectionID,
            collectionIndex: collectionIndex,
            savedSearchID: savedSearchID,
            savedSearchIndex: savedSearchIndex,
            exportEventID: exportEventID,
            exportEventIndex: exportEventIndex,
            stackID: stackID,
            stackIndex: stackIndex
        )
    }

    static func issueSort(
        _ lhs: LibraryCatalogHealthIssue,
        _ rhs: LibraryCatalogHealthIssue
    ) -> Bool {
        let lhsKey = (
            lhs.severity == .error ? 0 : 1,
            lhs.code.rawValue,
            lhs.frameID?.uuidString ?? "",
            lhs.frameIndex ?? -1,
            "\(lhs.rollID?.uuidString ?? ""):\(lhs.rollIndex ?? -1)",
            "\(lhs.sessionID?.uuidString ?? ""):\(lhs.jobID?.uuidString ?? ""):\(lhs.manifestID?.uuidString ?? ""):\(lhs.folderIndex ?? -1):\(lhs.collectionID?.uuidString ?? ""):\(lhs.collectionIndex ?? -1):\(lhs.savedSearchID?.uuidString ?? ""):\(lhs.savedSearchIndex ?? -1):\(lhs.exportEventID?.uuidString ?? ""):\(lhs.exportEventIndex ?? -1):\(lhs.stackID?.uuidString ?? ""):\(lhs.stackIndex ?? -1)"
        )
        let rhsKey = (
            rhs.severity == .error ? 0 : 1,
            rhs.code.rawValue,
            rhs.frameID?.uuidString ?? "",
            rhs.frameIndex ?? -1,
            "\(rhs.rollID?.uuidString ?? ""):\(rhs.rollIndex ?? -1)",
            "\(rhs.sessionID?.uuidString ?? ""):\(rhs.jobID?.uuidString ?? ""):\(rhs.manifestID?.uuidString ?? ""):\(rhs.folderIndex ?? -1):\(rhs.collectionID?.uuidString ?? ""):\(rhs.collectionIndex ?? -1):\(rhs.savedSearchID?.uuidString ?? ""):\(rhs.savedSearchIndex ?? -1):\(rhs.exportEventID?.uuidString ?? ""):\(rhs.exportEventIndex ?? -1):\(rhs.stackID?.uuidString ?? ""):\(rhs.stackIndex ?? -1)"
        )
        return lhsKey < rhsKey
    }

}
