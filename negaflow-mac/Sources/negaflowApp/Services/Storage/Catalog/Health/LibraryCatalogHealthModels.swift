import Foundation
import ScannerKit
import Chromabase

enum LibraryCatalogHealthSeverity: String, Codable, Equatable {
    case warning
    case error
}

enum LibraryCatalogHealthIssueCode: String, Codable, Equatable {
    case duplicateFrameID
    case duplicateRollID
    case invalidPhysicalRoll
    case invalidUnassignedRoll
    case rollReferencesMissingFrame
    case frameMissingRollMembership
    case duplicateRollMembership
    case splitVirtualCopyFamily
    case missingActiveRoll
    case activeRollNotPhysical
    case duplicateScanSessionID
    case emptyScanSession
    case invalidScanSession
    case previewJobPersisted
    case duplicateScanJobID
    case duplicateCaptureManifestID
    case missingScanRollAssignment
    case duplicateScanRollAssignment
    case duplicateScanRollAssignmentRollID
    case invalidScanRollAssignment
    case scanRollAssignmentMissingSession
    case partialFrameScanProvenance
    case frameScanSessionMissing
    case frameScanJobMissing
    case frameScanJobNotSucceededFull
    case frameScanRollMismatch
    case succeededScanRollMissing
    case succeededScanJobMissingRootFrame
    case succeededScanJobDuplicateRootFrame
    case scanRootFrameCaptureMismatch
    case scanVirtualCopyRootMismatch
    case emptySourcePath
    case unsupportedSourceKind
    case invalidRating
    case invalidBaseRGB
    case invalidScanIndex
    case invalidPixelDimensions
    case invalidResolution
    case invalidBitDepth
    case unsupportedSourceMetadataVersion
    case invalidSourceMetadata
    case invalidAppMetadataOverlay
    case inconsistentVirtualCopyMetadata
    case selfReferentialVirtualCopy
    case missingVirtualCopySource
    case inconsistentVirtualCopy
    case missingDefectRecipe
    case invalidDefectRecipe
    case invalidCleanedRawCachePath
    case offlineSource
    case offlineInfraredSource
    case missingCleanedRawCache
    case duplicateFolder
    case emptyFolder
    case offlineFolder
    case duplicateManualCollectionID
    case invalidManualCollectionName
    case duplicateManualCollectionMembership
    case manualCollectionMissingFrame
    case duplicateSmartCollectionID
    case invalidSmartCollectionName
    case invalidSmartCollectionQuery
    case duplicateSavedSearchID
    case invalidSavedSearchName
    case invalidSavedSearchQuery
    case invalidUserEditTracking
    case duplicateExportEventID
    case invalidExportTracking
    case invalidDefectReviewTracking
    case duplicateStackID
    case invalidPhotoStack
    case duplicateStackMembership
    case stackReferencesMissingFrame
}

extension LibraryCatalogHealthIssueCode {
    /// 열기를 막아야 하는 error. 레코드의 정체를 카탈로그 안에서 결정할 수 없어, 자동으로
    /// 고치면 어느 쪽이 진짜인지 앱이 임의로 정하게 되는 것들이다.
    ///
    /// 나머지 error 는 전부 부수 기록(소속·스캔 이력·추적 지문·컬렉션)의 정합성 문제이고,
    /// `LibraryCatalogRepair` 가 사진을 하나도 잃지 않고 되돌릴 수 있다. 그런 것 하나 때문에
    /// 라이브러리 전체를 잠그면 멀쩡한 사진까지 못 쓰게 된다.
    var blocksOpen: Bool {
        switch self {
        case .duplicateFrameID,
             .duplicateRollID,
             .emptySourcePath,
             .unsupportedSourceKind,
             .missingDefectRecipe,
             .invalidDefectRecipe:
            true
        default:
            false
        }
    }
}

struct LibraryCatalogHealthIssue: Codable, Equatable {
    var code: LibraryCatalogHealthIssueCode
    var severity: LibraryCatalogHealthSeverity
    var frameID: UUID?
    var frameIndex: Int?
    var rollID: UUID?
    var rollIndex: Int?
    var sessionID: UUID?
    var jobID: UUID?
    var manifestID: UUID?
    var folderIndex: Int?
    var collectionID: UUID?
    var collectionIndex: Int?
    var savedSearchID: UUID?
    var savedSearchIndex: Int?
    var exportEventID: UUID?
    var exportEventIndex: Int?
    var stackID: UUID?
    var stackIndex: Int?
}

struct LibraryCatalogHealthReport: Codable, Equatable {
    var catalogVersion: Int
    var frameCount: Int
    var rollCount: Int
    var folderCount: Int
    var issues: [LibraryCatalogHealthIssue]

    var errorCount: Int { issues.count { $0.severity == .error } }
    var warningCount: Int { issues.count { $0.severity == .warning } }

    /// 완전 무결한가. 새로 쓰는 카탈로그는 이 기준을 통과해야 한다 — 저장 경로는 완화하지
    /// 않는다. 여기를 느슨하게 잡으면 앱이 스스로 깨진 카탈로그를 만들어 낼 수 있다.
    var canOpenSafely: Bool { errorCount == 0 }

    var blockingIssues: [LibraryCatalogHealthIssue] {
        issues.filter { $0.severity == .error && $0.code.blocksOpen }
    }

    var repairableIssues: [LibraryCatalogHealthIssue] {
        issues.filter { $0.severity == .error && !$0.code.blocksOpen }
    }

    /// 이미 있는 카탈로그를 여는 기준. 수리로 되돌릴 수 없는 error 만 열기를 막는다.
    var blocksOpen: Bool { !blockingIssues.isEmpty }

    var needsRepair: Bool { !repairableIssues.isEmpty }
}
