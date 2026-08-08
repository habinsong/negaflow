import SwiftUI
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    func prepareCleanedRawForConsumption(_ frame: ScanFrame) async -> Bool {
        guard ownsFrame(frame) else { return false }
        guard frame.requiresCleanedRawForActiveDefects else { return true }
        guard let expectedIdentity = frame.boundDefectRecipeIdentity,
              let expectedSourceIdentity = expectedIdentity.sourceIdentity else {
            return false
        }
        let rawURL = frame.rawScanURL
        let revision = frame.cleanRawRevision
        let verification: CaptureFileVerificationResult = await Task.detached(priority: .utility) {
            guard let currentIdentity = try? AppModel.defectSourceIdentity(for: rawURL) else {
                return .unavailable
            }
            return currentIdentity == expectedSourceIdentity ? .match : .mismatch
        }.value
        guard ownsFrame(frame),
              frame.rawScanURL == rawURL,
              frame.cleanRawRevision == revision,
              frame.defectRecipeIdentity == expectedIdentity else {
            return false
        }
        guard verification != .unavailable else { return false }
        guard verification == .match else {
            recoverFromChangedDefectSource(
                frame,
                revision: revision,
                expectedRecipeIdentity: expectedIdentity,
                quiet: false
            )
            return false
        }
        return true
    }

    func cleanedRawBuildIsCurrent(
        _ frame: ScanFrame,
        revision: Int,
        recipeIdentity: DefectRecipeIdentity
    ) -> Bool {
        ownsFrame(frame)
            && frame.cleanRawRevision == revision
            && frame.defectRecipeIdentity == recipeIdentity
    }

    func recoverFromChangedDefectSource(
        _ frame: ScanFrame,
        revision: Int,
        expectedRecipeIdentity: DefectRecipeIdentity,
        quiet: Bool
    ) {
        guard ownsFrame(frame),
              frame.cleanRawRevision == revision,
              frame.defectRecipeIdentity == expectedRecipeIdentity else { return }

        frame.developRevision += 1
        frame.transformRevision += 1
        frame.defectDetectRevision += 1
        frame.cleanRawRevision += 1
        frame.transformTask?.cancel()
        frame.cleanRawTask?.cancel()
        frame.cleanRawTask = nil
        frame.cleanedRawPersistTask?.cancel()
        frame.cleanedRawPersistTask = nil
        frame.isRemovingDefects = false
        cancelInfraredClean(frame)
        cancelRegionDefect(frame)
        if let cacheURL = frame.cleanedRawDiskURL,
           CleanedRawCacheFile.isOwnedCacheURL(cacheURL, frameID: frame.id) {
            try? FileManager.default.removeItem(at: cacheURL)
        }
        frame.cleanedRawImage = nil
        frame.cleanedRawCanvas = nil
        frame.cleanedRawMemoryIdentity = nil
        frame.cleanedRawAppliedStamps = []
        frame.cleanedRawDiskURL = nil
        frame.cleanedRawDiskIdentity = nil
        frame.cleanedRawEditCount = 0
        invalidatePreviousBase(frame)
        frame.stripDefectPatchCaches()
        frameCacheManager.removeCleanedRawResident(frame)
        evictDevelopBuffers(frame)
        frame.cachedBaseKey = nil
        frame.cachedBase = nil
        frame.hasDevelopedOnce = false

        guard invalidateDefectRecipeSourceBindingForRelink(frame) else {
            if !quiet {
                statusMessage = text(AppLocalizedPhrase.removingDefectsFailedStatus)
            }
            return
        }
        rebuildCleanedRaw(frame)
    }

    func finishFailedCleanedRawBuild(
        _ frame: ScanFrame,
        revision: Int,
        quiet: Bool
    ) {
        guard ownsFrame(frame), frame.cleanRawRevision == revision else { return }
        if !quiet {
            // 실패 시 검출 결과를 남겨 사용자가 다시 제거할 수 있게 하고, busy 상태만 해제한다.
            frame.defectIsRemoving = false
            frame.isRemovingDefects = false
            if !Task.isCancelled {
                statusMessage = text(AppLocalizedPhrase.removingDefectsFailedStatus)
            }
        }
        frame.cleanRawTask = nil
    }

    /// cleaned raw가 필요한 작업은 메모리 또는 검증된 디스크 백킹을 명시적으로 선택한다.
    /// cache가 사라졌다면 recipe를 이용한 rebuild는 handleSelectedFrameChange가 담당한다.

}
