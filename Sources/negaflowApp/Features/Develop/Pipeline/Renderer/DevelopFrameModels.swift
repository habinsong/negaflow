import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit
import Metal

struct DevelopFrameSnapshot: @unchecked Sendable {
    let rawScanURL: URL
    // raw 입력 출처(로더 분기). 기본은 스캐너 TIFF.
    var sourceKind: FrameSource = .scannerTIFF
    // 결함 제거된 raw(메모리 CGImage). 있으면 이걸 입력으로 써서 원본 TIFF를 재디코딩하지 않는다.
    let preloadedRaw: CGImage?
    var preloadedPreviewRaw: DevelopFramePreviewRaw? = nil
    // 요청 치수의 프록시 캐시가 없을 때 GPU 다운스케일 소스로 쓸 정착(풀) raw 프록시.
    // 거대한 원본 TIFF를 디스크에서 다시 썸네일 디코딩하는 것보다 훨씬 빠르다.
    var preloadedFullPreviewRaw: DevelopFramePreviewRaw? = nil
    // 메모리 적재본이 없을 때의 디스크 백킹(결함 제거된 raw TIFF). 그래도 결함 제거가 유지된다.
    let cleanedRawURL: URL?
    let filmType: FilmType
    let params: DevelopParameters
    let preset: LookPreset?
    let imageTransform: ImageTransform
    let cachedBase: FilmBase?
    let baseKey: FilmBaseCacheKey
    let needsRawPreview: Bool
    let needsNeutralPreview: Bool
    var needsMainPreview: Bool = false
    let needsDebugPreviews: Bool
    var softProof: SoftProofSettings = .disabled
    var softProofRevision: UInt64 = 0
    var destinationGamutWarningEnabled: Bool = false
    var clippingOverlayEnabled: Bool = false
    var needsPixelSamplerBase: Bool = false
    // 현상 프록시 긴 변 상한. 인터랙티브(드래그 중) 패스는 작게, 정착(settle) 패스는 풀해상도로.
    var proxyMaxDimension: CGFloat = DevelopFrameRenderer.fullMaxDimension
    // 썸네일만 생성(인터랙티브 패스에서 부가 비용 없이 스트립용 썸네일 확보).
    var needsThumbnail: Bool = true
    /// 제품 runtime은 아래 세 값을 함께 채운다. legacy 단위 테스트 snapshot은 nil/false 기본값으로
    /// 기존 source fallback 계약을 유지한다.
    var cleanedRawFrameID: UUID? = nil
    var cleanedRawIdentity: DefectRecipeIdentity? = nil
    var requiresCleanedRaw: Bool = false
}

struct DevelopFrameRenderResult: @unchecked Sendable {
    let base: FilmBase?
    let rawPreview: CGImage?
    let rawBase: CGImage?          // 변형 전 raw proxy (fast 회전/크롭용 캐시)
    let neutralPreview: CGImage?   // 무보정 현상본 (Before 비교용)
    let neutralBase: CGImage?      // 변형 전 무보정 현상본 (fast 회전/크롭용 캐시)
    let mainPreview: CGImage?      // 현재 조정에서 현상 타깃만 MAIN으로 적용한 비교본
    let mainBase: CGImage?         // 변형 전 MAIN 비교본
    let developed: CGImage
    let developedBase: CGImage     // 변형 전 현상 결과 (fast 회전/크롭용 캐시)
    let workingBase: CGImage?      // 변형 전, soft-proof 미적용 sampler 전용 캐시
    let clippingOverlay: CGImage?
    let clippingOverlayBase: CGImage?
    let destinationGamutOverlay: CGImage?
    let destinationGamutOverlayBase: CGImage?
    let thumbnailBase: CGImage?    // 변형 전·soft-proof 미적용 경량 썸네일 캐시
    let thumbnail: CGImage?        // 필름스트립용 경량 썸네일(긴 변 ~360px)
    let debugPreviews: [DevelopDebugPreview]
    let previewRaw: DevelopFramePreviewRaw?
}

struct DevelopFrameFastPreviewResult: @unchecked Sendable {
    let preview: CGImage
    let thumbnail: CGImage?
    let previewRaw: DevelopFramePreviewRaw?
}

struct DevelopFramePreviewRaw: @unchecked Sendable {
    let image: CGImage
    let usesLinearSRGB: Bool
}

struct DevelopDebugPreview: @unchecked Sendable {
    let stage: DevelopDebugStage
    let image: CGImage
    let metrics: DevelopDebugMetrics?
}

enum DevelopFrameRenderError: Error {
    case loadFailed
    case rawPreviewFailed
    case developedFailed
}
