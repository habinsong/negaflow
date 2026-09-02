import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    func renderLatestDevelopment(
        for frame: ScanFrame,
        preserveThumbnail: Bool,
        skipInteractivePreview: Bool,
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

            if !skipInteractivePreview {
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
                    let renderStarted = Date()
                    let fast = try await renderDevelopmentSnapshot(interactive)
                    // 라이브 갱신 간격을 이 기기의 실제 소요에 맞추기 위한 근거.
                    developController.noteInteractiveDevelopDuration(-renderStarted.timeIntervalSinceNow)
                    guard developmentRequestIsCurrent(frame, selectionBoundFrameID: selectionBoundFrameID) else {
                        return
                    }
                    guard softProofRenderRequestIsCurrent(interactive) else {
                        revision = frame.developRevision
                        continue
                    }
                    // 결함 제거 세대가 뒤처진 결과는 화면에 올리지 않는다. 슬라이더 값이 한 틱
                    // 낡은 건 곧 덮이지만, 방금 지운 먼지가 되살아나 보이는 건 다른 문제다.
                    guard interactiveCleanRawRevision == frame.cleanRawRevision else {
                        revision = frame.developRevision
                        continue
                    }
                    // 반면 인스펙터 값이 렌더 도는 사이 또 바뀐 것뿐이라면 이 장은 화면에 올린다.
                    // 예전에는 여기서 통째로 버리고 다시 그렸는데, 그러면 드래그가 빠를수록 버리는
                    // 비율이 올라가 화면이 오히려 덜 갱신됐다(실측: 요청 간격을 45→16 ms 로
                    // 줄이면 갱신이 23.4→15.9/s 로 **떨어짐**). 한 틱 낡은 장을 잠깐 보여주고
                    // 바로 아래에서 최신 값으로 다시 도는 편이 라이브 프리뷰답다 — 루프가
                    // 순차라 옛 결과가 새 결과를 덮을 수는 없고, 마지막 값은 항상 반영된다.
                    applyBaseCache(fast, to: frame, baseKey: baseKey)
                    applySceneMeasurementCache(
                        fast, to: frame, baseKey: baseKey,
                        proxyMaxDimension: interactive.proxyMaxDimension
                    )
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
                    // 프록시 결과다 — 정착 패스가 끝나기 전에 취소되면 저화질로 남는다는 표시.
                    frame.developedIsSettled = false
                    if let thumbnailBase = fast.thumbnailBase {
                        frame.cachedThumbnailBase = thumbnailBase
                    }
                    if let thumb = fast.thumbnail {
                        frame.thumbnailImage = NSImage(
                            cgImage: thumb,
                            size: NSSize(width: thumb.width, height: thumb.height)
                        )
                        frame.thumbnailTransform = interactive.imageTransform
                    }
                    frame.hasDevelopedOnce = true
                    frame.displayedCleanRawRevision = max(
                        frame.displayedCleanRawRevision, interactiveCleanRawRevision
                    )
                } catch is CancellationError {
                    return
                } catch DevelopFrameRenderError.cleanedRawPending {
                    // 결함 제거 빌드가 아직 픽셀을 안 내놨다. 실패가 아니라 순서 문제이고,
                    // 빌드가 커밋될 때 현상이 다시 발행된다 — 조용히 물러난다.
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
                // 정착 감지: 추가 편집 없이 settle 윈도우가 지나야 풀해상도로 마무리한다.
                if !(await waitForDevelopSettle(frame, revision: revision)) {
                    guard developmentRequestIsCurrent(
                        frame,
                        selectionBoundFrameID: selectionBoundFrameID
                    ) else { return }
                    revision = frame.developRevision
                    continue
                }
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
                // 방향이 어긋난 썸네일은 preserveThumbnail 이어도 다시 그린다 — 프레임을 회전한
                // 뒤(또는 시드 시점과 변형이 달라진 뒤) 썸네일만 옛 방향으로 남던 문제를 막는다.
                needsThumbnail: !preserveThumbnail
                    || frame.thumbnailTransform != frame.imageTransform,
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
                applySceneMeasurementCache(
                    result, to: frame, baseKey: baseKey,
                    proxyMaxDimension: full.proxyMaxDimension
                )
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
                frame.developedIsSettled = true
                if let thumb = result.thumbnail {
                    frame.thumbnailImage = NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
                    frame.thumbnailTransform = full.imageTransform
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
            } catch DevelopFrameRenderError.cleanedRawPending {
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
            cachedSceneMeasurements: cachedSceneMeasurements(
                for: frame, baseKey: baseKey, proxyMaxDimension: proxyMaxDimension
            ),
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
    /// 폴링 간격은 이 화면의 프레임에서 뽑는다(developController.editPollInterval) — 고정 간격은
    /// 빠른 기기에서 새 편집을 알아채는 데만 한 프레임 넘게 흘려보냈다.
    func waitForDevelopSettle(_ frame: ScanFrame, revision: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(0.14)
        let poll = UInt64(max(developController.editPollInterval, 0.001) * 1_000_000_000)
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: poll)
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

    /// 장면 측정 캐시 키. 베이스 값까지 포함해야 한다 — auto 모드는 baseKey 가 같아도 입력이
    /// 바뀌면 베이스가 달라지고, 그러면 반전 밀도역도 다시 재야 한다.
    func sceneMeasurementCacheKey(
        for frame: ScanFrame,
        baseKey: FilmBaseCacheKey
    ) -> SceneMeasurementCacheKey {
        SceneMeasurementCacheKey(
            baseKey: baseKey,
            baseRGB: frame.cachedBaseKey == baseKey ? frame.cachedBase?.rgb : nil,
            cleanRawRevision: frame.cleanRawRevision,
            autoLevels: frame.params.autoLevels,
            autoNeutralBalance: frame.params.autoNeutralBalance
        )
    }

    /// 요청 치수에 해당하는 슬롯의 측정. 정착 치수 요청은 정착 슬롯을, 그보다 작은(드래그)
    /// 요청은 같은 치수로 떴던 드래그 슬롯만 쓴다 — 프리뷰 raw 캐시와 같은 규칙이다.
    func cachedSceneMeasurements(
        for frame: ScanFrame,
        baseKey: FilmBaseCacheKey,
        proxyMaxDimension: CGFloat
    ) -> DevelopSceneMeasurements {
        guard frame.cachedSceneMeasurementsKey == sceneMeasurementCacheKey(for: frame, baseKey: baseKey) else {
            return DevelopSceneMeasurements()
        }
        if proxyMaxDimension >= DevelopFrameRenderer.fullMaxDimension - 0.5 {
            return frame.cachedSettledSceneMeasurements ?? DevelopSceneMeasurements()
        }
        guard abs(frame.cachedInteractiveSceneMeasurementsDimension - proxyMaxDimension) <= 0.5 else {
            return DevelopSceneMeasurements()
        }
        return frame.cachedInteractiveSceneMeasurements ?? DevelopSceneMeasurements()
    }

    func applySceneMeasurementCache(
        _ result: DevelopFrameRenderResult,
        to frame: ScanFrame,
        baseKey: FilmBaseCacheKey,
        proxyMaxDimension: CGFloat
    ) {
        let key = sceneMeasurementCacheKey(for: frame, baseKey: baseKey)
        if frame.cachedSceneMeasurementsKey != key {
            // 입력 raw 나 베이스가 바뀌었다 — 두 슬롯 모두 옛 장면 것이다.
            frame.cachedInteractiveSceneMeasurements = nil
            frame.cachedInteractiveSceneMeasurementsDimension = 0
            frame.cachedSettledSceneMeasurements = nil
            frame.cachedSceneMeasurementsKey = key
        }
        if proxyMaxDimension >= DevelopFrameRenderer.fullMaxDimension - 0.5 {
            frame.cachedSettledSceneMeasurements = result.sceneMeasurements
        } else {
            frame.cachedInteractiveSceneMeasurements = result.sceneMeasurements
            frame.cachedInteractiveSceneMeasurementsDimension = proxyMaxDimension
        }
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
