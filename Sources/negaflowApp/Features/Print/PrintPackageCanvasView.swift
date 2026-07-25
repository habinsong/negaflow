import AppKit
import Chromabase
import SwiftUI

struct PrintPackageCanvasView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settingsStore: PrintWorkspaceSettingsStore
    let frames: [ScanFrame]
    let package: PrintPackageSettings
    let paperColor: Color
    @State private var selectedPage = 0
    @State private var selectedCustomItemIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            if let preview = previewData,
               !preview.pages.isEmpty {
                let pageIndex = min(max(selectedPage, 0), preview.pages.count - 1)
                let page = preview.pages[pageIndex]
                let paperRect = aspectFit(
                    page.canvasSizePoints,
                    in: CGRect(origin: .zero, size: proxy.size).insetBy(dx: 30, dy: 42)
                )
                let scale = paperRect.width / page.canvasSizePoints.width

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(paperColor)
                        .frame(width: paperRect.width, height: paperRect.height)
                        .position(x: paperRect.midX, y: paperRect.midY)

                    ForEach(Array(page.items.enumerated()), id: \.offset) { itemOffset, item in
                        if preview.sources.indices.contains(item.sourceIndex) {
                            let source = preview.sources[item.sourceIndex]
                            let destination = converted(
                                item.destinationRectPoints,
                                page: page,
                                paperRect: paperRect,
                                scale: scale
                            )
                            packageImage(
                                source.image,
                                item: item,
                                destination: destination
                            )
                            .zIndex(Double(itemOffset * 3))

                            if model.softProofEnabled,
                               model.destinationGamutWarningEnabled,
                               model.destinationGamutWarningAvailable,
                               let overlay = source.destinationGamutOverlay {
                                packageImage(
                                    overlay,
                                    item: item,
                                    destination: destination
                                )
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                                .zIndex(Double(itemOffset * 3 + 1))
                            }

                            if let captionRect = item.captionRectPoints,
                               let caption = source.caption,
                               !caption.isEmpty {
                                let convertedCaption = converted(
                                    captionRect,
                                    page: page,
                                    paperRect: paperRect,
                                    scale: scale
                                )
                                Text(caption)
                                    .font(.system(size: max(7, min(11, convertedCaption.height * 0.55))))
                                    .foregroundStyle(Color.black.opacity(0.92))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(
                                        width: convertedCaption.width,
                                        height: convertedCaption.height,
                                        alignment: .leading
                                    )
                                    .position(x: convertedCaption.midX, y: convertedCaption.midY)
                                    .zIndex(Double(itemOffset * 3 + 2))
                            }
                        }
                    }

                    if package.mode == .customPackage {
                        PrintCustomPackageCanvasOverlay(
                            settingsStore: settingsStore,
                            package: package,
                            page: page,
                            paperRect: paperRect,
                            scale: scale,
                            selectedItemIndex: $selectedCustomItemIndex
                        )
                    }

                    Path { path in
                        for segment in page.cropMarkSegments {
                            path.move(to: converted(
                                segment.start,
                                page: page,
                                paperRect: paperRect,
                                scale: scale
                            ))
                            path.addLine(to: converted(
                                segment.end,
                                page: page,
                                paperRect: paperRect,
                                scale: scale
                            ))
                        }
                    }
                    .stroke(Color.black.opacity(0.72), lineWidth: 1)
                    .zIndex(Double(page.items.count * 3))

                    Rectangle()
                        .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                        .frame(width: paperRect.width, height: paperRect.height)
                        .position(x: paperRect.midX, y: paperRect.midY)

                    if preview.pages.count > 1 {
                        pageControls(count: preview.pages.count)
                            .position(x: proxy.size.width / 2, y: 20)
                    }
                }
            } else {
                ContentUnavailableView(model.text(.noFrame), systemImage: "rectangle.grid.2x2")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: frames.map(\.id)) { _, _ in selectedPage = 0 }
        .onChange(of: package.mode) { _, mode in
            if mode != .customPackage { selectedCustomItemIndex = nil }
        }
        .onChange(of: previewData?.pages.count) { _, count in
            selectedPage = min(selectedPage, max(0, (count ?? 1) - 1))
        }
    }

    private struct PreviewSource {
        let image: NSImage
        let destinationGamutOverlay: NSImage?
        let size: CGSize
        let caption: String?
    }

    private struct PreviewData {
        let sources: [PreviewSource]
        let pages: [PrintPackagePageLayout]
    }

    private var previewData: PreviewData? {
        let sources = frames.map { frame -> PreviewSource? in
            guard let image = frame.developedImage ?? frame.rawPreviewImage ?? frame.thumbnailImage else {
                return nil
            }
            let size = image.representations.first.map {
                CGSize(width: $0.pixelsWide, height: $0.pixelsHigh)
            } ?? image.size
            guard size.width > 0, size.height > 0 else { return nil }
            return PreviewSource(
                image: image,
                destinationGamutOverlay: frame.displayedSoftProofRevision
                    == model.softProofConfigurationRevision
                    ? frame.destinationGamutOverlayImage
                    : nil,
                size: size,
                caption: PrintPackageCaptionFormatter.caption(
                    for: frame,
                    mode: package.captionMode
                )
            )
        }
        guard sources.allSatisfy({ $0 != nil }) else { return nil }
        let availableSources = sources.compactMap { $0 }
        guard !availableSources.isEmpty,
              let pages = PrintPackageLayout.make(
                sourceSizes: availableSources.map(\.size),
                composition: settingsStore.compositionSettings(dpi: 72),
                package: package
              ) else { return nil }
        return PreviewData(sources: availableSources, pages: pages)
    }

    @ViewBuilder
    private func packageImage(
        _ image: NSImage,
        item: PrintPackageItemLayout,
        destination: CGRect
    ) -> some View {
        let mode: ContentMode = item.sourceUnitCropRect == CGRect(x: 0, y: 0, width: 1, height: 1)
            ? .fit
            : .fill
        if item.quarterTurns == 1 {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: mode)
                .frame(width: destination.height, height: destination.width)
                .rotationEffect(.degrees(-90))
                .frame(width: destination.width, height: destination.height)
                .clipped()
                .position(x: destination.midX, y: destination.midY)
        } else {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: mode)
                .frame(width: destination.width, height: destination.height)
                .clipped()
                .position(x: destination.midX, y: destination.midY)
        }
    }

    private func pageControls(count: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedPage = max(0, selectedPage - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(selectedPage <= 0)
            .help(model.text(.printPreviousPage))
            .accessibilityLabel(model.text(.printPreviousPage))

            Text(verbatim: "\(min(selectedPage + 1, count)) / \(count)")
                .font(.caption.monospacedDigit())
                .frame(minWidth: 48)

            Button {
                selectedPage = min(count - 1, selectedPage + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(selectedPage >= count - 1)
            .help(model.text(.printNextPage))
            .accessibilityLabel(model.text(.printNextPage))
        }
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

    private func converted(
        _ rect: CGRect,
        page: PrintPackagePageLayout,
        paperRect: CGRect,
        scale: CGFloat
    ) -> CGRect {
        CGRect(
            x: paperRect.minX + rect.minX * scale,
            y: paperRect.minY + (page.canvasSizePoints.height - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private func converted(
        _ point: CGPoint,
        page: PrintPackagePageLayout,
        paperRect: CGRect,
        scale: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: paperRect.minX + point.x * scale,
            y: paperRect.minY + (page.canvasSizePoints.height - point.y) * scale
        )
    }
}
