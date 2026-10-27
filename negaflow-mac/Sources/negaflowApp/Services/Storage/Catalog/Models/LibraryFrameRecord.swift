import Foundation
import Chromabase
import ScannerKit

struct LibraryFrameRecord: Codable, Equatable {
    var id: UUID
    var scanIndex: Int
    var rawScanPath: String
    var infraredScanPath: String?
    /// 경로가 Finder에서 이동·변경돼도 같은 볼륨의 원본을 다시 찾기 위한 macOS bookmark.
    /// optional이라 기존 v1 catalog와 호환된다.
    var rawScanBookmarkData: Data?
    var infraredScanBookmarkData: Data?
    var sourceKind: String
    /// 날짜 폴더 아래 출처 폴더명(default / 가져온 폴더명 / 스캐너 축약명).
    var storageGroup: String?
    var sourcePixelWidth: Int?
    var sourcePixelHeight: Int?
    var sourceResolutionDPI: Int?
    var sourceBitDepth: Int?
    var sourceMetadata: SourceMetadataSnapshot? = nil
    var appMetadataOverlay: AppMetadataOverlay? = nil
    /// 외부 스캐너 workflow의 영속 provenance. 가져온 파일과 legacy frame에는 nil이다.
    var scanSessionID: UUID?
    var scanJobID: UUID?
    var scannedAt: Date
    var filmType: FilmType
    var presetID: String?
    var params: DevelopParameters
    var imageTransform: ImageTransform
    var baseRGB: [Double]?
    /// 렌더가 잰 채널 밀도 범위 모양(R·G·B, 기하평균 1). 롤 교정의 재료다. 없으면 아직 안 쟀다.
    var rangeShapeRGB: [Double]? = nil
    var rating: Int
    var pickState: FramePickState
    var customDisplayName: String?
    var hasDevelopedOnce: Bool
    var developHistory: [DevelopHistoryEntry]
    var developSnapshots: [DevelopSnapshot]
    var sourceFrameID: UUID?
    var sourceFrameDisplayName: String?
    var virtualCopyNumber: Int?
    /// current v6 payload에 선택적으로 추가되는 Proof Copy 설정. nil이면 일반 원본/가상 사본이다.
    var proofCopyConfiguration: ProofCopyConfiguration? = nil
    // 결함 recipe는 app-owned sidecar에, 재생성 가능한 픽셀 결과는 cache TIFF에 둔다.
    // optional 필드라 기존 v1 catalog도 그대로 디코드된다.
    var cleanedRawPath: String?
    var cleanedRawEditCount: Int?
    var hasDefectEdits: Bool?
    /// 결함 기록(sidecar)의 세대. 시작할 때 기록 전체(IR 은 장당 수십 MB)를 읽지 않고도 썸네일
    /// 레시피와 기록 식별을 맞추기 위한 값이다. 기록이 진실이며, 실제로 읽을 때 대조한다.
    /// 없으면(예전 카탈로그) 시작할 때 기록을 읽어 채운다.
    var defectRecipeIdentity: DefectRecipeIdentity? = nil
    /// v4 이하에서 과거 행동을 추정하지 않는다. runtime source-of-truth 연결 전까지
    /// `init(frame:)`도 안전하게 legacyUnknown으로 기록한다.
    var userEditTracking: LibraryUserEditTracking = .legacyUnknown()
    var exportTracking: LibraryExportTracking = .legacyUnknown
    var defectReviewTracking: LibraryDefectReviewTracking = .legacyUnknown
}

extension LibraryFrameRecord {
    private enum TrackingCodingKeys: String, CodingKey {
        case userEditTracking
        case exportTracking
        case defectReviewTracking
        case appMetadataOverlay
        case proofCopyConfiguration
        case defectRecipeIdentity
        case rangeShapeRGB
    }

