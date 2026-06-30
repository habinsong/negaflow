import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    // MARK: 슬라이더 라이브 현상 요청(레이트 throttle)
    //
    // 리딩+트레일링 throttle: 즉시(리딩) 한 번 띄우고, 간격 내 추가 변경은 트레일링으로 모아 ~22fps로
    // 제한한다. 과거처럼 매 틱마다 리비전을 올려 루프가 무제한 렌더하지 않으므로 GPU(IOSurface) 압박이
    // 사라지고 간헐적 블랭크 렌더가 방지된다. 마지막(정착) 호출이 풀해상도 패스까지 마무리한다.
    func requestDevelop(_ frame: ScanFrame) {
        guard !isScanning else { return }
        let interval = Self.developThrottleInterval
        let now = Date()
        let elapsed = now.timeIntervalSince(developThrottleLast)
        developThrottleTask?.cancel()
        if elapsed >= interval {
            developThrottleLast = now
            developThrottleTask = Task { [weak self] in
                await self?.developFrame(frame)
            }
        } else {
            let wait = interval - elapsed
            developThrottleTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.developThrottleLast = Date()
                await self?.developFrame(frame)
            }
        }
    }

    // MARK: develop (엔진 호출 — 색감 로직은 그대로)
    func developFrame(_ frame: ScanFrame) async {
        // filmType 동기화는 실제로 다를 때만(슬라이더 핫패스에서 불필요한 @Published 발행 방지).
        if frame.params.filmType != frame.filmType {
            frame.updateParams { $0.filmType = frame.filmType }
        }
        frame.developRevision += 1
        // 이미 진행 중이면 리비전만 올리고 종료 — 진행 중 루프가 최신 값으로 재렌더한다(코얼레싱).
        guard activeDevelopmentFrameIDs.insert(frame.id).inserted else { return }
        await renderLatestDevelopment(for: frame)
    }

    private func renderLatestDevelopment(for frame: ScanFrame) async {
        frame.isDeveloping = true
        developBegan()
        defer {
            frame.isDeveloping = false
            activeDevelopmentFrameIDs.remove(frame.id)
            developEnded()
        }
        var revision = frame.developRevision

        while true {
            let baseKey = FilmBaseCacheKey(
                filmType: frame.filmType,
                mode: frame.params.baseEstimationMode,
                manualBaseRGB: frame.params.manualBaseRGB,
                filmStockDminID: frame.params.filmStockDminID
            )

            // ── 패스 1: 인터랙티브(저해상도 프록시, 발색 결과만). 슬라이더 드래그 중 즉각적인
            //    라이브 프리뷰를 위해 픽셀 수를 줄여 빠르게 한 장 띄운다. 변형-전 캐시(cachedDevelopedBase)
            //    나 비교/디버그 프리뷰는 만들지 않는다(정착 패스에서 풀해상도로 채운다).
            let interactive = makeSnapshot(
                for: frame, baseKey: baseKey,
                needsRawPreview: false, needsNeutralPreview: false, needsDebugPreviews: false,
                needsThumbnail: frame.thumbnailImage == nil,
                proxyMaxDimension: DevelopFrameRenderer.interactiveMaxDimension
            )
            updateProcessingDetail(interactive: true)
            do {
                let fast = try await Task.detached(priority: .userInitiated) {
                    try DevelopFrameRenderer.render(interactive)
                }.value
                applyBaseCache(fast, to: frame, baseKey: baseKey)
                frame.developedImage = NSImage(
                    cgImage: fast.developed,
                    size: NSSize(width: fast.developed.width, height: fast.developed.height)
                )
                if let thumb = fast.thumbnail {
                    frame.thumbnailImage = NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
                }
                frame.hasDevelopedOnce = true
            } catch {
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
                revision = frame.developRevision
                continue
            }

            // ── 패스 2: 풀해상도 정착. 변형-전 캐시 + 비교/디버그 프리뷰 + 썸네일까지 채운다.
            let full = makeSnapshot(
                for: frame, baseKey: baseKey,
                needsRawPreview: frame.rawPreviewImage == nil || frame.rawPreviewTransform != frame.imageTransform,
                needsNeutralPreview: beforeAfterCompareActive
                    && (frame.neutralPreviewImage == nil
                        || frame.neutralPreviewTransform != frame.imageTransform
                        || frame.neutralPreviewBaseKey != baseKey),
                needsDebugPreviews: frame.debugOverlayEnabled,
                needsThumbnail: true,
                proxyMaxDimension: DevelopFrameRenderer.fullMaxDimension
            )
            updateProcessingDetail(interactive: false)
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try DevelopFrameRenderer.render(full)
                }.value
                guard frame.developRevision == revision else {
                    revision = frame.developRevision
                    continue
                }
                applyBaseCache(result, to: frame, baseKey: baseKey)
                frame.cachedDevelopedBase = result.developedBase   // ICE 적용 전 base
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
                frame.developedImage = NSImage(
                    cgImage: result.developed,
                    size: NSSize(width: result.developed.width, height: result.developed.height)
                )
                if let thumb = result.thumbnail {
                    frame.thumbnailImage = NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
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
                markDevelopedResident(frame)   // 풀해상도 버퍼 FIFO 등록(한도 초과 시 오래된 프레임 해제)
                // 결함 제거는 입력 raw(cleaned raw)에 이미 반영되어 있으므로 현상 결과에 그대로 포함된다.
                return
            } catch {
                developFailed(frame, revision: revision)
                if frame.developRevision == revision { return }
                revision = frame.developRevision
                continue
            }
        }
    }

    /// 현상 스냅샷 빌더(인터랙티브/풀 공통). 입력 raw·base 캐시·transform 을 프레임에서 읽어 담는다.
    private func makeSnapshot(
        for frame: ScanFrame,
        baseKey: FilmBaseCacheKey,
        needsRawPreview: Bool,
        needsNeutralPreview: Bool,
        needsDebugPreviews: Bool,
        needsThumbnail: Bool,
        proxyMaxDimension: CGFloat
    ) -> DevelopFrameSnapshot {
        DevelopFrameSnapshot(
            rawScanURL: frame.rawScanURL,
            preloadedRaw: frame.cleanedRawImage,
            cleanedRawURL: frame.cleanedRawDiskURL,
            filmType: frame.filmType,
            params: frame.params,
            preset: frame.preset,
            imageTransform: frame.imageTransform,
            cachedBase: frame.cachedBaseKey == baseKey ? frame.cachedBase : nil,
            baseKey: baseKey,
            needsRawPreview: needsRawPreview,
            needsNeutralPreview: needsNeutralPreview,
            needsDebugPreviews: needsDebugPreviews,
            proxyMaxDimension: proxyMaxDimension,
            needsThumbnail: needsThumbnail
        )
    }

    /// 추가 편집 없이 settle 윈도(≈0.14s)가 지나면 true, 그 전에 새 리비전이 오면 false(드래그 진행).
    /// 짧은 간격으로 폴링해 새 편집을 빠르게 감지 → 라이브 인터랙티브 갱신이 끊기지 않는다.
    private func waitForDevelopSettle(_ frame: ScanFrame, revision: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(0.14)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if frame.developRevision != revision { return false }
        }
        return frame.developRevision == revision
    }

    private func applyBaseCache(_ result: DevelopFrameRenderResult, to frame: ScanFrame, baseKey: FilmBaseCacheKey) {
        frame.cachedBase = result.base
        frame.cachedBaseKey = baseKey
        frame.baseRGB = result.base?.rgb
    }

    private func developFailed(_ frame: ScanFrame, revision: Int) {
        guard frame.developRevision == revision else { return }
        statusMessage = "이미지 로드 실패: \(frame.rawScanURL.lastPathComponent)"
        scanPhase = .error
    }

    // MARK: 현상 처리 상태(스캔과 분리)
    private func developBegan() {
        developInFlight += 1
        processingActive = true
    }

    private func developEnded() {
        developInFlight = max(0, developInFlight - 1)
        if developInFlight == 0 {
            processingActive = false
            processingDetail = ""
        }
    }

    private func updateProcessingDetail(interactive: Bool) {
        guard !isScanning else { return }   // 스캔 중엔 스캔 진행률이 우선
        if developInFlight > 1 {
            processingDetail = "현상 중 \(developInFlight)장"
        } else {
            processingDetail = interactive ? "프리뷰 생성 중" : "고해상도 현상 중"
        }
    }

    func loadRawPreview(_ frame: ScanFrame) {
        let snapshot = DevelopFrameSnapshot(
            rawScanURL: frame.rawScanURL,
            preloadedRaw: frame.cleanedRawImage,
            cleanedRawURL: frame.cleanedRawDiskURL,
            filmType: frame.filmType,
            params: frame.params,
            preset: frame.preset,
            imageTransform: frame.imageTransform,
            cachedBase: nil,
            baseKey: FilmBaseCacheKey(
                filmType: frame.filmType,
                mode: frame.params.baseEstimationMode,
                manualBaseRGB: frame.params.manualBaseRGB,
                filmStockDminID: frame.params.filmStockDminID
            ),
            needsRawPreview: true,
            needsNeutralPreview: false,
            needsDebugPreviews: false
        )
        Task {
            let rawPreview = try? await Task.detached(priority: .utility) {
                try DevelopFrameRenderer.renderRawPreview(snapshot)
            }.value
            guard let rawPreview else { return }
            frame.rawPreviewImage = NSImage(
                cgImage: rawPreview,
                size: NSSize(width: rawPreview.width, height: rawPreview.height)
            )
            frame.rawPreviewTransform = snapshot.imageTransform
        }
    }
}
