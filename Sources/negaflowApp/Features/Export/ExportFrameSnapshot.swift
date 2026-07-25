import Foundation
import CoreGraphics
import ScannerKit
import Chromabase

struct ExportFrameSnapshot: @unchecked Sendable {
    let rawScanURL: URL
    /// Snapshot 생성 전에 계산한 원본 byte identity. 모든 decode와 산출물은 이 세대에 묶인다.
    let sourceIdentity: RenderManifest.SourceIdentity
    // raw 입력 출처(로더 분기). 기본은 스캐너 TIFF.
    var sourceKind: FrameSource = .scannerTIFF
    // 결함 제거된 raw(메모리 CGImage). 있으면 이걸 입력으로 써서 결함 제거가 export에도 반영된다.
    let preloadedRaw: CGImage?
    // 메모리 적재본이 없을 때의 디스크 백킹(결함 제거된 raw TIFF).
    let cleanedRawURL: URL?
    /// 활성 결함 recipe가 있어 source raw로의 fallback을 허용할 수 없는 snapshot.
    let requiresCleanedRaw: Bool
    let outputURL: URL
    let format: ExportFormat
    let filmType: FilmType
    let params: DevelopParameters
    let baseMode: DevelopParameters.BaseMode
    let manualBaseRGB: SIMD3<Double>?
    let cachedBase: FilmBase?
    let scannerMake: String?
    let scannerDeviceModel: String?
    let scannerModel: String?
    let resolutionDPI: Int?
    let sourceBitDepth: Int?
    let backendUsed: String?
    let presetName: String?
    let scannerProfileID: String?
    let cropRect: SIMD4<Double>?
    let virtualCopy: Sidecar.VirtualCopyInfo?
    let rating: Int
    let pickState: FramePickState
    let developHistory: [DevelopHistoryEntry]
    let developSnapshots: [Sidecar.DevelopSnapshotRecord]
    let sourceDate: Date?
    let metadataDate: Date
    let appVersion: String
    let rendererVersion: String
    let writeSidecar: Bool
    let writeMainFlatMaster: Bool
    let writeOriginalRaw: Bool
    let exportOptions: ExportOptions
    /// PRINT 산출물에만 쓰는 exact printer-class ICC. working image에는 적용하지 않는다.
    let printerOutputProfile: ICCOutputProfileSnapshot?
    let printComposition: PrintCompositionSettings?
    let exportRecipeIdentity: ExportRecipeIdentity?
    let appMetadataOverlay: AppMetadataOverlay?
    let sourceMetadataSHA256: String?
    let cleanedRawFrameID: UUID?
    let cleanedRawIdentity: DefectRecipeIdentity?
}

struct ExportFrameResult: @unchecked Sendable {
    let commitTransactionID: UUID
    let base: FilmBase?
    let mainFlatMasterURL: URL?
    let originalRawURL: URL?
    let artifactURLs: [URL]
}
