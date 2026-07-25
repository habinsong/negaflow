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
    var canOpenSafely: Bool { errorCount == 0 }
}
