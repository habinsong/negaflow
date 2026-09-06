import AppKit
import Foundation
import Chromabase

extension AppModel {
    /// 디스크 그림을 먼저 모두 표시한 뒤 원본 디코드와 누락된 현상 썸네일 복구를 진행합니다.
    @discardableResult
    func loadThumbnailsFromDisk(for restoredFrames: [ScanFrame]) -> Task<Void, Never> {
        let jobs = restoredFrames.map { frame in
            (
                frame: frame,
                recipeID: frame.currentThumbnailRecipeID(),
                inputGamma: frame.params.inputGamma,
                sourceKind: frame.sourceKind,
                inputRevision: frame.cleanRawRevision,
                sourceRevision: frame.sourceLocationRevision,
                hasNewInputSettings: frame.params.inputGamma != .automatic || frame.params.baseScale != .identity,
                developedURL: thumbnailFileURL(for: frame),
                rawCacheURL: rawThumbnailFileURL(for: frame),
                previousDevelopedURL: unversionedThumbnailFileURL(for: frame, raw: false),
                previousRawURL: unversionedThumbnailFileURL(for: frame, raw: true),
                legacyURL: legacyThumbnailFileURL(for: frame),
                sourceURL: frame.rawScanURL,
                transform: frame.imageTransform,
                requiresInversion: frame.filmType.requiresInversion,
                hasDevelopedOnce: frame.hasDevelopedOnce
            )
        }
        let cache = thumbnailDiskCache
        return Task.detached(priority: .utility) {
            var rawIsMissing: [Bool] = []
            var developedIsMissing: [Bool] = []
            // 큰 TIFF의 감마 추정 때문에 뒤에 있는 캐시 그림까지 기다리게 하지 않습니다.
            for job in jobs {
                guard !Task.isCancelled else { return }
                let current = job.recipeID.flatMap { ThumbnailDiskCache.load(at: job.developedURL, matchingRecipe: $0) }
                let developed = current ?? ThumbnailDiskCache.load(at: job.developedURL)
                    ?? (job.hasNewInputSettings ? nil : ThumbnailDiskCache.load(at: job.previousDevelopedURL))
                let raw = ThumbnailDiskCache.load(at: job.rawCacheURL)
                    ?? (job.inputGamma == .automatic ? ThumbnailDiskCache.load(at: job.previousRawURL) : nil)
                let legacy = job.hasNewInputSettings ? nil : ThumbnailDiskCache.load(at: job.legacyURL)
                rawIsMissing.append(raw == nil)
                developedIsMissing.append(current == nil)
                await MainActor.run {
                    guard self.ownsFrame(job.frame), job.frame.cleanRawRevision == job.inputRevision,
                          job.frame.sourceLocationRevision == job.sourceRevision,
                          job.frame.currentThumbnailRecipeID() == job.recipeID else { return }
                    if let raw, job.frame.rawPreviewImage == nil { job.frame.rawPreviewImage = raw }
                    if job.frame.thumbnailImage == nil {
                        if let displayed = developed ?? (job.hasDevelopedOnce ? legacy : nil) {
                            job.frame.thumbnailImage = displayed
                            job.frame.thumbnailRecipeID = current == nil ? nil : job.recipeID
                        } else if !job.requiresInversion, let displayed = legacy ?? raw {
                            job.frame.thumbnailImage = displayed
                        } else if !job.hasDevelopedOnce, job.frame.rawPreviewImage == nil {
                            job.frame.rawPreviewImage = legacy
                        }
                    }
                }
            }

            var framesToDevelop: [ScanFrame] = []
            for (index, job) in jobs.enumerated() {
                guard !Task.isCancelled else { return }
                let isCurrent = await MainActor.run {
                    self.ownsFrame(job.frame) && job.frame.cleanRawRevision == job.inputRevision
                        && job.frame.sourceLocationRevision == job.sourceRevision
                        && job.frame.currentThumbnailRecipeID() == job.recipeID
                }
                guard isCurrent else { continue }
                if rawIsMissing[index], let raw = AppModel.rawThumbnailCGImage(
                    for: job.sourceURL, maxPixelSize: 360, inputGamma: job.inputGamma, sourceKind: job.sourceKind
                ) {
                    let cg = AppModel.orientedThumbnail(raw, transform: job.transform)
                    await MainActor.run {
                        guard self.ownsFrame(job.frame), job.frame.cleanRawRevision == job.inputRevision,
                              job.frame.sourceLocationRevision == job.sourceRevision,
                              job.frame.currentThumbnailRecipeID() == job.recipeID else { return }
                        // 늦게 끝난 원본 복원이 최신 현상 프리뷰를 덮지 않습니다.
                        if job.frame.rawPreviewImage == nil {
                            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                            job.frame.rawPreviewImage = image
                            job.frame.rawPreviewTransform = job.transform
                            if !job.requiresInversion, job.frame.thumbnailImage == nil {
                                job.frame.thumbnailImage = image
                                job.frame.thumbnailTransform = job.transform
                            }
                        }
                        cache.store(cg, for: job.frame.id, at: job.rawCacheURL)
                    }
                }
                if (job.hasDevelopedOnce || job.hasNewInputSettings), developedIsMissing[index],
                   FileManager.default.fileExists(atPath: job.sourceURL.path) {
                    framesToDevelop.append(job.frame)
                }
            }
            guard !Task.isCancelled, !framesToDevelop.isEmpty else { return }
            let frames = framesToDevelop
            let task = await MainActor.run { self.developImportedFramesSequentially(frames) }
            await task.value
        }
    }
}
