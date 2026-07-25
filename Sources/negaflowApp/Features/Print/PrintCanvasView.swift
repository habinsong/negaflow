import AppKit
import Chromabase
import SwiftUI

struct PrintCanvasView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settingsStore: PrintWorkspaceSettingsStore
    let activeFrame: ScanFrame
    let frames: [ScanFrame]

    var body: some View {
        Group {
            if let package = settingsStore.effectivePackageSettings(sourceCount: frames.count) {
                PrintPackageCanvasView(
                    settingsStore: settingsStore,
                    frames: frames,
                    package: package,
                    paperColor: paperColor
                )
            } else {
                singleImageCanvas
            }
        }
        .background(model.canvasBackground.color)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("negaflow.print.canvas")
    }

    private var singleImageCanvas: some View {
        GeometryReader { proxy in
            if let image = activeFrame.developedImage
                ?? activeFrame.rawPreviewImage
                ?? activeFrame.thumbnailImage,
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
                            .position(convertedCenter(of: filmRect, layout: layout, paperRect: paperRect, scale: scale))
                    }

                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: layout.imageRect.width * scale,
                            height: layout.imageRect.height * scale
                        )
                        .position(convertedCenter(of: layout.imageRect, layout: layout, paperRect: paperRect, scale: scale))

                    if model.softProofEnabled,
                       model.destinationGamutWarningEnabled,
                       model.destinationGamutWarningAvailable,
                       activeFrame.displayedSoftProofRevision == model.softProofConfigurationRevision,
                       let overlay = activeFrame.destinationGamutOverlayImage {
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
                            .position(convertedCenter(of: rect, layout: layout, paperRect: paperRect, scale: scale))
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
            for: model.printerSoftProofSettings
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
        let rgba = PrintFilmStripAppearance(filmType: activeFrame.filmType).baseRGBA
        return Color(
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
        return PrintCompositionLayout.make(
            sourceSize: sourceSize,
            settings: settingsStore.compositionSettings(dpi: 72)
        )
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
