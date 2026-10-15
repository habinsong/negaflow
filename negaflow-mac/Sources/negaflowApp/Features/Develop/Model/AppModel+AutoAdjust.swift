import SwiftUI
import Chromabase
import AppKit

// 라이트룸식 자동 보정. 핵심은 "결정적(1회)": 대상 슬라이더를 0 으로 리셋한 **중립 현상본**을 기준으로
// 절대값을 계산해 슬라이더에 **대입**한다(누적 아님). 그래서 버튼을 여러 번 눌러도 같은 결과가 되고,
// 중립(톤 매핑 전) 기준이라 노출뿐 아니라 대비·화이트·블랙·바이브런스 등 모든 슬라이더가 의미있게 변한다.
// (현재 결과 기준 델타는 이미 보정된 상태라 노출 외에는 0 에 수렴 → 과거 버그였다.)
extension AppModel {
    /// 자동 화이트 밸런스(⇧⌘U) — Warmth/Tint 를 0 으로 둔 중립본의 평균색을 gray-world 로 무채색화.
    @discardableResult
    func autoWhiteBalance(
        _ frame: ScanFrame,
        source: AutoAdjustTrace.Source = .inspectorButton
    ) -> Task<Void, Never> {
        // 다른 종류의 자동 보정이 돌고 있으면 그것이 반영된 뒤 그 값 위에서 잰다 — 연달아 누르면
        // 순서대로 누른 것과 같은 값이 된다(2026-10-15: 서로의 요청을 버려 한쪽이 씹혔다). 기다릴
        // 것이 없으면 예전처럼 누른 순간의 입력으로 요청을 고정한다.
        let pending = frame.autoToneTail
        frame.autoWhiteBalanceTicket &+= 1
        let ticket = frame.autoWhiteBalanceTicket
        let clickRequest = pending == nil ? AutoAdjustRequest(frame) : nil
        let clickParams = frame.params
        AutoAdjustTrace.began("autoWhiteBalance", source: source, frameID: frame.id)
        let task = Task {
            defer { if frame.autoWhiteBalanceTicket == ticket { frame.autoWhiteBalanceTail = nil } }
            var request = clickRequest
            var expectedParams = clickParams
            if let pending {
                await pending.value
                guard frame.autoWhiteBalanceTicket == ticket else { return }
                request = AutoAdjustRequest(frame)
                expectedParams = frame.params
            }
            guard let request, request.isCurrent(frame) else { return }
            guard await prepareCleanedRawForConsumption(frame) else {
                return AutoAdjustTrace.stopped("autoWhiteBalance", source: source, at: .cleanedRawUnavailable)
            }
            guard ownsFrame(frame) else {
                return AutoAdjustTrace.stopped("autoWhiteBalance", source: source, at: .frameNotOwned)
            }
            guard request.isCurrent(frame), frame.params == expectedParams else {
                return AutoAdjustTrace.stopped("autoWhiteBalance", source: source, at: .paramsChangedBeforeRender)
            }
            let expectedDefectIdentity = frame.boundDefectRecipeIdentity
            let cleanRawRevision = frame.cleanRawRevision
            let snapshot = neutralSnapshot(frame, clearWB: true)
            guard let result = await Task.detached(priority: .userInitiated, operation: { () -> (warmth: Double, tint: Double)? in
                guard let cg = try? DevelopFrameRenderer.render(snapshot).developed,
                      let stats = AutoAdjust.imageStats(cg) else { return nil }
                return AutoAdjust.autoWhiteBalance(stats)
            }).value else {
                return AutoAdjustTrace.stopped("autoWhiteBalance", source: source, at: .renderOrStatsFailed)
            }
            guard ownsFrame(frame) else {
                return AutoAdjustTrace.stopped("autoWhiteBalance", source: source, at: .frameNotOwned)
            }
            guard request.isCurrent(frame), frame.params == expectedParams else {
                return AutoAdjustTrace.stopped("autoWhiteBalance", source: source, at: .paramsChangedAfterRender)
            }
            guard frame.cleanRawRevision == cleanRawRevision else {
                return AutoAdjustTrace.stopped("autoWhiteBalance", source: source, at: .cleanRawRevisionChanged)
            }
            guard frame.boundDefectRecipeIdentity == expectedDefectIdentity else {
                return AutoAdjustTrace.stopped("autoWhiteBalance", source: source, at: .defectIdentityChanged)
            }
            applyTransferredSettings(to: [frame]) {
                $0.params.warmth = result.0
                $0.params.tint = result.1
            }
            AutoAdjustTrace.applied(
                "autoWhiteBalance", source: source,
                values: String(format: "warmth=%.4f tint=%.4f", result.0, result.1)
            )
            statusMessage = text(AppLocalizedPhrase.autoWhiteBalanceStatus)
            Task { await developFrame(frame) }
        }
        frame.autoWhiteBalanceTail = task
        return task
    }

