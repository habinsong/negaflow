import CoreImage
import Chromabase

extension DevelopFrameRenderer {
    /// 저장된 레이어를 새 감마의 원본에 다시 계산합니다. 기존 patch/cleaned raw는 섞지 않습니다.
    static func inputGammaDefectPreview(_ snapshot: DevelopFrameSnapshot) throws -> RenderInput {
        guard !snapshot.inputGammaPreviewDefects.isEmpty else { throw DevelopFrameRenderError.cleanedRawPending }
        var image: CIImage
        if let source = snapshot.inputGammaPreviewSource, source.matches(snapshot.rawScanURL) {
            image = try source.image(gamma: snapshot.params.inputGamma, maxDimension: 0,
                applyOrientation: snapshot.sourceKind == .importedFile)
        } else if snapshot.sourceKind == .importedFile {
            image = try ImageLoader.loadImportedDecoded(snapshot.rawScanURL, inputGamma: snapshot.params.inputGamma).image
        } else {
            image = try ImageLoader.loadScannerTIFFDecoded(snapshot.rawScanURL, inputGamma: snapshot.params.inputGamma).image
        }
        let width = Int(image.extent.width), height = Int(image.extent.height)
        for item in snapshot.inputGammaPreviewDefects where item.enabled && item.strength > 1e-3 {
            try Task.checkCancellation()
            guard let patches = computeDefectPatches(item.edit, base: image, pixelWidth: width,
                pixelHeight: height, shouldCancel: { Task.isCancelled }) else {
                throw DevelopFrameRenderError.cleanedRawPending
            }
            for patch in patches {
                image = patch.composited(over: image, strength: item.strength, colorSpace: linearColorSpace)
            }
        }
        return RenderInput(image: displayProxy(image, maxDimension: snapshot.proxyMaxDimension), generatedPreviewRaw: nil)
    }
}
