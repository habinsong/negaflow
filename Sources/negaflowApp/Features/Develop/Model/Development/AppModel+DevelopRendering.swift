import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    func renderLatestDevelopment(
        for frame: ScanFrame,
        preserveThumbnail: Bool,
        selectionBoundFrameID: UUID? = nil
    ) async {
        let trace = AppDiagnostics.start(.developFrame, category: .develop)
        defer { trace.finish() }
        guard developmentRequestIsCurrent(frame, selectionBoundFrameID: selectionBoundFrameID) else {
            developController.endFrame(frame)
            developController.releaseDevelopSlot()
            return
        }
        frame.isDeveloping = true
        developController.developBegan()
        defer {
            frame.isDeveloping = false
            developController.endFrame(frame)
            developController.developEnded()
            developController.releaseDevelopSlot()
        }
        var revision = frame.developRevision

        while true {
            guard developmentRequestIsCurrent(frame, selectionBoundFrameID: selectionBoundFrameID) else { return }
            let baseKey = FilmBaseCacheKey(
                filmType: frame.filmType,
                mode: frame.params.baseEstimationMode,
                manualBaseRGB: frame.params.manualBaseRGB,
                filmStockDminID: frame.params.filmStockDminID,
                lightSourceProfileID: frame.params.lightSourceProfileID
            )

            // ── 패스 1: 인터랙티브(표시 크기 적응형 프록시, 발색 결과만). 캔버스가 실제로 쓰는
            //    디바이스 픽셀 이상으로 렌더해 정착 패스와 화면상 선명도가 같다(해상도 펌핑 없음).
            //    변형-전 캐시(cachedDevelopedBase)나 비교/디버그 프리뷰는 만들지 않는다(정착 패스에서 채운다).
            let interactiveDimension = DevelopFrameRenderer.interactiveProxyDimension(
                displayTargetPixels: canvasDisplayTargetPixels
            )
            // 스냅샷이 소비하는 cleaned raw 세대 — 발행 시 displayedCleanRawRevision 에 기록해
            // 결함 제거 스피너가 "제거가 보이는 시점"에 끝나게 한다.
            let interactiveCleanRawRevision = frame.cleanRawRevision
            let interactive = makeSnapshot(
                for: frame, baseKey: baseKey,
                needsRawPreview: false, needsNeutralPreview: false, needsDebugPreviews: false,
                needsThumbnail: frame.thumbnailImage == nil,
                proxyMaxDimension: interactiveDimension
            )
            developController.updateProcessingDetail(
                interactive: true,
                proxyPixels: Int(interactiveDimension),
                isScanning: isScanning,
                language: appLanguage
            )
            do {
                let fast = try await renderDevelopmentSnapshot(interactive)
                guard developmentRequestIsCurrent(frame, selectionBoundFrameID: selectionBoundFrameID) else { return }
                guard softProofRenderRequestIsCurrent(interactive) else {
                    revision = frame.developRevision
                    continue
                }
                guard frame.developRevision == revision else {
                    revision = frame.developRevision
                    continue
                }
                applyBaseCache(fast, to: frame, baseKey: baseKey)
                applyPreviewRawCache(fast, to: frame, maxDimension: interactive.proxyMaxDimension)
                frame.noteDevelopedDisplaySize(
                    CGSize(width: fast.developed.width, height: fast.developed.height),
                    authoritative: interactive.proxyMaxDimension >= DevelopFrameRenderer.fullMaxDimension - 0.5
                )
                frame.developedImage = NSImage(
                    cgImage: fast.developed,
                    size: NSSize(width: fast.developed.width, height: fast.developed.height)
                )
                frame.clippingOverlayImage = fast.clippingOverlay.map {
                    NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
                }
                frame.destinationGamutOverlayImage = fast.destinationGamutOverlay.map {
                    NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
                }
                frame.developedPreviewTransform = interactive.imageTransform
                frame.displayedSoftProofRevision = interactive.softProofRevision
                if let thumbnailBase = fast.thumbnailBase {
                    frame.cachedThumbnailBase = thumbnailBase
                }
                if let thumb = fast.thumbnail {
                    frame.thumbnailImage = NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
                }
                frame.hasDevelopedOnce = true
                frame.displayedCleanRawRevision = max(
                    frame.displayedCleanRawRevision, interactiveCleanRawRevision
                )
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                trace.recordError(error)
                developFailed(frame, revision: revision)
                if frame.developRevision == revision { return }
                revision = frame.developRevision
                continue
            }
            // 인터랙티브 후 리비전이 바뀌었으면(드래그 진행) 즉시 다음 인터랙티브로 — 라이브 갱신 유지.
            guard frame.developRevision == revision else {
                revision = frame.developRevision
                continue
            }
            // 정착 감지: 추가 편집 없이 settle 윈도가 지나야 풀해상도로 마무리. 짧게 폴링해 새 편집이
            // 오면 즉시 인터랙티브로 복귀(라이브 끊김 없음). 무거운 3600px 렌더를 드래그 경로에서 제외해
            // 연속 렌더로 인한 GPU(IOSurface) 누적·블랭크 렌더를 막는다.
            if !(await waitForDevelopSettle(frame, revision: revision)) {
                guard developmentRequestIsCurrent(frame, selectionBoundFrameID: selectionBoundFrameID) else { return }
                revision = frame.developRevision
                continue
            }
            guard developmentRequestIsCurrent(frame, selectionBoundFrameID: selectionBoundFrameID) else { return }

            // ── 패스 2: 풀해상도 정착. 변형-전 캐시 + 비교/디버그 프리뷰 + 썸네일까지 채운다.
            let fullCleanRawRevision = frame.cleanRawRevision
            let full = makeSnapshot(
                for: frame, baseKey: baseKey,
                needsRawPreview: frame.rawPreviewImage == nil || frame.rawPreviewTransform != frame.imageTransform,
                needsNeutralPreview: beforeAfterCompareActive
                    && (frame.neutralPreviewImage == nil
                        || frame.neutralPreviewTransform != frame.imageTransform
                        || frame.neutralPreviewBaseKey != baseKey),
                needsMainPreview: beforeAfterMainCompareActive
                    && frame.params.developTarget != .main
                    && (frame.mainPreviewImage == nil
                        || frame.mainPreviewTransform != frame.imageTransform
                        || frame.mainPreviewDevelopRevision != frame.developRevision),
                needsDebugPreviews: frame.debugOverlayEnabled,
                needsThumbnail: !preserveThumbnail,
                proxyMaxDimension: DevelopFrameRenderer.fullMaxDimension
            )
            developController.updateProcessingDetail(
                interactive: false,
                proxyPixels: Int(DevelopFrameRenderer.fullMaxDimension),
                isScanning: isScanning,
                language: appLanguage
            )
            do {
                let result = try await renderDevelopmentSnapshot(full)
                guard developmentRequestIsCurrent(frame, selectionBoundFrameID: selectionBoundFrameID) else { return }
                guard softProofRenderRequestIsCurrent(full) else {
                    revision = frame.developRevision
                    continue
                }
                guard frame.developRevision == revision else {
                    revision = frame.developRevision
                    continue
                }
                applyBaseCache(result, to: frame, baseKey: baseKey)
                applyPreviewRawCache(result, to: frame, maxDimension: full.proxyMaxDimension)
                frame.cachedDevelopedBase = result.developedBase   // 결함 제거 적용 전 base
                if pixelSamplerStore.isEnabled {
                    pixelSamplerStore.setWorkingBase(result.workingBase, for: frame.id)
                }
                frame.cachedClippingOverlayBase = result.clippingOverlayBase
                frame.cachedDestinationGamutOverlayBase = result.destinationGamutOverlayBase
                if let thumbnailBase = result.thumbnailBase {
                    frame.cachedThumbnailBase = thumbnailBase
                }
                if let rawBase = result.rawBase { frame.cachedRawBase = rawBase }
                if let rawPreview = result.rawPreview {
                    frame.rawPreviewImage = NSImage(
                        cgImage: rawPreview,
                        size: NSSize(width: rawPreview.width, height: rawPreview.height)
                    )
                    frame.rawPreviewTransform = full.imageTransform
                }
                if let neutralBase = result.neutralBase { frame.cachedNeutralBase = neutralBase }
                if let neutralPreview = result.neutralPreview {
                    frame.neutralPreviewImage = NSImage(
                        cgImage: neutralPreview,
                        size: NSSize(width: neutralPreview.width, height: neutralPreview.height)
                    )
                    frame.neutralPreviewTransform = full.imageTransform
                    frame.neutralPreviewBaseKey = full.baseKey
                }
                if let mainBase = result.mainBase { frame.cachedMainBase = mainBase }
                if let mainPreview = result.mainPreview {
                    frame.mainPreviewImage = NSImage(
                        cgImage: mainPreview,
                        size: NSSize(width: mainPreview.width, height: mainPreview.height)
                    )
                    frame.mainPreviewTransform = full.imageTransform
                    frame.mainPreviewDevelopRevision = revision
                }
                frame.noteDevelopedDisplaySize(
                    CGSize(width: result.developed.width, height: result.developed.height),
                    authoritative: true
                )
                frame.developedImage = NSImage(
                    cgImage: result.developed,
                    size: NSSize(width: result.developed.width, height: result.developed.height)
                )
                frame.clippingOverlayImage = result.clippingOverlay.map {
                    NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
                }
                frame.destinationGamutOverlayImage = result.destinationGamutOverlay.map {
                    NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
                }
                frame.developedPreviewTransform = full.imageTransform
                frame.displayedSoftProofRevision = full.softProofRevision
                if let thumb = result.thumbnail {
                    frame.thumbnailImage = NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
                    // 정착 패스마다 디스크 썸네일을 현상 결과로 덮어쓴다(표준 방식 — 라이브러리/
                    // 필름스트립이 재시작 후에도 마지막 현상 상태를 보여준다). 드래그 중 인터랙티브
                    // 패스는 건너뛰므로 디스크 IO 는 정착 시점 1회다.
                    persistThumbnail(for: frame, cgImage: thumb)
                }
                frame.debugPreviewImages = Dictionary(uniqueKeysWithValues: result.debugPreviews.map { preview in
                    (preview.stage,
                     NSImage(cgImage: preview.image, size: NSSize(width: preview.image.width, height: preview.image.height)))
                })
                frame.debugMetrics = Dictionary(uniqueKeysWithValues: result.debugPreviews.compactMap { preview in
                    guard let metrics = preview.metrics else { return nil }
                    return (preview.stage, metrics)
                })
                frame.hasDevelopedOnce = true
                frame.displayedCleanRawRevision = max(
                    frame.displayedCleanRawRevision, fullCleanRawRevision
                )
                markDevelopedResident(frame)   // 풀해상도 버퍼 FIFO 등록(한도 초과 시 오래된 프레임 해제)
                // 결함 제거는 입력 raw(cleaned raw)에 이미 반영되어 있으므로 현상 결과에 그대로 포함된다.
                return
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                trace.recordError(error)
                developFailed(frame, revision: revision)
                if frame.developRevision == revision { return }
                revision = frame.developRevision
                continue
            }
        }
    }

    private func renderDevelopmentSnapshot(
        _ snapshot: DevelopFrameSnapshot
    ) async throws -> DevelopFrameRenderResult {
        let renderTask = Task.detached(priority: .userInitiated) {
            try DevelopFrameRenderer.render(snapshot)
        }
        return try await withTaskCancellationHandler {
            try await renderTask.value
        } onCancel: {
            renderTask.cancel()
        }
    }

    /// 현상 스냅샷 빌더(인터랙티브/풀 공통). 입력 raw·base 캐시·transform 을 프레임에서 읽어 담는다.
    func makeSnapshot(
        for frame: ScanFrame,
        baseKey: FilmBaseCacheKey,
        needsRawPreview: Bool,
        needsNeutralPreview: Bool,
        needsMainPreview: Bool = false,
        needsDebugPreviews: Bool,
        needsThumbnail: Bool,
        proxyMaxDimension: CGFloat
    ) -> DevelopFrameSnapshot {
        let previewRaw = cachedPreviewRaw(for: frame, maxDimension: proxyMaxDimension)
        let cleanedIdentity = frame.boundDefectRecipeIdentity
        return DevelopFrameSnapshot(
            rawScanURL: frame.rawScanURL,
            sourceKind: frame.sourceKind,
            preloadedRaw: frame.identityMatchedCleanedRawImage,
            preloadedPreviewRaw: previewRaw,
            preloadedFullPreviewRaw: previewRaw == nil ? cachedSettledPreviewRaw(for: frame) : nil,
            cleanedRawURL: frame.identityMatchedCleanedRawDiskURL,
            filmType: frame.filmType,
            params: frame.params,
            preset: frame.preset,
            imageTransform: frame.imageTransform,
            cachedBase: frame.cachedBaseKey == baseKey ? frame.cachedBase : nil,
            baseKey: baseKey,
            needsRawPreview: needsRawPreview,
            needsNeutralPreview: needsNeutralPreview,
            needsMainPreview: needsMainPreview,
            needsDebugPreviews: needsDebugPreviews,
            softProof: displaySoftProofSettings(for: frame),
            softProofRevision: softProofConfigurationRevision,
            destinationGamutWarningEnabled: destinationGamutWarningEnabled
                && destinationGamutWarningAvailable,
            clippingOverlayEnabled: clippingOverlayEnabled,
            needsPixelSamplerBase: pixelSamplerStore.isEnabled,
            proxyMaxDimension: proxyMaxDimension,
            needsThumbnail: needsThumbnail,
            cleanedRawFrameID: cleanedIdentity == nil ? nil : frame.id,
            cleanedRawIdentity: cleanedIdentity,
            requiresCleanedRaw: frame.requiresCleanedRawForActiveDefects
        )
    }

    private func softProofRenderRequestIsCurrent(_ snapshot: DevelopFrameSnapshot) -> Bool {
        snapshot.softProofRevision == softProofConfigurationRevision
    }

    /// 추가 편집 없이 settle 윈도(≈0.14s)가 지나면 true, 그 전에 새 리비전이 오면 false(드래그 진행).
    /// 짧은 간격으로 폴링해 새 편집을 빠르게 감지 → 라이브 인터랙티브 갱신이 끊기지 않는다.
    func waitForDevelopSettle(_ frame: ScanFrame, revision: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(0.14)
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: 25_000_000)
            } catch {
                return false
            }
            if Task.isCancelled || !ownsFrame(frame) || frame.developRevision != revision { return false }
        }
        return !Task.isCancelled && ownsFrame(frame) && frame.developRevision == revision
    }

    func applyBaseCache(_ result: DevelopFrameRenderResult, to frame: ScanFrame, baseKey: FilmBaseCacheKey) {
        frame.cachedBase = result.base
        frame.cachedBaseKey = baseKey
        frame.baseRGB = result.base?.rgb
    }

    /// 요청 치수와 일치하는 raw 프록시 캐시. 정착 치수(fullMaxDimension) 요청은 정착 슬롯을,
    /// 그보다 작은(인터랙티브) 요청은 같은 치수로 만들었던 인터랙티브 슬롯만 사용한다.
    func cachedPreviewRaw(for frame: ScanFrame, maxDimension: CGFloat) -> DevelopFramePreviewRaw? {
        if maxDimension >= DevelopFrameRenderer.fullMaxDimension - 0.5 {
            return cachedSettledPreviewRaw(for: frame)
        }
        guard frame.cachedInteractivePreviewRawRevision == frame.cleanRawRevision,
              abs(frame.cachedInteractivePreviewRawDimension - maxDimension) <= 0.5 else {
            return nil
        }
        return frame.cachedInteractivePreviewRaw
    }

    func cachedSettledPreviewRaw(for frame: ScanFrame) -> DevelopFramePreviewRaw? {
        frame.cachedSettledPreviewRawRevision == frame.cleanRawRevision
            ? frame.cachedSettledPreviewRaw
            : nil
    }

    func applyPreviewRawCache(_ result: DevelopFrameRenderResult, to frame: ScanFrame, maxDimension: CGFloat) {
        applyPreviewRawCache(result.previewRaw, to: frame, maxDimension: maxDimension)
    }

    func applyPreviewRawCache(_ result: DevelopFrameFastPreviewResult, to frame: ScanFrame, maxDimension: CGFloat) {
        applyPreviewRawCache(result.previewRaw, to: frame, maxDimension: maxDimension)
    }

    func applyPreviewRawCache(_ previewRaw: DevelopFramePreviewRaw?, to frame: ScanFrame, maxDimension: CGFloat) {
        guard let previewRaw else { return }
        if maxDimension >= DevelopFrameRenderer.fullMaxDimension - 0.5 {
            frame.cachedSettledPreviewRaw = previewRaw
            frame.cachedSettledPreviewRawRevision = frame.cleanRawRevision
        } else {
            frame.cachedInteractivePreviewRaw = previewRaw
            frame.cachedInteractivePreviewRawRevision = frame.cleanRawRevision
            frame.cachedInteractivePreviewRawDimension = maxDimension
        }
    }

    func developFailed(_ frame: ScanFrame, revision: Int) {
        guard ownsFrame(frame), frame.developRevision == revision else { return }
        reportError(text(AppLocalizedPhrase.imageLoadFailedFormat, frame.rawScanURL.lastPathComponent))
    }

}
