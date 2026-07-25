import Foundation
import Chromabase
import ScannerKit

struct LibraryCatalogVersionProbe: Decodable {
    let version: Int
}

/// v5의 마지막 배포 shape. v6의 stack key가 없음을 명시적으로 마이그레이션한다.
struct LibraryCatalogV5: Decodable {
    let version: Int
    let minimumReaderVersion: Int
    let folders: [String]
    let frames: [LibraryFrameRecord]
    let rolls: [LibraryRoll]
    let activeRollID: UUID?
    let scanSessions: [ScanSession]
    let scanRollAssignments: [LibraryScanRollAssignment]
    let manualCollections: [LibraryManualCollection]
    let smartCollections: [LibrarySmartCollection]
    let savedSearches: [LibrarySavedSearch]
}

/// v4의 마지막 배포 shape를 현재 모델과 분리해 고정한다. 새 collection/tracking key가
/// v4에 없다는 이유로 기본값 decode를 사용하지 않고 순수하게 v5로 옮긴다.
struct LibraryCatalogV4: Decodable {
    let version: Int
    let minimumReaderVersion: Int
    let folders: [String]
    let frames: [LibraryFrameRecordV4]
    let rolls: [LibraryRoll]
    let activeRollID: UUID?
    let scanSessions: [ScanSession]
    let scanRollAssignments: [LibraryScanRollAssignment]
}

struct LibraryFrameRecordV4: Decodable {
    var id: UUID
    var scanIndex: Int
    var rawScanPath: String
    var infraredScanPath: String?
    var rawScanBookmarkData: Data?
    var infraredScanBookmarkData: Data?
    var sourceKind: String
    var storageGroup: String?
    var sourcePixelWidth: Int?
    var sourcePixelHeight: Int?
    var sourceResolutionDPI: Int?
    var sourceBitDepth: Int?
    var sourceMetadata: SourceMetadataSnapshot?
    var scanSessionID: UUID?
    var scanJobID: UUID?
    var scannedAt: Date
    var filmType: FilmType
    var presetID: String?
    var params: DevelopParameters
    var imageTransform: ImageTransform
    var baseRGB: [Double]?
    var rating: Int
    var pickState: FramePickState
    var customDisplayName: String?
    var hasDevelopedOnce: Bool
    var developHistory: [DevelopHistoryEntry]
    var developSnapshots: [DevelopSnapshot]
    var sourceFrameID: UUID?
    var sourceFrameDisplayName: String?
    var virtualCopyNumber: Int?
    var cleanedRawPath: String?
    var cleanedRawEditCount: Int?
    var hasDefectEdits: Bool?

    var currentRecord: LibraryFrameRecord {
        LibraryFrameRecord(
            id: id,
            scanIndex: scanIndex,
            rawScanPath: rawScanPath,
            infraredScanPath: infraredScanPath,
            rawScanBookmarkData: rawScanBookmarkData,
            infraredScanBookmarkData: infraredScanBookmarkData,
            sourceKind: sourceKind,
            storageGroup: storageGroup,
            sourcePixelWidth: sourcePixelWidth,
            sourcePixelHeight: sourcePixelHeight,
            sourceResolutionDPI: sourceResolutionDPI,
            sourceBitDepth: sourceBitDepth,
            sourceMetadata: sourceMetadata,
            scanSessionID: scanSessionID,
            scanJobID: scanJobID,
            scannedAt: scannedAt,
            filmType: filmType,
            presetID: presetID,
            params: params,
            imageTransform: imageTransform,
            baseRGB: baseRGB,
            rating: rating,
            pickState: pickState,
            customDisplayName: customDisplayName,
            hasDevelopedOnce: hasDevelopedOnce,
            developHistory: developHistory,
            developSnapshots: developSnapshots,
            sourceFrameID: sourceFrameID,
            sourceFrameDisplayName: sourceFrameDisplayName,
            virtualCopyNumber: virtualCopyNumber,
            cleanedRawPath: cleanedRawPath,
            cleanedRawEditCount: cleanedRawEditCount,
            hasDefectEdits: hasDefectEdits,
            userEditTracking: .legacyUnknown(
                currentRecipeSHA256: try? LibraryDevelopRecipeFingerprint.sha256(
                    filmType: filmType,
                    presetID: presetID,
                    params: params,
                    imageTransform: imageTransform
                )
            ),
            exportTracking: .legacyUnknown,
            defectReviewTracking: .legacyUnknown
        )
    }
}

/// v3의 마지막 배포 shape를 현재 모델과 분리해 고정한다. 마이그레이션 중 파일을 다시 읽거나
/// 롤/workflow를 재구성하지 않고 저장된 값을 그대로 v5로 옮긴다.
struct LibraryCatalogV3: Decodable {
    let version: Int
    let minimumReaderVersion: Int
    let folders: [String]
    let frames: [LibraryFrameRecordV3]
    let rolls: [LibraryRoll]
    let activeRollID: UUID?
    let scanSessions: [ScanSession]
    let scanRollAssignments: [LibraryScanRollAssignment]
}

