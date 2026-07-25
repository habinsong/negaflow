import Foundation
import CoreImage
import CoreGraphics
import Chromabase

// MARK: - 필름 베이스 스포이드 (film base picker)
//
// 캔버스에서 미노광 베이스(프레임 사이/가장자리)를 클릭하면 반전 전 raw 를 영역 평균으로
// 샘플해 manualBaseRGB(절대 Dmin)로 설정한다. 업계 D-min picker 와 동일한 절대값 의미론.
extension AppModel {
    /// - Parameter baseUnit: 변형(회전/플립/크롭) 전 raw 정규좌표(0...1, y-down).
    ///   CanvasView 가 표시 좌표를 `ImageTransform.displayUnitToBase` 로 역변환해 전달한다.
    func pickFilmBase(at baseUnit: CGPoint, frame: ScanFrame) {
        guard ownsFrame(frame) else { return }
        let point = CGPoint(x: min(max(baseUnit.x, 0), 1), y: min(max(baseUnit.y, 0), 1))
        Task { [weak self] in
            guard let self,
                  await self.prepareCleanedRawForConsumption(frame),
                  self.ownsFrame(frame) else { return }
            let expectedDefectIdentity = frame.boundDefectRecipeIdentity
            let preloadedRaw = frame.identityMatchedCleanedRawImage
            let cleanedRawURL = frame.identityMatchedCleanedRawDiskURL
            let requiresCleanedRaw = frame.requiresCleanedRawForActiveDefects
            let frameID = frame.id
            let rawScanURL = frame.rawScanURL
            let sourceKind = frame.sourceKind
            let cleanRawRevision = frame.cleanRawRevision
            let neutralBase = frame.filmType == .bwNegative
            let sampled = await Task.detached(priority: .userInitiated) { () -> SIMD3<Double>? in
                guard let raw = Self.loadRawForBasePick(
                    preloadedRaw: preloadedRaw,
                    cleanedRawURL: cleanedRawURL,
                    cleanedRawFrameID: expectedDefectIdentity == nil ? nil : frameID,
                    cleanedRawIdentity: expectedDefectIdentity,
                    requiresCleanedRaw: requiresCleanedRaw,
                    rawScanURL: rawScanURL,
                    sourceKind: sourceKind
                ) else { return nil }
                return FilmBasePicker.sample(in: raw, atUnit: point, neutralBase: neutralBase)
            }.value
            // 픽 유효성은 raw 픽셀 상태에만 의존한다(cleanRawRevision + 결함 identity).
            // 과거의 params 전체 동일성 가드는 샘플링(대형 파일 디코드) 중 무관한 슬라이더
            // 조정·연속 픽에도 결과를 조용히 버려 "찍었는데 안 변함"의 원인이었다.
            guard self.ownsFrame(frame),
                  frame.cleanRawRevision == cleanRawRevision,
                  frame.boundDefectRecipeIdentity == expectedDefectIdentity else { return }
            guard let sampled else {
                self.statusMessage = self.text(AppLocalizedPhrase.filmBaseSampleFailed)
                return
            }
            frame.updateParams {
                $0.manualBaseRGB = sampled
                $0.baseEstimationMode = .manual
            }
            self.statusMessage = self.text(AppLocalizedPhrase.filmBasePickedFormat, sampled.x, sampled.y, sampled.z)
            self.requestDevelop(frame)
        }
    }

    /// 현상 렌더러(resolveRawInput)와 동일한 우선순위로 반전 전 raw 를 로드한다.
    nonisolated static func loadRawForBasePick(
        preloadedRaw: CGImage?,
        cleanedRawURL: URL?,
        cleanedRawFrameID: UUID?,
        cleanedRawIdentity: DefectRecipeIdentity?,
        requiresCleanedRaw: Bool,
        rawScanURL: URL,
        sourceKind: FrameSource
    ) -> CIImage? {
        if let pre = preloadedRaw {
            let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
            return CIImage(cgImage: pre, options: [.colorSpace: linear])
        }
        if let url = cleanedRawURL,
           let frameID = cleanedRawFrameID,
           let identity = cleanedRawIdentity,
           identity.sourceIdentity != nil,
           CleanedRawCacheFile.isOwnedCacheURL(url, frameID: frameID),
           let ci = ImageLoader.loadScannerTIFF(url) {
            return ci
        }
        if requiresCleanedRaw { return nil }
        let engine = ChromabaseEngine()
        switch sourceKind {
        case .scannerTIFF:  return engine.loadScannerImage(rawScanURL)
        case .importedFile: return engine.loadImportedImage(rawScanURL)
        }
    }
}
