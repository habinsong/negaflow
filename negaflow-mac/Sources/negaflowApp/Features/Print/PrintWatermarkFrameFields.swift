import AppKit
import Chromabase
import Foundation

extension ScanFrame {
    /// 필름스트립 썸네일이 지금 레시피·회전·자르기로 만든 것이면 그 이미지. 블러 바탕과 히스토그램은
    /// 큰 화면 이미지 대신 이것을 쓴다(작은 이미지로 충분한 일이다). 오래됐으면 nil.
    var watermarkReferenceImage: CGImage? {
        guard let thumbnail = thumbnailImage,
              thumbnailTransform == imageTransform,
              let recipe = thumbnailRecipeID,
              recipe == currentThumbnailRecipeID() else { return nil }
        return thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

extension PrintCompositionSettings {
    @MainActor
    func resolvingWatermarkLogo() -> PrintCompositionSettings {
        guard let watermark else { return self }
        var result = self
        // 로고는 저장된 경로에서 이 자리에서 읽는다(지워졌으면 로고만 빠진다).
        result.watermark = watermark.resolvingLogo()
        return result
    }
}