    /// 자동 톤(⌘U) — 톤/색 조정을 0 으로 둔 중립본의 히스토그램으로 Exposure·Contrast·Density·
    /// Highlights·Shadows·Whites·Blacks·Vibrance·Saturation 절대값을 계산해 대입. WB(Warmth/Tint)는
    /// 건드리지 않는다.
    @discardableResult
    func autoTone(
        _ frame: ScanFrame,
        source: AutoAdjustTrace.Source = .inspectorButton
    ) -> Task<Void, Never> {
        // 다른 종류의 자동 보정이 돌고 있으면 그것이 반영된 뒤 그 값 위에서 잰다 — 연달아 누르면
        // 순서대로 누른 것과 같은 값이 된다(2026-10-15: 서로의 요청을 버려 한쪽이 씹혔다). 기다릴
        // 것이 없으면 예전처럼 누른 순간의 입력으로 요청을 고정한다.
        let pending = frame.autoWhiteBalanceTail
        frame.autoToneTicket &+= 1
        let ticket = frame.autoToneTicket
        let clickRequest = pending == nil ? AutoAdjustRequest(frame) : nil
        let clickParams = frame.params
        AutoAdjustTrace.began("autoTone", source: source, frameID: frame.id)
        let task = Task {
            defer { if frame.autoToneTicket == ticket { frame.autoToneTail = nil } }
            var request = clickRequest
            var expectedParams = clickParams
            if let pending {
                await pending.value
                guard frame.autoToneTicket == ticket else { return }
                request = AutoAdjustRequest(frame)
                expectedParams = frame.params
            }
            guard let request, request.isCurrent(frame) else { return }
            guard await prepareCleanedRawForConsumption(frame) else {
                return AutoAdjustTrace.stopped("autoTone", source: source, at: .cleanedRawUnavailable)
            }
            guard ownsFrame(frame) else {
                return AutoAdjustTrace.stopped("autoTone", source: source, at: .frameNotOwned)
            }
            guard request.isCurrent(frame), frame.params == expectedParams else {
                return AutoAdjustTrace.stopped("autoTone", source: source, at: .paramsChangedBeforeRender)
            }
            let expectedDefectIdentity = frame.boundDefectRecipeIdentity
            let cleanRawRevision = frame.cleanRawRevision
            let snapshot = neutralSnapshot(frame, clearTone: true)
            // 폐루프: 계산값을 사용자의 나머지 파라미터(커브·색 깊이·타겟)와 함께 실제로 그려 다시
            // 재고 한 번 바로잡는다 — 모형 밖 상호작용을 흡수한다.
            guard let first = await Task.detached(priority: .userInitiated, operation: { () -> AutoAdjust.ToneDelta? in
                guard let cg = try? DevelopFrameRenderer.render(snapshot).developed,
                      let stats = AutoAdjust.imageStats(cg) else { return nil }
                return AutoAdjust.autoTone(stats, filmType: snapshot.filmType)
            }).value else {
                return AutoAdjustTrace.stopped("autoTone", source: source, at: .renderOrStatsFailed)
            }
            let verify = autoAdjustSnapshot(frame, params: Self.applying(first, to: frame.params))
            let adjustment = await Task.detached(priority: .userInitiated, operation: { () -> AutoAdjust.ToneDelta in
                guard let cg = try? DevelopFrameRenderer.render(verify).developed,
                      let verified = AutoAdjust.imageStats(cg) else { return first }
                return AutoAdjust.refineTone(first, measured: verified, filmType: verify.filmType)
            }).value
            guard ownsFrame(frame) else {
                return AutoAdjustTrace.stopped("autoTone", source: source, at: .frameNotOwned)
            }
            guard request.isCurrent(frame), frame.params == expectedParams else {
                return AutoAdjustTrace.stopped("autoTone", source: source, at: .paramsChangedAfterRender)
            }
            guard frame.cleanRawRevision == cleanRawRevision else {
                return AutoAdjustTrace.stopped("autoTone", source: source, at: .cleanRawRevisionChanged)
            }
            guard frame.boundDefectRecipeIdentity == expectedDefectIdentity else {
                return AutoAdjustTrace.stopped("autoTone", source: source, at: .defectIdentityChanged)
            }
            let p = Self.applying(adjustment, to: frame.params)
            applyTransferredSettings(to: [frame]) { $0.params = p }
            AutoAdjustTrace.applied(
                "autoTone", source: source,
                values: String(
                    format: "ev=%.4f contrast=%.4f whites=%.4f blacks=%.4f vibrance=%.4f",
                    adjustment.exposure, adjustment.contrast,
                    adjustment.whites, adjustment.blacks, adjustment.vibrance
                )
            )
            statusMessage = text(AppLocalizedPhrase.autoToneStatus)
            Task { await developFrame(frame) }
        }
        frame.autoToneTail = task
        return task
    }

