import SwiftUI
import Chromabase
import AppKit

// 라이트룸식 자동 보정. 핵심은 "결정적(1회)": 대상 슬라이더를 0 으로 리셋한 **중립 현상본**을 기준으로
// 절대값을 계산해 슬라이더에 **대입**한다(누적 아님). 그래서 버튼을 여러 번 눌러도 같은 결과가 되고,
// 중립(톤 매핑 전) 기준이라 노출뿐 아니라 대비·화이트·블랙·바이브런스 등 모든 슬라이더가 의미있게 변한다.
// (현재 결과 기준 델타는 이미 보정된 상태라 노출 외에는 0 에 수렴 → 과거 버그였다.)
extension AppModel {
    /// 자동 화이트 밸런스(⇧⌘U) — Warmth/Tint 를 0 으로 둔 중립본의 평균색을 gray-world 로 무채색화.
    func autoWhiteBalance(_ frame: ScanFrame) {
        guard !isScanning else { return }
        let snapshot = neutralSnapshot(frame, clearWB: true)
        Task.detached(priority: .userInitiated) {
            guard let cg = try? DevelopFrameRenderer.render(snapshot).developed,
                  let s = AutoAdjust.imageStats(cg) else { return }
            let (w, t) = AutoAdjust.autoWhiteBalance(s)
            await MainActor.run {
                frame.params.warmth = w
                frame.params.tint = t
                self.statusMessage = "자동 화이트 밸런스"
                Task { await self.developFrame(frame) }
            }
        }
    }

    /// 자동 톤(⌘U) — 톤/색 조정을 0 으로 둔 중립본의 히스토그램으로 Exposure·Contrast·Highlights·
    /// Shadows·Whites·Blacks·Vibrance·Saturation 절대값을 계산해 대입. WB(Warmth/Tint)는 건드리지 않는다.
    func autoTone(_ frame: ScanFrame) {
        guard !isScanning else { return }
        let snapshot = neutralSnapshot(frame, clearTone: true)
        Task.detached(priority: .userInitiated) {
            guard let cg = try? DevelopFrameRenderer.render(snapshot).developed,
                  let s = AutoAdjust.imageStats(cg) else { return }
            let a = AutoAdjust.autoTone(s)
            await MainActor.run {
                var p = frame.params
                p.exposure = a.exposure
                p.contrast = a.contrast
                p.highlight = a.highlight
                p.shadow = a.shadow
                p.whites = a.whites
                p.blacks = a.blacks
                p.vibrance = a.vibrance
                p.saturation = a.saturation
                frame.params = p
                self.statusMessage = "자동 톤"
                Task { await self.developFrame(frame) }
            }
        }
    }

    /// 자동 보정 기준용 중립 스냅샷: 대상 슬라이더만 0 으로 리셋(base/profile/preset/geometry 는 유지).
    /// 작은 프록시(500px)로 렌더해 통계만 빠르게 낸다.
    private func neutralSnapshot(_ frame: ScanFrame, clearTone: Bool = false, clearWB: Bool = false) -> DevelopFrameSnapshot {
        var p = frame.params
        if clearTone {
            p.exposure = 0; p.contrast = 0; p.density = 0
            p.highlight = 0; p.shadow = 0; p.whites = 0; p.blacks = 0
            p.curveHighlights = 0; p.curveLights = 0; p.curveDarks = 0; p.curveShadows = 0
            p.vibrance = 0; p.saturation = 0; p.colorDepth = 0
        }
        if clearWB { p.warmth = 0; p.tint = 0 }
        return DevelopFrameSnapshot(
            rawScanURL: frame.rawScanURL,
            preloadedRaw: frame.cleanedRawImage,
            cleanedRawURL: frame.cleanedRawDiskURL,
            filmType: frame.filmType,
            params: p,
            preset: frame.preset,
            imageTransform: frame.imageTransform,
            cachedBase: frame.cachedBase,
            baseKey: FilmBaseCacheKey(filmType: frame.filmType, mode: p.baseEstimationMode,
                                      manualBaseRGB: p.manualBaseRGB, filmStockDminID: p.filmStockDminID),
            needsRawPreview: false, needsNeutralPreview: false, needsDebugPreviews: false,
            proxyMaxDimension: 500, needsThumbnail: false
        )
    }
}
