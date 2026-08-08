import AppKit
import Chromabase
import CoreImage
import Foundation

// 종료 시 결함 편집을 이미지에 굽는다: cleaned raw가 프레임의 원본이 되고(스캔=제자리 교체,
// 가져오기·공유 원본=앱 소유 사본으로 리포인트), 기록(defectEdits/undo/recipe)은 폐기한다.
// 다음 실행은 구워진 원본을 그대로 로드하므로 기록 복원·검증·재빌드가 전혀 없다.
extension AppModel {
    /// 결함 편집이 있는 모든 프레임을 굽는다. 실패한 프레임이 있으면 false를 돌려
    /// 종료를 보류한다(적용된 편집 유실 방지). 성공 시 스테이징 캐시도 함께 정리한다.
    func bakeDefectEditsForTermination() async -> Bool {
        for frame in frames where !frame.isPreviewScan {
            if frame.defectEdits.isEmpty {
                removeCleanedRawStaging(frame)
                continue
            }
            guard await bakeDefectEdits(into: frame) else { return false }
        }
        return true
    }

    private func bakeDefectEdits(into frame: ScanFrame) async -> Bool {
        // 진행 중 상태 확정: live 지문 워커·제스처를 닫고, 실행 중인 빌드를 기다린다.
        cancelPendingDefectRecipeRefresh(frame)
        if frame.defectGestureRecipeAdvanced {
            _ = refreshDefectRecipeState(frame, advanceRevision: true, persist: false)
        }
        if let task = frame.cleanRawTask {
            await task.value
        }
        // 디스크 persist 는 취소하고 끝을 기다린다 — 메모리/인라인 합성이 최종 픽셀을 책임지고,
        // 늦게 커밋된 스테이징이 정리(removeCleanedRawStaging) 뒤에 되살아나지 않게 한다.
        if let persist = frame.cleanedRawPersistTask {
            persist.cancel()
            await persist.value
            frame.cleanedRawPersistTask = nil
        }
        guard ownsFrame(frame) else { return true }
        guard frame.requiresCleanedRawForActiveDefects else {
            // 켜진 레이어가 없으면 원본이 곧 결과다 — 기록만 폐기한다.
            clearDefectStateAfterBake(frame)
            return true
        }

        // 최종 픽셀 확보: 메모리 → 디스크 스테이징 → (드물게) 인라인 재계산.
        let identity = frame.defectRecipeIdentity
        var preloaded: CGImage?
        if let cg = frame.cleanedRawImage, identity != nil,
           frame.cleanedRawMemoryIdentity == identity {
            preloaded = cg
        }
        var stagedURL: URL?
        if preloaded == nil,
           let url = frame.cleanedRawDiskURL, identity != nil,
           frame.cleanedRawDiskIdentity == identity,
           CleanedRawCacheFile.isOwnedCacheURL(url, frameID: frame.id) {
            stagedURL = url
        }

        let rawURL = frame.rawScanURL
        let sourceKind = frame.sourceKind
        let edits = frame.defectEdits
        // 같은 원본을 다른 프레임(가상 복사본 등)이 공유하면 제자리 교체가 그 프레임의
        // 픽셀까지 바꾸므로, 이 프레임만 앱 소유 사본으로 리포인트한다.
        let sharesRaw = frames.contains {
            $0 !== frame && $0.rawScanURL.standardizedFileURL.path
                == rawURL.standardizedFileURL.path
        }
        let inPlace = sourceKind == .scannerTIFF && !sharesRaw
        let destination = inPlace ? nil : makeBakedCopyURL(for: frame)

        let bakedURL: URL? = await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                let finalCG: CGImage?
                if let preloaded {
                    finalCG = preloaded
                } else if let stagedURL {
                    finalCG = decodeCleanedRaw(stagedURL)
                } else {
                    finalCG = Self.composeCleanedRawForBake(
                        rawURL: rawURL,
                        sourceKind: sourceKind,
                        edits: edits
                    )
                }
                guard let finalCG else { return nil }
                if let destination {
                    return ImageLoader.saveScannerTIFF(finalCG, to: destination)
                        ? destination
                        : nil
                }
                // 제자리 교체: 같은 디렉터리에 임시 저장 후 원자적으로 바꾼다.
                let tempURL = rawURL.deletingLastPathComponent()
                    .appendingPathComponent(".negaflow-bake-\(UUID().uuidString).tiff")
                guard ImageLoader.saveScannerTIFF(finalCG, to: tempURL) else { return nil }
                do {
                    _ = try FileManager.default.replaceItemAt(rawURL, withItemAt: tempURL)
                    return rawURL
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                    return nil
                }
            }
        }.value

        guard ownsFrame(frame) else { return true }
        guard let bakedURL else { return false }
        if !inPlace {
            frame.updateSourceLocation(
                rawURL: bakedURL,
                infraredURL: frame.infraredScanURL,
                sourceMetadata: frame.sourceMetadata
            )
        }
        clearDefectStateAfterBake(frame)
        dirtyLibraryFrameRecordIDs.insert(frame.id)
        return true
    }

    /// 리포인트용 앱 소유 사본 경로(스캔 폴더, 프레임 id로 유일).
    private func makeBakedCopyURL(for frame: ScanFrame) -> URL {
        let directory = diskStorage.scansURL
        _ = DiskStorageStore.ensureDirectory(directory)
        let stem = frame.rawScanURL.deletingPathExtension().lastPathComponent
        let suffix = frame.id.uuidString.prefix(8)
        return directory.appendingPathComponent("\(stem)-cleaned-\(suffix).tiff")
    }

    private func clearDefectStateAfterBake(_ frame: ScanFrame) {
        frame.defectEdits = []
        frame.defectEditUndoStack = []
        frame.defectRecipeIdentity = nil
        frame.defectRecipeRevision = 0
        frame.defectGestureRecipeAdvanced = false
        frame.defectGestureUndoPushed = false
        frame.defectGestureSourceIdentity = nil
        frame.defectMaskPreviewID = nil
        frame.cleanedRawImage = nil
        frame.cleanedRawCanvas = nil
        frame.cleanedRawMemoryIdentity = nil
        frame.cleanedRawAppliedStamps = []
        frame.cleanedRawEditCount = 0
        invalidatePreviousBase(frame)
        removeCleanedRawStaging(frame)
        frameCacheManager.removeCleanedRawResident(frame)
        updateDefectReviewTracking(frame, identity: nil)
    }

    private func removeCleanedRawStaging(_ frame: ScanFrame) {
        frame.cleanedRawPersistTask?.cancel()
        frame.cleanedRawPersistTask = nil
        if let url = frame.cleanedRawDiskURL,
           CleanedRawCacheFile.isOwnedCacheURL(url, frameID: frame.id) {
            try? FileManager.default.removeItem(at: url)
        }
        frame.cleanedRawDiskURL = nil
        frame.cleanedRawDiskIdentity = nil
    }

    /// 메모리/스테이징이 모두 없을 때의 마지막 수단 — 원본을 디코드해 편집을 순차 적용한다.
    /// runCleanedRawBuild와 같은 합성 규칙(켜진 레이어만, 캐시 패치 재사용, 마지막 1회 flatten).
    nonisolated private static func composeCleanedRawForBake(
        rawURL: URL,
        sourceKind: FrameSource,
        edits: [DefectEditItem]
    ) -> CGImage? {
        let engine = ChromabaseEngine()
        let rawCI = sourceKind == .importedFile
            ? engine.loadImportedImage(rawURL)
            : engine.loadScannerImage(rawURL)
        guard let rawCI,
              let inputCG = cleanedRawContext.createCGImage(
                  rawCI, from: rawCI.extent,
                  format: .RGBA16, colorSpace: linearColorSpace
              ) else { return nil }
        var working = CIImage(cgImage: inputCG, options: [.colorSpace: linearColorSpace])
        let workingCG = inputCG
        var dirty = false
        for item in edits {
            guard item.enabled, item.strength > 1e-3 else { continue }
            let patches: [DefectPatch]
            if let cached = item.cachedPatches {
                patches = cached
            } else {
                // 캐시 미스 패치는 체인에서 국소 창만 렌더해 계산한다(빌드 경로와 동일 규칙) —
                // 레이어마다 풀해상도 flatten 을 만들지 않는다.
                guard let fresh = computeDefectPatches(
                    item.edit, base: working,
                    pixelWidth: inputCG.width, pixelHeight: inputCG.height,
                    shouldCancel: { false }
                ) else { return nil }
                patches = fresh
            }
            for p in patches {
                working = p.composited(
                    over: working, strength: item.strength, colorSpace: linearColorSpace
                )
                dirty = true
            }
        }
        guard dirty else { return workingCG }
        return cleanedRawContext.createCGImage(
            working, from: working.extent,
            format: .RGBA16, colorSpace: linearColorSpace
        )
    }
}