    /// 기존 frame payload는 frozen v4 decoder로 읽고 v5 tracking key만 별도로 강제한다.
    /// 따라서 optional/default runtime 값이 있어도 current catalog의 key 누락은 invalid다.
    init(from decoder: Decoder) throws {
        self = try LibraryFrameRecordV4(from: decoder).currentRecord
        let container = try decoder.container(keyedBy: TrackingCodingKeys.self)
        userEditTracking = try container.decode(
            LibraryUserEditTracking.self,
            forKey: .userEditTracking
        )
        exportTracking = try container.decode(
            LibraryExportTracking.self,
            forKey: .exportTracking
        )
        defectReviewTracking = try container.decode(
            LibraryDefectReviewTracking.self,
            forKey: .defectReviewTracking
        )
        appMetadataOverlay = try container.decodeIfPresent(
            AppMetadataOverlay.self,
            forKey: .appMetadataOverlay
        )
        proofCopyConfiguration = try container.decodeIfPresent(
            ProofCopyConfiguration.self,
            forKey: .proofCopyConfiguration
        )
        // 읽기 지름길일 뿐이라 이 값이 모르는 형식이어도 사진을 버리지 않는다 — 없을 때처럼 기록을 읽는다.
        defectRecipeIdentity = (try? container.decodeIfPresent(
            DefectRecipeIdentity.self,
            forKey: .defectRecipeIdentity
        )) ?? nil
        // 측정 캐시일 뿐이라 모르는 형식이면 버리고 다시 잰다.
        rangeShapeRGB = (try? container.decodeIfPresent([Double].self, forKey: .rangeShapeRGB)) ?? nil
    }
}

extension FrameSource {
    /// 카탈로그 직렬화 키(원시값 없는 enum 이라 별도 매핑).
    var storageKey: String {
        switch self {
        case .scannerTIFF: "scanner"
        case .importedFile: "imported"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "scanner": self = .scannerTIFF
        case "imported": self = .importedFile
        default: return nil
        }
    }
}

extension LibraryFrameRecord {
    @MainActor
    init(frame: ScanFrame) {
        id = frame.id
        scanIndex = frame.scanIndex
        rawScanPath = frame.rawScanURL.path
        infraredScanPath = frame.infraredScanURL?.path
        rawScanBookmarkData = frame.rawScanBookmarkData
        infraredScanBookmarkData = frame.infraredScanBookmarkData
        sourceKind = frame.sourceKind.storageKey
        storageGroup = frame.storageGroupName
        sourcePixelWidth = frame.sourcePixelWidth
        sourcePixelHeight = frame.sourcePixelHeight
        sourceResolutionDPI = frame.sourceResolutionDPI
        sourceBitDepth = frame.sourceBitDepth
        sourceMetadata = frame.sourceMetadata
        appMetadataOverlay = frame.appMetadataOverlay
        scanSessionID = frame.scanSessionID
        scanJobID = frame.scanJobID
        scannedAt = frame.scannedAt
        filmType = frame.filmType
        presetID = frame.preset?.id
        params = frame.params
        imageTransform = frame.imageTransform
        baseRGB = frame.baseRGB.map { [$0.x, $0.y, $0.z] }
        rangeShapeRGB = frame.rangeShape.map { [$0.x, $0.y, $0.z] }
        rating = frame.rating
        pickState = frame.pickState
        customDisplayName = frame.customDisplayName
        hasDevelopedOnce = frame.hasDevelopedOnce
        developHistory = frame.developHistory
        developSnapshots = frame.developSnapshots
        sourceFrameID = frame.sourceFrameID
        sourceFrameDisplayName = frame.sourceFrameDisplayName
        virtualCopyNumber = frame.virtualCopyNumber
        proofCopyConfiguration = frame.proofCopyConfiguration
        // recipe만 영속화하고 파생 픽셀은 복원 시 현재 입력 감마로 다시 만듭니다.
        cleanedRawPath = nil
        cleanedRawEditCount = nil
        hasDefectEdits = frame.defectEditsNeedRestore || !frame.defectEdits.isEmpty ? true : nil
        defectRecipeIdentity = hasDefectEdits == true ? frame.defectRecipeIdentity : nil
        let currentRecipeSHA256 = frame.currentLibraryDevelopRecipeSHA256()
        let trackingState: LibraryFrameWorkflowTrackingState
        if let currentRecipeSHA256 {
            if let existing = frame.libraryWorkflowTrackingState {
                trackingState = existing.reconciled(
                    currentRecipeSHA256: currentRecipeSHA256
                ) ?? existing
            } else {
                trackingState = .newFrame(currentRecipeSHA256: currentRecipeSHA256)
            }
        } else {
            trackingState = LibraryFrameWorkflowTrackingState(
                userEditTracking: .legacyUnknown(),
                exportTracking: frame.libraryWorkflowTrackingState?.exportTracking ?? .legacyUnknown,
                defectReviewTracking: frame.libraryWorkflowTrackingState?.defectReviewTracking
                    ?? .legacyUnknown
            )
        }
        if frame.libraryWorkflowTrackingState != trackingState {
            frame.libraryWorkflowTrackingState = trackingState
        }
        userEditTracking = trackingState.userEditTracking
        exportTracking = trackingState.exportTracking
        defectReviewTracking = trackingState.defectReviewTracking
    }

