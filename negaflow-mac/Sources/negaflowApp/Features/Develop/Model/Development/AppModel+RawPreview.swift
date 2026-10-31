import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    func loadRawPreview(_ frame: ScanFrame) {
        guard ownsFrame(frame) else { return }
        let transformRevision = frame.transformRevision
        Task {
            guard await prepareCleanedRawForConsumption(frame),
                  ownsFrame(frame),
                  frame.transformRevision == transformRevision else { return }
            let cleanRawRevision = frame.cleanRawRevision
            let cleanedIdentity = frame.boundDefectRecipeIdentity
            let snapshot = DevelopFrameSnapshot(
                rawScanURL: frame.rawScanURL,
                sourceKind: frame.sourceKind,
                preloadedRaw: frame.identityMatchedCleanedRawImage,
                cleanedRawURL: frame.identityMatchedCleanedRawDiskURL,
                filmType: frame.filmType,
                params: frame.params,
                preset: frame.preset,
                imageTransform: frame.imageTransform,
                cachedBase: nil,
                baseKey: FilmBaseCacheKey(
                    filmType: frame.filmType,
                    mode: frame.params.baseEstimationMode,
                    manualBaseRGB: frame.params.manualBaseRGB,
                    filmStockDminID: frame.params.filmStockDminID,
                    lightSourceProfileID: frame.params.lightSourceProfileID,
                    imageTransform: frame.imageTransform
                ),
                needsRawPreview: true,
                needsNeutralPreview: false,
                needsDebugPreviews: false,
                cleanedRawFrameID: cleanedIdentity == nil ? nil : frame.id,
                cleanedRawIdentity: cleanedIdentity,
                requiresCleanedRaw: frame.requiresCleanedRawForActiveDefects
            )
            let rawPreview = try? await Task.detached(priority: .utility) {
                try DevelopFrameRenderer.renderRawPreview(snapshot)
            }.value
            guard let rawPreview,
                  self.ownsFrame(frame),
                  frame.transformRevision == transformRevision,
                  frame.cleanRawRevision == cleanRawRevision,
                  frame.boundDefectRecipeIdentity == cleanedIdentity else { return }
            frame.rawPreviewImage = NSImage(
                cgImage: rawPreview,
                size: NSSize(width: rawPreview.width, height: rawPreview.height)
            )
            frame.rawPreviewTransform = snapshot.imageTransform
        }
    }

    /// 정착 패스가 미룬 원본 미리보기. 원본을 다시 읽지 않고 방금 굳힌 정착 입력에서 만든다.
    func renderDeferredRawPreview(_ frame: ScanFrame, settled: DevelopFrameSnapshot) {
        guard ownsFrame(frame) else { return }
        var snapshot = settled
        snapshot.preloadedFullPreviewRaw = cachedSettledPreviewRaw(for: frame) ?? settled.preloadedFullPreviewRaw
        let transformRevision = frame.transformRevision
        let cleanRawRevision = frame.cleanRawRevision
        let transform = snapshot.imageTransform
        let prepared = snapshot
        Task {
            let pair = try? await Task.detached(priority: .utility) {
                try DevelopFrameRenderer.renderRawPreviewPair(prepared)
            }.value
            guard let pair, ownsFrame(frame),
                  frame.transformRevision == transformRevision,
                  frame.cleanRawRevision == cleanRawRevision,
                  frame.imageTransform == transform else { return }
            frame.cachedRawBase = pair.base
            frame.rawPreviewImage = NSImage(
                cgImage: pair.transformed,
                size: NSSize(width: pair.transformed.width, height: pair.transformed.height)
            )
            frame.rawPreviewTransform = transform
        }
    }
}
