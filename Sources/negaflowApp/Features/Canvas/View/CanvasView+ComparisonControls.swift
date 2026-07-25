import SwiftUI
import AppKit
import Chromabase

extension CanvasView {
    var beforeAfterToggle: some View {
        CanvasCompareToggle(
            activeMode: activeCompareMode,
            onSelectMode: selectCompareMode
        )
    }

    func selectCompareMode(_ mode: CanvasCompareMode) {
        withAnimation(.snappy(duration: 0.16)) {
            compareMode = mode
            frame.showDeveloped = mode != .raw
            if mode != .developed {
                previousCompareMode = mode
            }
        }
        updateCompareGating()
    }

    var isComparingSplit: Bool {
        activeCompareMode == .splitVertical || activeCompareMode == .splitHorizontal
    }

    /// 무보정 프리뷰는 좌우/상하 비교가 떠 있을 때만 의미가 있다. 비교 진입 시에만 플래그를 켜고,
    /// (필요하면) 무보정본이 없거나 stale 일 때 1회 현상해 채운다. 비교를 안 보면 추가 패스를 안 돈다.
    func updateCompareGating() {
        let active = isComparingSplit
        if model.beforeAfterCompareActive != active {
            model.beforeAfterCompareActive = active
        }
        let mainActive = active
            && selectedBeforeID == CompareBeforeContent.main.rawValue
            && frame.params.developTarget != .main
        if model.beforeAfterMainCompareActive != mainActive {
            model.beforeAfterMainCompareActive = mainActive
        }
        guard active else { return }
        if selectedBeforeID == CompareBeforeContent.main.rawValue {
            let stale = frame.params.developTarget != .main
                && (frame.mainPreviewImage == nil
                    || frame.mainPreviewTransform != frame.imageTransform
                    || frame.mainPreviewDevelopRevision != frame.developRevision)
            if stale, !frame.isDeveloping {
                Task { await model.developFrame(frame) }
            }
            return
        }
        guard selectedBeforeID == CompareBeforeContent.unedited.rawValue else {
            if let comparison = comparisonFrame(for: selectedBeforeID),
               comparison.developedImage == nil,
               !comparison.isDeveloping {
                Task { await model.developFrame(comparison) }
            }
            return
        }
        let baseKey = FilmBaseCacheKey(
            filmType: frame.filmType,
            mode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            filmStockDminID: frame.params.filmStockDminID,
            lightSourceProfileID: frame.params.lightSourceProfileID
        )
        let stale = frame.neutralPreviewImage == nil
            || frame.neutralPreviewTransform != frame.imageTransform
            || frame.neutralPreviewBaseKey != baseKey
        if stale {
            Task { await model.developFrame(frame) }
        }
    }

    func toggleDevelopedShortcut() {
        let target: CanvasCompareMode = activeCompareMode == .developed ? previousCompareMode : .developed
        selectCompareMode(target)
    }


}