    func resetAutoTone(_ frame: ScanFrame) {
        frame.autoAdjustRevision &+= 1
        frame.autoToneTicket &+= 1
        applyTransferredSettings(to: [frame]) { frame in
            frame.updateParams {
                $0.exposure = 0
                $0.contrast = 0
                $0.density = 0
                $0.highlight = 0
                $0.shadow = 0
                $0.whites = 0
                $0.blacks = 0
                $0.vibrance = 0
                $0.saturation = 0
            }
        }
        Task { await developFrame(frame) }
    }

    func resetAutoWhiteBalance(_ frame: ScanFrame) {
        frame.autoAdjustRevision &+= 1
        frame.autoWhiteBalanceTicket &+= 1
        applyTransferredSettings(to: [frame]) { frame in
            frame.updateParams {
                $0.warmth = 0
                $0.tint = 0
            }
        }
        Task { await developFrame(frame) }
    }

    /// 자동 톤이 대입하는 값. 채도는 대입하지 않는다 — 자동 톤은 채도를 계산하지 않으므로 대입하면
    /// 사용자 값을 조용히 0 으로 지운다(Windows `AutoAdjustCoordinator.ApplyTone` 과 같다).
    nonisolated static func applying(_ adjustment: AutoAdjust.ToneDelta,
                                     to params: DevelopParameters) -> DevelopParameters {
        var p = params
        p.exposure = adjustment.exposure
        p.contrast = adjustment.contrast
        p.density = adjustment.density
        p.highlight = adjustment.highlight
        p.shadow = adjustment.shadow
        p.whites = adjustment.whites
        p.blacks = adjustment.blacks
        p.vibrance = adjustment.vibrance
        return p
    }

    /// 자동 보정 기준용 중립 스냅샷: 대상 슬라이더만 0 으로 리셋(base/profile/preset/geometry 는 유지).
    /// 작은 프록시(500px)로 렌더해 통계만 빠르게 낸다.
    func neutralSnapshot(_ frame: ScanFrame, clearTone: Bool = false, clearWB: Bool = false) -> DevelopFrameSnapshot {
        var p = frame.params
        if clearTone {
            p.exposure = 0; p.contrast = 0; p.density = 0
            p.highlight = 0; p.shadow = 0; p.whites = 0; p.blacks = 0
            p.curveHighlights = 0; p.curveLights = 0; p.curveDarks = 0; p.curveShadows = 0
            p.vibrance = 0; p.saturation = 0; p.colorDepth = 0
        }
        if clearWB { p.warmth = 0; p.tint = 0 }
        return autoAdjustSnapshot(frame, params: p)
    }

    /// 자동 보정용 500px 스냅샷(주어진 파라미터 그대로).
    func autoAdjustSnapshot(_ frame: ScanFrame, params p: DevelopParameters) -> DevelopFrameSnapshot {
        let cleanedIdentity = frame.boundDefectRecipeIdentity
        let baseKey = FilmBaseCacheKey(filmType: frame.filmType, mode: p.baseEstimationMode,
            manualBaseRGB: p.manualBaseRGB, filmStockDminID: p.filmStockDminID,
            lightSourceProfileID: p.lightSourceProfileID, imageTransform: frame.imageTransform)
        return DevelopFrameSnapshot(
            rawScanURL: frame.rawScanURL,
            sourceKind: frame.sourceKind,
            preloadedRaw: frame.identityMatchedCleanedRawImage,
            // 화면이 이미 메모리에 올린 raw 프록시를 GPU 로 500px 로 줄인다. 원본(수백 MB TIFF)을
            // 매번 디스크에서 다시 디코드하던 것이 자동 톤·WB 지연의 대부분이었다(2026-10-15 실측
            // 릴리스: 디스크 0.55~1.17s → 메모리 0.045~0.067s, 자동 톤은 렌더 2 회).
            preloadedFullPreviewRaw: cachedSettledPreviewRaw(for: frame) ?? cachedInteractivePreviewRaw(for: frame),
            cleanedRawURL: frame.identityMatchedCleanedRawDiskURL,
            filmType: frame.filmType,
            params: p,
            preset: frame.preset,
            imageTransform: frame.imageTransform,
            // 화면용 base는 3600px 렌더가 끝나며 교체됩니다. 자동 보정은 매번 같은
            // 500px 입력에서 측정해야 cold/warm 상태와 반복 클릭에 따라 값이 달라지지 않습니다.
            cachedBase: nil,
            baseKey: baseKey,
            needsRawPreview: false, needsNeutralPreview: false, needsDebugPreviews: false,
            proxyMaxDimension: 500,
            needsThumbnail: false,
            cleanedRawFrameID: cleanedIdentity == nil ? nil : frame.id,
            cleanedRawIdentity: cleanedIdentity,
            requiresCleanedRaw: frame.requiresCleanedRawForActiveDefects
        )
    }
}
