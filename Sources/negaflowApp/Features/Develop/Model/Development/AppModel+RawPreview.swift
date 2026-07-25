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
                    lightSourceProfileID: frame.params.lightSourceProfileID
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
}
