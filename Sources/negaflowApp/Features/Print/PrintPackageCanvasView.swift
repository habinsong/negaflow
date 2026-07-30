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
                ZStack(alignment: .topLeading) {
                    packagePage(
                        preview: preview,
                        page: preview.pages[pageIndex]
                    )
                    .accessibilityIdentifier("negaflow.print.page.\(pageIndex)")

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
        let size: CGSize
        let caption: String?
    }

    private struct PreviewData {
        let sources: [PreviewSource]
        let pages: [PrintPackagePageLayout]
    }

    /// 크기를 아직 알 수 없는 프레임의 임시 셀 비율. 셀을 빼 버리면 선택 순서가 어긋나므로
    /// 자리를 유지하고, 실제 크기를 알게 되면 그 값으로 다시 배치된다.
    private static let fallbackSourceSize = CGSize(width: 3, height: 2)

    private var previewData: PreviewData? {
        // 선택한 프레임은 이미지가 아직 메모리에 없어도 전부 시트에 자리를 잡는다. 한 장이라도
        // 로드되지 않았다고 시트 전체를 비우면 다중 선택이 첫 장만 남은 것처럼 보인다.
        let sources = frames.enumerated().map { sourceIndex, frame in
            PreviewSource(
                size: model.printPackageLayoutSize(for: frame) ?? Self.fallbackSourceSize,
                caption: PrintPackageCaptionFormatter.caption(
                    for: frame,
                    mode: package.captionMode,
                    sequenceNumber: sourceIndex + 1
                )
            )
        }
        guard !sources.isEmpty,
              let pages = PrintPackageLayout.make(
                sourceSizes: sources.map(\.size),
                composition: model.printCompositionSettings(dpi: 72),
                package: package,
                forcedQuarterTurns: model.printPackageForcedQuarterTurns(
                    for: frames,
                    package: package
                )
              ) else { return nil }
        return PreviewData(sources: sources, pages: pages)
    }

    /// 용지 색은 모든 인화 레이아웃에 적용된다. 흰 종이일 때만 프루프가 계산한 종이 흰색을 쓴다.
    private var usesTintedPaper: Bool {
        package.contactSheetBackground != .white
    }

    private var pageBackgroundColor: Color {
        switch package.contactSheetBackground {
        case .black: .black
        case .gray: Color(white: 0.5)
        case .white: paperColor
        }
    }

    private var pageForegroundColor: Color {
        usesTintedPaper ? .white : .black
    }

    private var captionFrameAlignment: Alignment {
        frameAlignment(package.captionAlignment)
    }

    private func packagePage(
        preview: PreviewData,
        page: PrintPackagePageLayout
    ) -> some View {
        GeometryReader { proxy in
            let paperRect = aspectFit(
                page.canvasSizePoints,
                in: CGRect(origin: .zero, size: proxy.size).insetBy(dx: 30, dy: 42)
            )
            let scale = paperRect.width / page.canvasSizePoints.width
            let foregroundColor = pageForegroundColor

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(pageBackgroundColor)
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
                        PrintPackageFrameItemView(
                            frame: frames[item.sourceIndex],
                            item: item,
                            destination: destination,
                            softProofRevision: model.softProofConfigurationRevision,
                            showsDestinationGamutWarning: model.displaySoftProofSettings(
                                for: frames[item.sourceIndex]
                            ).isEnabled
                                && model.destinationGamutWarningEnabled
                                && model.destinationGamutWarningAvailable
                        )
                        .zIndex(Double(itemOffset * 3))

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
                                .font(.custom(
                                    package.captionFontName,
                                    size: max(7, min(11, convertedCaption.height * 0.55))
                                ))
                                .foregroundStyle(foregroundColor.opacity(0.92))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(
                                    width: convertedCaption.width,
                                    height: convertedCaption.height,
                                    alignment: captionFrameAlignment
                                )
                                .position(x: convertedCaption.midX, y: convertedCaption.midY)
                                .zIndex(Double(itemOffset * 3 + 2))
                        }
                    }
                }

                ForEach(Array(page.textItems.enumerated()), id: \.offset) { textOffset, item in
                    let rect = converted(
                        item.rectPoints,
                        page: page,
                        paperRect: paperRect,
                        scale: scale
                    )
                    Text(item.text)
                        .font(.custom(
                            package.captionFontName,
                            size: max(7, min(18, rect.height * 0.55))
                        ))
                        .foregroundStyle(foregroundColor.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(
                            width: rect.width,
                            height: rect.height,
                            alignment: frameAlignment(item.alignment)
                        )
                        .position(x: rect.midX, y: rect.midY)
                        .zIndex(Double(page.items.count * 3 + textOffset))
                }

                if settingsStore.outputProcess == .cPrint {
                    PrintPaperSurfaceOverlay(surface: settingsStore.cPrintPaperSurface)
                        .frame(width: paperRect.width, height: paperRect.height)
                        .position(x: paperRect.midX, y: paperRect.midY)
                        .zIndex(Double(page.items.count * 3 + page.textItems.count))
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
                    .zIndex(Double(page.items.count * 3 + page.textItems.count + 1))
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
                .stroke(
                    foregroundColor.opacity(usesTintedPaper ? 0.9 : 0.72),
                    lineWidth: 1
                )
                .zIndex(Double(page.items.count * 3 + page.textItems.count + 2))

                Rectangle()
                    .stroke(foregroundColor.opacity(0.18), lineWidth: 1)
                    .frame(width: paperRect.width, height: paperRect.height)
                    .position(x: paperRect.midX, y: paperRect.midY)
                    .zIndex(Double(page.items.count * 3 + page.textItems.count + 3))
            }
        }
    }

    private func frameAlignment(_ alignment: PrintPackageCaptionAlignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
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

private struct PrintPackageFrameItemView: View {
    @ObservedObject var frame: ScanFrame
    let item: PrintPackageItemLayout
    let destination: CGRect
    let softProofRevision: UInt64
    let showsDestinationGamutWarning: Bool

    var body: some View {
        Group {
            // 셀이 작으므로 썸네일을 먼저 쓴다. 여기서 풀해상도 현상 결과를 요구하면 시트에 올린
            // 장수만큼 무거운 렌더가 줄줄이 돌아 화면이 끊긴다.
            if let image = frame.thumbnailImage ?? frame.developedImage ?? frame.rawPreviewImage {
                packageImage(image)
            } else {
                // 아직 미리보기가 준비되지 않은 셀. 빈 종이로 두면 선택이 누락된 것처럼 보인다.
                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: destination.width, height: destination.height)
                    .position(x: destination.midX, y: destination.midY)
                    .accessibilityHidden(true)
            }
            if showsDestinationGamutWarning,
               frame.displayedSoftProofRevision == softProofRevision,
               let overlay = frame.destinationGamutOverlayImage {
                packageImage(overlay)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func packageImage(_ image: NSImage) -> some View {
        let mode: ContentMode = item.sourceUnitCropRect
            == CGRect(x: 0, y: 0, width: 1, height: 1) ? .fit : .fill
        let turns = max(0, min(3, item.quarterTurns))
        // 홀수 번 돌면 그리는 상자의 가로세로가 바뀐다.
        let swapsAxes = turns % 2 == 1
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: mode)
            .frame(
                width: swapsAxes ? destination.height : destination.width,
                height: swapsAxes ? destination.width : destination.height
            )
            .rotationEffect(.degrees(-90 * Double(turns)))
            .frame(width: destination.width, height: destination.height)
            .clipped()
            .position(x: destination.midX, y: destination.midY)
    }
}
