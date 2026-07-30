import AppKit
import Chromabase
import SwiftUI

struct PrintCanvasView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settingsStore: PrintWorkspaceSettingsStore
    @ObservedObject var activeFrame: ScanFrame
    let frames: [ScanFrame]

    @State private var viewport = CanvasViewportState()

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            ZStack {
                page(canvasSize: canvasSize)
                    .scaleEffect(viewport.scale)
                    .offset(viewport.offset)
                    .gesture(
                        panGesture(canvasSize: canvasSize),
                        // 여러 장을 세로로 넘겨 보는 동안에는 끌기가 스크롤과 싸운다.
                        isEnabled: !usesVerticalPageScroll
                    )
                    .gesture(magnifyGesture(canvasSize: canvasSize))

                CanvasToolHUD(
                    zoomText: viewport.zoomText,
                    onZoomOut: { setScale(viewport.scale / 1.25, canvasSize: canvasSize) },
                    onZoomIn: { setScale(viewport.scale * 1.25, canvasSize: canvasSize) },
                    onSetZoomPercent: { setScale($0 / 100, canvasSize: canvasSize) },
                    onFit: { viewport.reset() },
                    onActualSize: { setScale(1, canvasSize: canvasSize) }
                )
                .fixedSize()
                .position(
                    x: canvasSize.width - 96,
                    y: canvasSize.height - 28
                )
                .accessibilityIdentifier("negaflow.print.zoom")
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
        }
        .background(model.canvasBackground.color)
        .contentShape(Rectangle())
        .contextMenu {
            CanvasBackgroundMenu()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("negaflow.print.canvas")
        .task(id: packagePreviewTaskID) {
            // 여러 장을 세로로 늘어놓는 레이아웃도 패키지와 같은 가벼운 프리뷰를 재사용한다.
            guard settingsStore.layoutMode.packageMode != nil || frames.count > 1 else { return }
            model.preparePrintPackagePreviews(for: frames)
        }
        .onChange(of: settingsStore.layoutMode) { _, _ in viewport.reset() }
    }

    /// 사진 한 장당 한 페이지인 레이아웃에서 여러 장을 골랐는가.
    private var usesVerticalPageScroll: Bool {
        settingsStore.layoutMode.usesVerticalPageStack(sourceCount: frames.count)
    }

    @ViewBuilder
    private func page(canvasSize: CGSize) -> some View {
        if let package = settingsStore.effectivePackageSettings(sourceCount: frames.count) {
            PrintPackageCanvasView(
                settingsStore: settingsStore,
                frames: frames,
                package: package,
                paperColor: paperColor
            )
        } else if usesVerticalPageScroll {
            singleImagePages(canvasSize: canvasSize)
        } else {
            singleImageCanvas
        }
    }

    /// 고른 사진마다 용지 한 장. 사이는 좁게 띄워 어디서 끊기는지 보이게 한다.
    private func singleImagePages(canvasSize: CGSize) -> some View {
        let pageHeight = max(220, canvasSize.height - 24)
        return ScrollView(.vertical) {
            LazyVStack(spacing: 10) {
                ForEach(frames) { frame in
                    PrintSingleImagePageView(
                        settingsStore: settingsStore,
                        frame: frame
                    )
                    .frame(height: pageHeight)
                    .accessibilityIdentifier("negaflow.print.page.\(frame.id.uuidString)")
                }
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.automatic)
    }

    /// 확대·이동은 종이 전체를 대상으로 한다. 지면과 캔버스를 같은 크기로 보고 여백을 묶어,
    /// 100% 에서는 움직이지 않고 확대한 만큼만 끌 수 있게 한다.
    private func panGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                viewport.updatePan(
                    translation: value.translation,
                    imageSize: NSSize(width: canvasSize.width, height: canvasSize.height),
                    canvasSize: canvasSize
                )
            }
            .onEnded { _ in viewport.endPan() }
    }

    private func magnifyGesture(canvasSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                setScale(viewport.lastScale * value.magnification, canvasSize: canvasSize)
            }
            .onEnded { _ in viewport.lastScale = viewport.scale }
    }

    private func setScale(_ scale: CGFloat, canvasSize: CGSize) {
        viewport.setScale(
            scale,
            imageSize: NSSize(width: canvasSize.width, height: canvasSize.height),
            canvasSize: canvasSize
        )
    }

    /// 시트에 올라간 프레임 구성이나 레이아웃이 바뀔 때만 미리보기 준비를 다시 요청한다.
    private var packagePreviewTaskID: String {
        settingsStore.layoutMode.rawValue
            + "|"
            + frames.map(\.id.uuidString).joined(separator: ",")
    }

    private var singleImageCanvas: some View {
        PrintSingleImagePageView(
            settingsStore: settingsStore,
            frame: activeFrame
        )
        .accessibilityIdentifier("negaflow.print.page.\(activeFrame.id.uuidString)")
    }

    private var paperColor: Color {
        guard let rgb = SoftProof.simulatedPaperWhiteRGB(
            for: model.displaySoftProofSettings(for: activeFrame)
        ) else {
            return .white
        }
        return Color(
            red: min(max(rgb.x, 0), 1),
            green: min(max(rgb.y, 0), 1),
            blue: min(max(rgb.z, 0), 1)
        )
    }
}