struct LibraryFrameRecordV3: Decodable {
    var id: UUID
    var scanIndex: Int
    var rawScanPath: String
    var infraredScanPath: String?
    var rawScanBookmarkData: Data?
    var infraredScanBookmarkData: Data?
    var sourceKind: String
    var storageGroup: String?
    var sourcePixelWidth: Int?
    var sourcePixelHeight: Int?
    var sourceResolutionDPI: Int?
    var sourceBitDepth: Int?
    var scanSessionID: UUID?
    var scanJobID: UUID?
    var scannedAt: Date
    var filmType: FilmType
    var presetID: String?
    var params: DevelopParameters
    var imageTransform: ImageTransform
    var baseRGB: [Double]?
    var rating: Int
    var pickState: FramePickState
    var customDisplayName: String?
    var hasDevelopedOnce: Bool
    var developHistory: [DevelopHistoryEntry]
    var developSnapshots: [DevelopSnapshot]
    var sourceFrameID: UUID?
    var sourceFrameDisplayName: String?
    var virtualCopyNumber: Int?
    var cleanedRawPath: String?
    var cleanedRawEditCount: Int?
    var hasDefectEdits: Bool?

    var currentRecord: LibraryFrameRecord {
        LibraryFrameRecord(
            id: id,
            scanIndex: scanIndex,
            rawScanPath: rawScanPath,
            infraredScanPath: infraredScanPath,
            rawScanBookmarkData: rawScanBookmarkData,
            infraredScanBookmarkData: infraredScanBookmarkData,
            sourceKind: sourceKind,
            storageGroup: storageGroup,
            sourcePixelWidth: sourcePixelWidth,
            sourcePixelHeight: sourcePixelHeight,
            sourceResolutionDPI: sourceResolutionDPI,
            sourceBitDepth: sourceBitDepth,
            sourceMetadata: nil,
            scanSessionID: scanSessionID,
            scanJobID: scanJobID,
            scannedAt: scannedAt,
            filmType: filmType,
            presetID: presetID,
            params: params,
            imageTransform: imageTransform,
            baseRGB: baseRGB,
            rating: rating,
            pickState: pickState,
            customDisplayName: customDisplayName,
            hasDevelopedOnce: hasDevelopedOnce,
            developHistory: developHistory,
            developSnapshots: developSnapshots,
            sourceFrameID: sourceFrameID,
            sourceFrameDisplayName: sourceFrameDisplayName,
            virtualCopyNumber: virtualCopyNumber,
            cleanedRawPath: cleanedRawPath,
            cleanedRawEditCount: cleanedRawEditCount,
            hasDefectEdits: hasDefectEdits,
            userEditTracking: .legacyUnknown(
                currentRecipeSHA256: try? LibraryDevelopRecipeFingerprint.sha256(
                    filmType: filmType,
                    presetID: presetID,
                    params: params,
                    imageTransform: imageTransform
                )
            ),
            exportTracking: .legacyUnknown,
            defectReviewTracking: .legacyUnknown
        )
    }
}

/// v2의 마지막 배포 shape를 현재 모델과 분리해 고정한다. v3 필드가 늘어나도 v2 decode가
/// 현재 타입의 기본값이나 새 필드에 암묵적으로 의존하지 않는다.
struct LibraryCatalogV2: Decodable {
    let version: Int
    let minimumReaderVersion: Int
    let folders: [String]
    let frames: [LibraryFrameRecordV2]
}

struct LibraryFrameRecordV2: Decodable {
    var id: UUID
    var scanIndex: Int
    var rawScanPath: String
    var infraredScanPath: String?
    var rawScanBookmarkData: Data?
    var infraredScanBookmarkData: Data?
    var sourceKind: String
    var storageGroup: String?
    var sourcePixelWidth: Int?
    var sourcePixelHeight: Int?
    var sourceResolutionDPI: Int?
    var sourceBitDepth: Int?
    var scannedAt: Date
    var filmType: FilmType
    var presetID: String?
    var params: DevelopParameters
    var imageTransform: ImageTransform
    var baseRGB: [Double]?
    var rating: Int
    var pickState: FramePickState
    var customDisplayName: String?
    var hasDevelopedOnce: Bool
    var developHistory: [DevelopHistoryEntry]
    var developSnapshots: [DevelopSnapshot]
    var sourceFrameID: UUID?
    var sourceFrameDisplayName: String?
    var virtualCopyNumber: Int?
    var cleanedRawPath: String?
    var cleanedRawEditCount: Int?
    var hasDefectEdits: Bool?