    @MainActor
    func makeFrame(presets: [LookPreset]) -> ScanFrame {
        let rawLocation = SourceBookmark.resolve(
            rawScanBookmarkData,
            fallbackURL: URL(fileURLWithPath: rawScanPath)
        )
        let infraredLocation = infraredScanPath.map { path in
            SourceBookmark.resolve(
                infraredScanBookmarkData,
                fallbackURL: URL(fileURLWithPath: path)
            )
        }
        let frame = ScanFrame(
            scanIndex: scanIndex,
            rawScanURL: rawLocation.url,
            filmType: filmType,
            infraredScanURL: infraredLocation?.url,
            rawScanBookmarkData: rawLocation.bookmarkData,
            infraredScanBookmarkData: infraredLocation?.bookmarkData,
            sourceKind: FrameSource(storageKey: sourceKind) ?? .importedFile,
            sourcePixelWidth: sourcePixelWidth,
            sourcePixelHeight: sourcePixelHeight,
            sourceResolutionDPI: sourceResolutionDPI,
            sourceBitDepth: sourceBitDepth,
            sourceMetadata: sourceMetadata,
            appMetadataOverlay: appMetadataOverlay,
            scanSessionID: scanSessionID,
            scanJobID: scanJobID,
            initialTransform: imageTransform,
            scannedAt: scannedAt,
            sourceFrameID: sourceFrameID,
            sourceFrameDisplayName: sourceFrameDisplayName,
            virtualCopyNumber: virtualCopyNumber,
            id: id,
            storageGroupName: storageGroup
        )
        frame.preset = presetID.flatMap { id in presets.first(where: { $0.id == id }) }
        frame.params = params
        frame.defectEditsNeedRestore = hasDefectEdits == true
        if hasDefectEdits == true, let defectRecipeIdentity {
            // 항목은 사진을 쓸 때 읽는다(loadDeferredDefectEdits). 그 전까지도 썸네일·기록 식별은 맞는다.
            frame.defectRecipeIdentity = defectRecipeIdentity
            frame.defectRecipeRevision = defectRecipeIdentity.revision
            frame.defectEditsLoadDeferred = true
        }
        frame.imageTransform = imageTransform
        if let baseRGB, baseRGB.count == 3 {
            frame.baseRGB = SIMD3(baseRGB[0], baseRGB[1], baseRGB[2])
        }
        if let rangeShapeRGB, rangeShapeRGB.count == 3,
           let shape = ChannelRangeCalibration.sanitized(
            SIMD3(rangeShapeRGB[0], rangeShapeRGB[1], rangeShapeRGB[2])) {
            frame.rangeShape = shape
        }
        frame.setRating(rating)
        frame.pickState = pickState
        frame.customDisplayName = customDisplayName
        frame.hasDevelopedOnce = hasDevelopedOnce
        frame.developHistory = developHistory
        frame.developSnapshots = developSnapshots
        frame.proofCopyConfiguration = proofCopyConfiguration
        frame.libraryWorkflowTrackingState = LibraryFrameWorkflowTrackingState(
            userEditTracking: userEditTracking,
            exportTracking: exportTracking,
            defectReviewTracking: defectReviewTracking
        )
        return frame
    }
}