private struct PrintSingleImagePageView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settingsStore: PrintWorkspaceSettingsStore
    @ObservedObject var frame: ScanFrame

    var body: some View {
        GeometryReader { proxy in
            if let image = frame.developedImage
                ?? frame.rawPreviewImage
                ?? frame.thumbnailImage,
               let layout = previewLayout(for: image) {
                let paperRect = aspectFit(
                    layout.canvasSize,
                    in: CGRect(origin: .zero, size: proxy.size).insetBy(dx: 30, dy: 24)
                )
                let scale = paperRect.width / layout.canvasSize.width
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(paperColor)
                        .frame(width: paperRect.width, height: paperRect.height)
                        .position(x: paperRect.midX, y: paperRect.midY)

                    if let filmRect = layout.filmRect {
                        Rectangle()
                            .fill(filmColor)
                            .frame(
                                width: filmRect.width * scale,
                                height: filmRect.height * scale
                            )
                            .position(convertedCenter(
                                of: filmRect,
                                layout: layout,
                                paperRect: paperRect,
                                scale: scale
                            ))
                    }

                    presentedImage(image)
                        .frame(
                            width: layout.imageRect.width * scale,
                            height: layout.imageRect.height * scale
                        )
                        .position(convertedCenter(
                            of: layout.imageRect,
                            layout: layout,
                            paperRect: paperRect,
                            scale: scale
                        ))

                    if settingsStore.outputProcess == .cPrint {
                        PrintPaperSurfaceOverlay(surface: settingsStore.cPrintPaperSurface)
                            .frame(width: paperRect.width, height: paperRect.height)
                            .position(x: paperRect.midX, y: paperRect.midY)
                    }

                    if model.displaySoftProofSettings(for: frame).isEnabled,
                       model.destinationGamutWarningEnabled,
                       model.destinationGamutWarningAvailable,
                       frame.displayedSoftProofRevision == model.softProofConfigurationRevision,
                       let overlay = frame.destinationGamutOverlayImage {
                        Image(nsImage: overlay)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: layout.imageRect.width * scale,
                                height: layout.imageRect.height * scale
                            )
                            .position(convertedCenter(
                                of: layout.imageRect,
                                layout: layout,
                                paperRect: paperRect,
                                scale: scale
                            ))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    ForEach(Array(layout.perforationRects.enumerated()), id: \.offset) { _, rect in
                        RoundedRectangle(cornerRadius: max(1, layout.perforationCornerRadius * scale))
                            .fill(paperColor)
                            .frame(width: rect.width * scale, height: rect.height * scale)
                            .position(convertedCenter(
                                of: rect,
                                layout: layout,
                                paperRect: paperRect,
                                scale: scale
                            ))
                    }

                    Rectangle()
                        .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                        .frame(width: paperRect.width, height: paperRect.height)
                        .position(x: paperRect.midX, y: paperRect.midY)
                }
            } else {
                ContentUnavailableView(model.text(.noFrame), systemImage: "printer")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var paperColor: Color {
        guard let rgb = SoftProof.simulatedPaperWhiteRGB(
            for: model.displaySoftProofSettings(for: frame)
        ) else {
            return .white
        }
        return Color(
            red: min(max(rgb.x, 0), 1),
            green: min(max(rgb.y, 0), 1),
            blue: min(max(rgb.z, 0), 1)
        )
    }

    private var filmColor: Color {
        let rgba = PrintFilmStripAppearance(filmType: frame.filmType).baseRGBA
        return Color(
            red: rgba.x,
            green: rgba.y,
            blue: rgba.z,
            opacity: rgba.w
        )
    }

    @ViewBuilder
    private func presentedImage(_ image: NSImage) -> some View {
        switch settingsStore.layoutMode.presentationStyle {
        case .standard:
            sourceImage(image)
        case .cyanotype:
            let appearance = PrintPresentationAppearance(style: .cyanotype)
            ZStack {
                color(appearance.highlightRGBA)
                color(appearance.shadowRGBA)
                    .mask {
                        sourceImage(image)
                            .grayscale(1)
                            .colorInvert()
                            .luminanceToAlpha()
                    }
            }
        case .glassPlate:
            sourceImage(image)
                .grayscale(1)
                .colorInvert()
        case .gelatinSilver:
            sourceImage(image)
                .grayscale(1)
        }
    }

    private func sourceImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private func color(_ rgba: SIMD4<Double>) -> Color {
        Color(
            red: rgba.x,
            green: rgba.y,
            blue: rgba.z,
            opacity: rgba.w
        )
    }

    private func previewLayout(for image: NSImage) -> PrintCompositionLayout? {
        let sourceSize = image.representations.first.map {
            CGSize(width: $0.pixelsWide, height: $0.pixelsHigh)
        } ?? image.size
        // "사진 비율" 용지는 이 페이지의 사진을 따라간다 — 여러 장을 세로로 늘어놓아도
        // 각 장이 자기 비율의 종이 위에 놓인다.
        var settings = settingsStore.compositionSettings(dpi: 72)
        settings.photoAspectRatio = sourceSize.height > 0
            ? Double(sourceSize.width / sourceSize.height)
            : nil
        return PrintCompositionLayout.make(sourceSize: sourceSize, settings: settings)
    }

    private func aspectFit(_ size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func convertedCenter(
        of rect: CGRect,
        layout: PrintCompositionLayout,
        paperRect: CGRect,
        scale: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: paperRect.minX + rect.midX * scale,
            y: paperRect.minY + (layout.canvasSize.height - rect.midY) * scale
        )
    }
}

struct PrintPaperSurfaceOverlay: View {
    let surface: PrintPaperSurface

    var body: some View {
        surfaceAppearance
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var surfaceAppearance: some View {
        switch surface {
        case .glossy:
            LinearGradient(
                colors: [
                    .white.opacity(0.02),
                    .white.opacity(0.18),
                    .clear,
                    .black.opacity(0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .matte:
            Color.clear
        case .lustre:
            surfaceLines(crossed: false, spacing: 5)
        case .silk:
            surfaceLines(crossed: true, spacing: 7)
        }
    }

    private func surfaceLines(crossed: Bool, spacing: CGFloat) -> some View {
        Canvas { context, size in
            var rising = Path()
            for offset in stride(
                from: -size.height,
                through: size.width,
                by: spacing
            ) {
                rising.move(to: CGPoint(x: offset, y: size.height))
                rising.addLine(to: CGPoint(x: offset + size.height, y: 0))
            }
            context.stroke(
                rising,
                with: .color(.white.opacity(0.10)),
                lineWidth: 0.45
            )

            guard crossed else { return }
            var falling = Path()
            for offset in stride(
                from: 0,
                through: size.width + size.height,
                by: spacing
            ) {
                falling.move(to: CGPoint(x: offset, y: 0))
                falling.addLine(to: CGPoint(x: offset - size.height, y: size.height))
            }
            context.stroke(
                falling,
                with: .color(.black.opacity(0.055)),
                lineWidth: 0.45
            )
        }
    }
}
