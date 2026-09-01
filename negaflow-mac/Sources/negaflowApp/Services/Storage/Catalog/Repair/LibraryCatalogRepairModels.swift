import Foundation

/// 수리가 무엇을 되돌렸는지. 진단에 그대로 실려서, 사용자가 무엇을 잃었는지(그리고 잃지
/// 않았는지) 나중에 확인할 수 있어야 한다.
enum LibraryCatalogRepairAction: String, Codable, Equatable, Sendable {
    case droppedMissingRollFrameReference
    case droppedDuplicateRollMembership
    case adoptedOrphanFrameIntoUnassignedRoll
    case normalizedUnassignedRoll
    case derivedRollFilmTypeFromFrames
    case derivedRollName
    case droppedEmptyInvalidRoll
    case clearedActiveRoll
    case droppedInvalidScanSession
    case droppedOrphanScanRollAssignment
    case droppedDuplicateScanRollAssignment
    case alignedScanRollAssignmentFilmType
    case filledScanRollAssignmentName
    case clearedFrameScanProvenance
    case clampedFrameRating
    case droppedInvalidSourceMetadata
    case droppedInvalidAppMetadataOverlay
    case recomputedUserEditTracking
    case droppedInvalidExportEvent
    case droppedDuplicateExportEvent
    case resetExportTrackingCoverage
    case resetDefectReviewTracking
    case realignedVirtualCopyRoll
    case realignedVirtualCopyMetadata
    case droppedDuplicateOrganizerID
    case filledOrganizerName
    case droppedMissingOrganizerFrame
    case droppedDuplicateOrganizerMembership
    case droppedInvalidStack
    case droppedDuplicateStackMembership
}

struct LibraryCatalogRepairReport: Equatable, Sendable {
    var actions: [LibraryCatalogRepairAction: Int] = [:]

    var isEmpty: Bool { actions.isEmpty }

    var totalCount: Int { actions.values.reduce(0, +) }

    /// 정렬된 `code=count` 목록. 진단 텍스트와 테스트가 같은 표현을 쓴다.
    var summaryComponents: [String] {
        actions
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
    }

    mutating func record(_ action: LibraryCatalogRepairAction, count: Int = 1) {
        guard count > 0 else { return }
        actions[action, default: 0] += count
    }

    mutating func merge(_ other: LibraryCatalogRepairReport) {
        for (action, count) in other.actions {
            actions[action, default: 0] += count
        }
    }
}

struct LibraryCatalogRepairResult: Equatable, Sendable {
    var catalog: LibraryCatalog
    var report: LibraryCatalogRepairReport

    var didRepair: Bool { !report.isEmpty }
}
