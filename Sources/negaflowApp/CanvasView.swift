import SwiftUI
import AppKit
import Chromabase

enum CanvasCompareMode: String {
    case raw
    case developed
    case splitVertical
    case splitHorizontal
}

/// 좌우/상하 비교에서 "Before"로 보여줄 대상.
///  - unedited: 무보정 현상본(Target main, 프로파일/조정 없음) — 기본값.
///  - raw: 반전 전 raw 스캔.
enum CompareBeforeContent: String, CaseIterable {
    case unedited
    case raw

    var label: String {
        switch self {
        case .unedited: return "Unedited"
        case .raw: return "Raw"
        }
    }
}

struct CanvasView: View {
    @ObservedObject var frame: ScanFrame
    @EnvironmentObject var model: AppModel
    @Binding var cropMode: Bool
    @Binding var brushMode: Bool
    @Binding var regionICEMode: Bool
    @Binding var localDodgeBurnMode: Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    // 크롭 진입 시점의 엔진 크롭(취소 시 복원용). nil = 크롭 없음.
    @State private var preCropRect: SIMD4<Double>?
    @State private var brushThickness: CGFloat = 0.010
    @State private var brushStrokes: [DefectStroke] = []
    @State private var brushCurrent: [CGPoint] = []
    @State private var localMode: LocalDodgeBurnMode = .dodge
    @State private var localShape: LocalDodgeBurnToolShape = .brush
    @State private var localAmount: Double = 0.45
    @State private var localThickness: Double = 0.06
    @State private var localFeather: Double = 0.04
    @State private var localBrushStrokes: [LocalDodgeBurnStroke] = []
    @State private var localCurrentPoints: [LocalDodgeBurnPoint] = []
    @State private var localDragStart: LocalDodgeBurnPoint?
    @State private var localDragCurrent: LocalDodgeBurnPoint?
    @State private var localPolygonPoints: [LocalDodgeBurnPoint] = []
    @State private var compareMode: CanvasCompareMode = .developed
    @State private var previousCompareMode: CanvasCompareMode = .raw
    @AppStorage("compare.beforeContent") private var beforeContentRaw: String = CompareBeforeContent.unedited.rawValue

