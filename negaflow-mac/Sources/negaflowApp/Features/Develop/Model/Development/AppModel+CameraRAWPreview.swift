import AppKit
import Chromabase
import Foundation

extension AppModel {
    /// 첫 화면만 먼저 발행한다. 이 입력의 측정값은 정착 렌더에 넘기지 않는다.
    func prepareColdCameraRAWPreview(
        _ frame: ScanFrame, snapshot: DevelopFrameSnapshot, revision: Int,
        cleanRawRevision: Int, selectionBoundFrameID: UUID?
    ) async -> (isCurrent: Bool, hasSettledInput: Bool) {
        let displayedSize = frame.developedImage?.size ?? .zero
        guard !frame.developedIsSettled,
              max(displayedSize.width, displayedSize.height) < snapshot.proxyMaxDimension,
              usesCameraNativeDecode(frame),
              !snapshot.isInputGammaPreview, snapshot.params.inputGamma == .automatic,
              !snapshot.requiresCleanedRaw, snapshot.preloadedRaw == nil,
              snapshot.cleanedRawURL == nil, snapshot.preloadedPreviewRaw == nil,
              snapshot.preloadedFullPreviewRaw == nil,
              let work = NativeCameraRAW.beginProgressivePreview(
                snapshot.rawScanURL, firstMaxDimension: snapshot.proxyMaxDimension) else { return (true, false) }
        let sourceRevision = frame.sourceLocationRevision
        defer { work.cancel() }
        do {
            let outcome = try await withTaskCancellationHandler {
                for try await phase in work.updates {
                    guard developmentRequestIsCurrent(frame, selectionBoundFrameID: selectionBoundFrameID),
                          frame.sourceLocationRevision == sourceRevision,
                          frame.cleanRawRevision == cleanRawRevision else { return (false, false) }
                    switch phase {
                    case .first(let raster):
                        var first = snapshot
                        first.preloadedPreviewRaw = DevelopFramePreviewRaw(image: raster, usesLinearSRGB: true)
                        first.needsRangeShape = false
                        first.needsThumbnail = false
                        let result = try await renderDevelopmentSnapshot(first)
                        applyInitialCameraRAWPreview(result, to: frame, snapshot: first, revision: revision,
                            cleanRawRevision: cleanRawRevision, sourceRevision: sourceRevision)
                    case .ready(let raster):
                        guard frame.developRevision == revision, frame.params == snapshot.params,
                              frame.rawScanURL == snapshot.rawScanURL else { return (false, false) }
                        applyPreviewRawCache(DevelopFramePreviewRaw(image: raster, usesLinearSRGB: true),
                            to: frame, maxDimension: DevelopFrameRenderer.fullMaxDimension)
                        markDevelopedResident(frame)
                        return (true, true)
                    }
                }
                return (!Task.isCancelled, false)
            } onCancel: {
                work.cancel()
            }
            // 선택 루프가 끝나기 전에 실제 LibRaw 핸들도 해제한다. 빠른 전환에서 작업이 쌓이지 않는다.
            await work.cancelAndWait()
            return outcome
        } catch {
            await work.cancelAndWait()
            // 선행 표시를 만들지 못해도 기존 정착 디코드 경로로 복구한다.
            return (developmentRequestIsCurrent(frame, selectionBoundFrameID: selectionBoundFrameID)
                && frame.sourceLocationRevision == sourceRevision && frame.cleanRawRevision == cleanRawRevision, false)
        }
    }

    func applyInitialCameraRAWPreview(
        _ result: DevelopFrameRenderResult, to frame: ScanFrame, snapshot: DevelopFrameSnapshot,
        revision: Int, cleanRawRevision: Int, sourceRevision: UInt64
    ) {
        guard !Task.isCancelled, ownsFrame(frame), selectedFrameID == frame.id,
              frame.developRevision == revision, frame.cleanRawRevision == cleanRawRevision,
              frame.sourceLocationRevision == sourceRevision, frame.rawScanURL == snapshot.rawScanURL,
              snapshot.softProofRevision == softProofConfigurationRevision else { return }
        frame.developedImage = NSImage(cgImage: result.developed,
            size: NSSize(width: result.developed.width, height: result.developed.height))
        frame.developedPreviewTransform = snapshot.imageTransform
        frame.developedIsSettled = false
        CameraRAWSelectionTrace.presented(frame, settled: false)
        frame.displayedSoftProofRevision = snapshot.softProofRevision
        frame.displayedCleanRawRevision = max(frame.displayedCleanRawRevision, cleanRawRevision)
        frame.noteDevelopedDisplaySize(
            CGSize(width: result.developed.width, height: result.developed.height), authoritative: false)
        frame.clippingOverlayImage = result.clippingOverlay.map {
            NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
        }
        frame.destinationGamutOverlayImage = result.destinationGamutOverlay.map {
            NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
        }
        // 정착 전에 사진을 넘겨도 임시 표시 이미지가 상주 한도를 벗어나 쌓이지 않는다.
        frameCacheManager.markDevelopedResident(frame, selectedFrameID: selectedFrameID,
            frames: frames, evictBuffers: { [weak self] in self?.evictDevelopBuffers($0) })
    }
}