    var currentRecord: LibraryFrameRecord {
        LibraryFrameRecord(
            id: id,
            scanIndex: scanIndex,
            rawScanPath: rawScanPath,
            infraredScanPath: infraredScanPath,
            rawScanBookmarkData: rawScanBookmarkData,
            infraredScanBookmarkData: infraredScanBookmarkData,
            sourceKind: sourceKind,
            storageGroup: storageGroup,
            sourcePixelWidth: sourcePixelWidth,
            sourcePixelHeight: sourcePixelHeight,
            sourceResolutionDPI: sourceResolutionDPI,
            sourceBitDepth: sourceBitDepth,
            sourceMetadata: nil,
            scanSessionID: nil,
            scanJobID: nil,
            scannedAt: scannedAt,
            filmType: filmType,
            presetID: presetID,
            params: params,
            imageTransform: imageTransform,
            baseRGB: baseRGB,
            rating: rating,
            pickState: pickState,
            customDisplayName: customDisplayName,
            hasDevelopedOnce: hasDevelopedOnce,
            developHistory: developHistory,
            developSnapshots: developSnapshots,
            sourceFrameID: sourceFrameID,
            sourceFrameDisplayName: sourceFrameDisplayName,
            virtualCopyNumber: virtualCopyNumber,
            cleanedRawPath: cleanedRawPath,
            cleanedRawEditCount: cleanedRawEditCount,
            hasDefectEdits: hasDefectEdits,
            userEditTracking: .legacyUnknown(
                currentRecipeSHA256: try? LibraryDevelopRecipeFingerprint.sha256(
                    filmType: filmType,
                    presetID: presetID,
                    params: params,
                    imageTransform: imageTransform
                )
            ),
            exportTracking: .legacyUnknown,
            defectReviewTracking: .legacyUnknown
        )
    }
}

struct LibraryCatalogV1: Decodable {
    let version: Int
    let folders: [String]
    let frames: [LibraryFrameRecordV1]
}

struct LibraryFrameRecordV1: Decodable {
    var id: UUID
    var scanIndex: Int
    var rawScanPath: String
    var infraredScanPath: String?
    var rawScanBookmarkData: Data?
    var infraredScanBookmarkData: Data?
    var sourceKind: String
    var storageGroup: String?
    var sourcePixelWidth: Int?
    var sourcePixelHeight: Int?
    var sourceResolutionDPI: Int?
    var sourceBitDepth: Int?
    var scannedAt: Date
    var filmType: FilmType
    var presetID: String?
    var params: DevelopParameters
    var imageTransform: ImageTransform
    var baseRGB: [Double]?
    var rating: Int
    var pickState: FramePickState
    var customDisplayName: String?
    var hasDevelopedOnce: Bool
    var developHistory: [DevelopHistoryEntry]
    var developSnapshots: [DevelopSnapshot]
    var sourceFrameID: UUID?
    var sourceFrameDisplayName: String?
    var virtualCopyNumber: Int?
    var cleanedRawPath: String?
    var cleanedRawEditCount: Int?
    var hasDefectEdits: Bool?

    var currentRecord: LibraryFrameRecord {
        LibraryFrameRecord(
            id: id,
            scanIndex: scanIndex,
            rawScanPath: rawScanPath,
            infraredScanPath: infraredScanPath,
            rawScanBookmarkData: rawScanBookmarkData,
            infraredScanBookmarkData: infraredScanBookmarkData,
            sourceKind: sourceKind,
            storageGroup: storageGroup,
            sourcePixelWidth: sourcePixelWidth,
            sourcePixelHeight: sourcePixelHeight,
            sourceResolutionDPI: sourceResolutionDPI,
            sourceBitDepth: sourceBitDepth,
            sourceMetadata: nil,
            scanSessionID: nil,
            scanJobID: nil,
            scannedAt: scannedAt,
            filmType: filmType,
            presetID: presetID,
            params: params,
            imageTransform: imageTransform,
            baseRGB: baseRGB,
            rating: rating,
            pickState: pickState,
            customDisplayName: customDisplayName,
            hasDevelopedOnce: hasDevelopedOnce,
            developHistory: developHistory,
            developSnapshots: developSnapshots,
            sourceFrameID: sourceFrameID,
            sourceFrameDisplayName: sourceFrameDisplayName,
            virtualCopyNumber: virtualCopyNumber,
            cleanedRawPath: cleanedRawPath,
            cleanedRawEditCount: cleanedRawEditCount,
            hasDefectEdits: hasDefectEdits,
            userEditTracking: .legacyUnknown(
                currentRecipeSHA256: try? LibraryDevelopRecipeFingerprint.sha256(
                    filmType: filmType,
                    presetID: presetID,
                    params: params,
                    imageTransform: imageTransform
                )
            ),
            exportTracking: .legacyUnknown,
            defectReviewTracking: .legacyUnknown
        )
    }
}