    private let minScale: CGFloat = 0.2
    private let maxScale: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let image = referenceImage
            let imageSize = image?.size
            ZStack(alignment: .topLeading) {
                model.canvasBackground.color
                if let img = image {
                    let imageFrame = fittedImageFrame(for: img.size, in: geo.size)
                    imageLayer(in: imageFrame)
                    if cropMode {
                        CropOverlay(
                            cropRect: $cropRect,
                            imageFrame: imageFrame,
                            onApply: applyCrop,
                            onReset: resetCrop,
                            onCancel: cancelCrop
                        )
                    }
                    if brushMode {
                        BrushOverlay(
                            strokes: $brushStrokes,
                            current: $brushCurrent,
                            thickness: brushThickness,
                            imageFrame: imageFrame
                        )
                    }
                    if regionICEMode {
                        RegionICEOverlay(frame: frame, imageFrame: imageFrame)
                    }
                    if localDodgeBurnMode {
                        LocalDodgeBurnOverlay(
                            shape: $localShape,
                            brushStrokes: $localBrushStrokes,
                            currentPoints: $localCurrentPoints,
                            dragStart: $localDragStart,
                            dragCurrent: $localDragCurrent,
                            polygonPoints: $localPolygonPoints,
                            mode: localMode,
                            thickness: localThickness,
                            imageFrame: imageFrame
                        )
                    }
                    canvasHUD(imageSize: img.size, canvasSize: geo.size)
                    debugStageBadge
                        .padding(10)
                }
                if canCompare && !isDebugPreviewActive {
                    beforeAfterToggle
                        .padding(10)
                }
            }
            .coordinateSpace(name: canvasCoordinateSpace)
            .contentShape(Rectangle())
            .gesture(panGesture(imageSize: imageSize, canvasSize: geo.size))
            .simultaneousGesture(zoomGesture(imageSize: imageSize, canvasSize: geo.size))
            .contextMenu { canvasBackgroundMenu }
        }
        .onAppear { updateCompareGating() }
        .onDisappear { model.beforeAfterCompareActive = false }
        .onChange(of: beforeContentRaw) { _, _ in updateCompareGating() }
        .onChange(of: cropMode) { _, isOn in
            if isOn {
                // 크롭 진입: 현재 크롭을 일시 해제해 **원본 전체**를 보여주고, 기존 크롭을 선택
                // 영역으로 미리 채운다. 이렇게 해야 핸들을 바깥으로 끌어 잘렸던 영역을 다시 키울 수 있다.
                preCropRect = frame.imageTransform.cropRect
                cropRect = displayRect(for: frame.imageTransform.cropRect)
                if frame.imageTransform.cropRect != nil {
                    frame.updateTransform { $0.cropRect = nil }
                    model.applyTransformFast(frame)
                }
            }
        }
        .onChange(of: frame.imageTransform.displayName) { _, _ in
            if !cropMode {
                resetViewport(animated: false)
            }
        }
        .background {
            Group {
                // ⌘Z: 마지막 결함 제거 복구(다단계). 숨김 버튼으로 단축키만 받는다.
                Button("") { model.undoDefects(frame) }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!frame.canUndoDefects)

                Button("") { toggleDevelopedShortcut() }
                    .keyboardShortcut("\\", modifiers: [])
                    .disabled(!canCompare)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    var activeCompareMode: CanvasCompareMode {
        guard canCompare else { return frame.showDeveloped ? .developed : .raw }
        return compareMode
    }

    var beforeContent: CompareBeforeContent {
        CompareBeforeContent(rawValue: beforeContentRaw) ?? .unedited
    }

    /// Before(좌/상)에 표시할 이미지. 무보정본 우선, 없으면 raw로 폴백(또는 사용자 선택이 raw).
    var beforeImage: NSImage? {
        switch beforeContent {
        case .unedited:
            return frame.neutralPreviewImage ?? frame.rawPreviewImage
        case .raw:
            return frame.rawPreviewImage ?? frame.neutralPreviewImage
        }
    }

    var canCompare: Bool {
        beforeImage != nil && frame.developedImage != nil
    }

    var referenceImage: NSImage? {
        if let debugPreviewImage {
            return debugPreviewImage
        }
        switch activeCompareMode {
        case .raw:
            return frame.rawPreviewImage ?? frame.developedImage ?? frame.thumbnailImage
        case .developed, .splitVertical, .splitHorizontal:
            // 메모리 FIFO로 풀해상도가 내려간 프레임을 재진입하면 재현상이 끝나기 전까지 썸네일을 보여준다.
            return frame.developedImage ?? frame.rawPreviewImage ?? frame.thumbnailImage
        }
    }

    var isDebugPreviewActive: Bool {
        frame.debugOverlayEnabled && debugPreviewImage != nil
    }

    var debugPreviewImage: NSImage? {
        guard frame.debugOverlayEnabled else { return nil }
        return frame.debugPreviewImages[frame.debugOverlayStage]
    }

    @ViewBuilder
    var beforeContentMenu: some View {
        Text("Before")
        ForEach(CompareBeforeContent.allCases, id: \.self) { option in
            Button {
                beforeContentRaw = option.rawValue
            } label: {
                if beforeContent == option {
                    Label(option.label, systemImage: "checkmark")
                } else {
                    Text(option.label)
                }
            }
        }
    }

    @ViewBuilder
    var canvasBackgroundMenu: some View {
        Text("배경색")
        ForEach(CanvasBackground.allCases) { bg in
            Button {
                model.canvasBackground = bg
            } label: {
                if model.canvasBackground == bg {
                    Label(bg.label, systemImage: "checkmark")
                } else {
                    Text(bg.label)
                }
            }
        }
    }

    @ViewBuilder
    func imageLayer(in imageFrame: CGRect) -> some View {
        if let debugPreviewImage {
            fittedImage(debugPreviewImage, in: imageFrame)
                .onTapGesture(count: 2) { resetViewport() }
        } else {
            switch activeCompareMode {
            case .raw:
                if let image = frame.rawPreviewImage ?? frame.developedImage ?? frame.thumbnailImage {
                    fittedImage(image, in: imageFrame)
                        .onTapGesture(count: 2) { resetViewport() }
                }
            case .developed:
                if let image = frame.developedImage ?? frame.rawPreviewImage ?? frame.thumbnailImage {
                    fittedImage(image, in: imageFrame)
                        .onTapGesture(count: 2) { resetViewport() }
                }
            case .splitVertical:
                if let before = beforeImage, let after = frame.developedImage {
                    splitVerticalImage(before: before, after: after, in: imageFrame)
                    compareLabels(in: imageFrame, vertical: true)
                }
            case .splitHorizontal:
                if let before = beforeImage, let after = frame.developedImage {
                    splitHorizontalImage(before: before, after: after, in: imageFrame)
                    compareLabels(in: imageFrame, vertical: false)
                }
            }
        }
    }

    @ViewBuilder
    var debugStageBadge: some View {
        if isDebugPreviewActive {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg.rectangle")
                Text("Debug · \(frame.debugOverlayStage.displayName)")
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .liquidSurface(cornerRadius: 7)
        }
    }

    func fittedImage(_ image: NSImage, in imageFrame: CGRect) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: imageFrame.width, height: imageFrame.height)
            .position(x: imageFrame.midX, y: imageFrame.midY)
    }

    func localImage(_ image: NSImage, width: CGFloat, height: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
    }

    func splitVerticalImage(before: NSImage, after: NSImage, in imageFrame: CGRect) -> some View {
        ZStack {
            localImage(after, width: imageFrame.width, height: imageFrame.height)
            HStack(spacing: 0) {
                localImage(before, width: imageFrame.width, height: imageFrame.height)
                    .frame(width: imageFrame.width / 2, alignment: .leading)
                    .clipped()
                Spacer(minLength: 0)
            }
            .frame(width: imageFrame.width, height: imageFrame.height)
            Rectangle()
                .fill(.white.opacity(0.75))
                .frame(width: 1, height: imageFrame.height)
        }
        .frame(width: imageFrame.width, height: imageFrame.height)
        .position(x: imageFrame.midX, y: imageFrame.midY)
    }

    func splitHorizontalImage(before: NSImage, after: NSImage, in imageFrame: CGRect) -> some View {
        ZStack {
            localImage(after, width: imageFrame.width, height: imageFrame.height)
            VStack(spacing: 0) {
                localImage(before, width: imageFrame.width, height: imageFrame.height)
                    .frame(height: imageFrame.height / 2, alignment: .top)
                    .clipped()
                Spacer(minLength: 0)
            }
            .frame(width: imageFrame.width, height: imageFrame.height)
            Rectangle()
                .fill(.white.opacity(0.75))
                .frame(width: imageFrame.width, height: 1)
        }
        .frame(width: imageFrame.width, height: imageFrame.height)
        .position(x: imageFrame.midX, y: imageFrame.midY)
    }

    func compareLabels(in imageFrame: CGRect, vertical: Bool) -> some View {
        ZStack {
            HStack(spacing: 4) {
                Text(beforeContent.label)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .liquidSurface(cornerRadius: 6)
                .contextMenu { beforeContentMenu }
                .position(
                    x: imageFrame.minX + 48,
                    y: imageFrame.minY + 48
                )
            Text("After")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .liquidSurface(cornerRadius: 6)
                .position(
                    x: vertical ? imageFrame.maxX - 38 : imageFrame.minX + 36,
                    y: vertical ? imageFrame.minY + 48 : imageFrame.maxY - 18
                )
        }
    }

    @ViewBuilder
    func canvasHUD(imageSize: NSSize, canvasSize: CGSize) -> some View {
        VStack {
            if brushMode {
                HStack {
                    Spacer()
                    BrushControlBar(
                        thickness: $brushThickness,
                        hasStrokes: !brushStrokes.isEmpty || frame.canUndoDefects,
                        hasAppliedDefects: !frame.defectEdits.isEmpty,
                        isBusy: frame.isRemovingDefects,
                        onApply: applyBrush,
                        onUndo: {
                            // 칠하던 스트로크가 남아 있으면 그걸, 없으면 적용된 결함 제거를 취소(⌘Z와 동일).
                            if !brushStrokes.isEmpty { _ = brushStrokes.popLast() }
                            else { model.undoDefects(frame) }
                        },
                        onClear: { brushStrokes.removeAll() },
                        onResetAll: { model.clearAllDefects(frame) }
                    )
                    Spacer()
                }
                .padding(.top, 12)
            }
            if localDodgeBurnMode {
                HStack {
                    Spacer()
                    LocalDodgeBurnControlBar(
                        mode: $localMode,
                        shape: $localShape,
                        amount: $localAmount,
                        thickness: $localThickness,
                        feather: $localFeather,
                        appliedCount: frame.params.localDodgeBurn.count,
                        canApply: canApplyLocalDodgeBurnDraft,
                        canUndoDraft: canUndoLocalDodgeBurnDraft,
                        onApply: applyLocalDodgeBurn,
                        onUndo: undoLocalDodgeBurnDraft,
                        onClearDraft: clearLocalDodgeBurnDraft,
                        onResetApplied: resetLocalDodgeBurn
                    )
                    Spacer()
                }
                .padding(.top, 12)
            }
            Spacer()
            HStack {
                Spacer()
                CanvasToolHUD(
                    zoomText: "\(Int((scale * 100).rounded()))%",
                    cropMode: cropMode,
                    brushMode: brushMode,
                    regionICEMode: regionICEMode,
                    localDodgeBurnMode: localDodgeBurnMode,
                    onZoomOut: { setScale(scale / 1.25, imageSize: imageSize, canvasSize: canvasSize) },
                    onZoomIn: { setScale(scale * 1.25, imageSize: imageSize, canvasSize: canvasSize) },
                    onFit: { resetViewport() },
                    onActualSize: { setScale(actualSizeScale(imageSize, in: canvasSize), imageSize: imageSize, canvasSize: canvasSize) },
                    onCrop: { withAnimation(.snappy(duration: 0.18)) { cropMode.toggle(); if cropMode { brushMode = false; regionICEMode = false; localDodgeBurnMode = false } } },
                    onBrush: { withAnimation(.snappy(duration: 0.18)) { brushMode.toggle(); if brushMode { cropMode = false; regionICEMode = false; localDodgeBurnMode = false } } },
                    onRegionICE: { withAnimation(.snappy(duration: 0.18)) { regionICEMode.toggle(); if regionICEMode { cropMode = false; brushMode = false; localDodgeBurnMode = false } } },
                    onLocalDodgeBurn: { withAnimation(.snappy(duration: 0.18)) { localDodgeBurnMode.toggle(); if localDodgeBurnMode { cropMode = false; brushMode = false; regionICEMode = false } } }
                )
                .padding(.trailing, 14)
                .padding(.bottom, 12)
            }
        }
    }

    private func applyBrush() {
        guard !brushStrokes.isEmpty else { return }
        let strokes = brushStrokes
        brushStrokes.removeAll()
        // 표시 좌표 스트로크를 base 좌표로 변환·누적하고 ICE를 재적용(변형/재현상 후에도 유지).
        model.applyDefectStrokes(strokes, to: frame)
    }

    private var canApplyLocalDodgeBurnDraft: Bool {
        switch localShape {
        case .brush:
            return !localBrushStrokes.isEmpty || !localCurrentPoints.isEmpty
        case .radial, .linear:
            return localDragStart != nil && localDragCurrent != nil
        case .polygon:
            return localPolygonPoints.count >= 3
        }
    }

    private var canUndoLocalDodgeBurnDraft: Bool {
        switch localShape {
        case .brush:
            return !localBrushStrokes.isEmpty || !localCurrentPoints.isEmpty
        case .radial, .linear:
            return localDragStart != nil || localDragCurrent != nil
        case .polygon:
            return !localPolygonPoints.isEmpty
        }
    }

    private func applyLocalDodgeBurn() {
        guard let mask = localDodgeBurnMaskFromDraft() else { return }
        let adjustment = LocalDodgeBurnAdjustment(mode: localMode, amount: localAmount, mask: mask)
        frame.updateParams { $0.localDodgeBurn.append(adjustment) }
        clearLocalDodgeBurnDraft()
        model.requestDevelop(frame)
    }

    private func localDodgeBurnMaskFromDraft() -> LocalDodgeBurnMask? {
        switch localShape {
        case .brush:
            var strokes = localBrushStrokes
            if !localCurrentPoints.isEmpty {
                strokes.append(LocalDodgeBurnStroke(points: localCurrentPoints, thickness: localThickness, feather: localFeather))
            }
            return strokes.isEmpty ? nil : .brush(strokes: strokes.map {
                LocalDodgeBurnStroke(points: $0.points, thickness: $0.thickness, feather: localFeather)
            })
        case .radial:
            guard let start = localDragStart, let current = localDragCurrent else { return nil }
            let dx = current.x - start.x
            let dy = current.y - start.y
            let radius = max(0.01, hypot(dx * max(1, referenceImage?.size.width ?? 1), dy * max(1, referenceImage?.size.height ?? 1)) / max(1, min(referenceImage?.size.width ?? 1, referenceImage?.size.height ?? 1)))
            return .radial(center: start, radius: radius, feather: localFeather)
        case .linear:
            guard let start = localDragStart, let current = localDragCurrent else { return nil }
            return .linear(start: start, end: current, feather: localFeather)
        case .polygon:
            guard localPolygonPoints.count >= 3 else { return nil }
            return .polygon(points: localPolygonPoints, feather: localFeather)
        }
    }

    private func undoLocalDodgeBurnDraft() {
        switch localShape {
        case .brush:
            if !localCurrentPoints.isEmpty {
                localCurrentPoints = []
            } else {
                _ = localBrushStrokes.popLast()
            }
        case .radial, .linear:
            localDragStart = nil
            localDragCurrent = nil
        case .polygon:
            _ = localPolygonPoints.popLast()
        }
    }

    private func clearLocalDodgeBurnDraft() {
        localBrushStrokes = []
        localCurrentPoints = []
        localDragStart = nil
        localDragCurrent = nil
        localPolygonPoints = []
    }

    private func resetLocalDodgeBurn() {
        guard !frame.params.localDodgeBurn.isEmpty else { return }
        frame.updateParams { $0.localDodgeBurn = [] }
        clearLocalDodgeBurnDraft()
        model.requestDevelop(frame)
    }

    var beforeAfterToggle: some View {
        HStack(spacing: 2) {
            compareButton(title: "Raw", mode: .raw)
            compareButton(title: "Developed", mode: .developed)
            compareIconButton(systemName: "rectangle.lefthalf.inset.filled", help: "좌우 Before/After", mode: .splitVertical)
            compareIconButton(systemName: "rectangle.tophalf.inset.filled", help: "상하 Before/After", mode: .splitHorizontal)
        }
        .padding(2)
        .liquidSurface(cornerRadius: 10, interactive: true)
    }

    func compareButton(title: String, mode: CanvasCompareMode) -> some View {
        let active = activeCompareMode == mode
        return Button {
            selectCompareMode(mode)
        } label: {
            Text(title)
                .font(.caption.weight(active ? .semibold : .regular))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .foregroundStyle(active ? Color.primary : Color.secondary)
                .background(active ? Color.primary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    func compareIconButton(systemName: String, help: String, mode: CanvasCompareMode) -> some View {
        let active = activeCompareMode == mode
        return Button {
            selectCompareMode(mode)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 24)
                .foregroundStyle(active ? Color.primary : Color.secondary)
                .background(active ? Color.primary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func selectCompareMode(_ mode: CanvasCompareMode) {
        withAnimation(.snappy(duration: 0.16)) {
            compareMode = mode
            frame.showDeveloped = mode != .raw
            if mode != .developed {
                previousCompareMode = mode
            }
        }
        updateCompareGating()
    }

    private var isComparingSplit: Bool {
        activeCompareMode == .splitVertical || activeCompareMode == .splitHorizontal
    }

    /// 무보정 프리뷰는 좌우/상하 비교가 떠 있을 때만 의미가 있다. 비교 진입 시에만 플래그를 켜고,
    /// (필요하면) 무보정본이 없거나 stale 일 때 1회 현상해 채운다. 비교를 안 보면 추가 패스를 안 돈다.
    private func updateCompareGating() {
        let active = isComparingSplit
        if model.beforeAfterCompareActive != active {
            model.beforeAfterCompareActive = active
        }
        guard active else { return }
        let baseKey = FilmBaseCacheKey(
            filmType: frame.filmType,
            mode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            filmStockDminID: frame.params.filmStockDminID
        )
        let stale = frame.neutralPreviewImage == nil
            || frame.neutralPreviewTransform != frame.imageTransform
            || frame.neutralPreviewBaseKey != baseKey
        if stale, !model.isScanning {
            Task { await model.developFrame(frame) }
        }
    }

    private func toggleDevelopedShortcut() {
        let target: CanvasCompareMode = activeCompareMode == .developed ? previousCompareMode : .developed
        selectCompareMode(target)
    }

    private func fitScale(_ s: NSSize, in c: CGSize) -> CGFloat {
        guard s.width > 0, s.height > 0, c.width > 0, c.height > 0 else { return 1 }
        return min(c.width / s.width, c.height / s.height)
    }

    private func fittedImageFrame(for imageSize: NSSize, in canvasSize: CGSize) -> CGRect {
        let fit = fitScale(imageSize, in: canvasSize) * scale
        let width = imageSize.width * fit
        let height = imageSize.height * fit
        return CGRect(
            x: (canvasSize.width - width) / 2 + offset.width,
            y: (canvasSize.height - height) / 2 + offset.height,
            width: width,
            height: height
        )
    }

    private func actualSizeScale(_ imageSize: NSSize, in canvasSize: CGSize) -> CGFloat {
        min(max(1 / fitScale(imageSize, in: canvasSize), minScale), maxScale)
    }

    private func resetViewport(animated: Bool = true) {
        let updates = {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
        if animated {
            withAnimation(.snappy(duration: 0.18)) { updates() }
        } else {
            updates()
        }
    }

    private func setScale(_ newScale: CGFloat, imageSize: NSSize, canvasSize: CGSize) {
        let clamped = min(max(newScale, minScale), maxScale)
        withAnimation(.snappy(duration: 0.16)) {
            scale = clamped
            lastScale = clamped
            offset = clampedOffset(offset, imageSize: imageSize, canvasSize: canvasSize, scale: clamped)
            lastOffset = offset
        }
    }

    private func panGesture(imageSize: NSSize?, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                guard let imageSize, !cropMode, !brushMode, !regionICEMode, !localDodgeBurnMode else { return }
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, imageSize: imageSize, canvasSize: canvasSize, scale: scale)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func zoomGesture(imageSize: NSSize?, canvasSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard let imageSize else { return }
                let next = min(max(lastScale * value, minScale), maxScale)
                scale = next
                offset = clampedOffset(offset, imageSize: imageSize, canvasSize: canvasSize, scale: next)
            }
            .onEnded { _ in
                lastScale = scale
                lastOffset = offset
            }
    }

    private func clampedOffset(_ proposed: CGSize, imageSize: NSSize, canvasSize: CGSize, scale: CGFloat) -> CGSize {
        let fit = fitScale(imageSize, in: canvasSize) * scale
        let imageWidth = imageSize.width * fit
        let imageHeight = imageSize.height * fit
        let limitX = max(48, (imageWidth - canvasSize.width) / 2 + 96)
        let limitY = max(48, (imageHeight - canvasSize.height) / 2 + 96)
        return CGSize(
            width: min(max(proposed.width, -limitX), limitX),
            height: min(max(proposed.height, -limitY), limitY)
        )
    }

    /// 엔진 크롭(y-up 정규좌표 (x, y, w, h))을 표시 좌표(y-down) 선택 사각형으로 변환.
    /// 크롭은 회전/플립 **이후** 마지막에 적용되므로 표시 좌표계와 동일 축이다(y만 뒤집음).
    private func displayRect(for crop: SIMD4<Double>?) -> CGRect {
        guard let c = crop else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return clampedUnitRect(CGRect(
            x: c.x,
            y: 1 - (c.y + c.w),
            width: c.z,
            height: c.w
        ))
    }

    private func applyCrop() {
        // 진입 시 크롭을 해제해 전체를 보고 있으므로, 선택 영역을 **절대 크롭**으로 그대로 설정한다(중첩 없음).
        frame.updateTransform {
            $0.cropRect = engineCrop(from: cropRect, existingCrop: nil)
        }
        cropMode = false
        resetViewport()
        model.applyTransformFast(frame)
    }

    private func resetCrop() {
        // "Full": 크롭 없음. 이미 전체를 보고 있으니 선택만 가득 채우고 복원 대상도 비운다.
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        preCropRect = nil
    }

    private func cancelCrop() {
        // 취소: 진입 시 해제했던 크롭을 되돌린다.
        if frame.imageTransform.cropRect != preCropRect {
            frame.updateTransform { $0.cropRect = preCropRect }
            model.applyTransformFast(frame)
        }
        cropMode = false
    }
}
