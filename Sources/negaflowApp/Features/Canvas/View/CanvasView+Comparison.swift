import SwiftUI
import AppKit
import Chromabase

extension CanvasView {
    var activeCompareMode: CanvasCompareMode {
        guard canCompare else { return frame.showDeveloped ? .developed : .raw }
        return compareMode
    }

    var selectedBeforeID: String {
        if CompareBeforeContent(rawValue: beforeContentRaw) != nil {
            return beforeContentRaw
        }
        if beforeContentRaw.hasPrefix(Self.beforeFramePrefix),
           comparisonFrame(for: beforeContentRaw) != nil {
            return beforeContentRaw
        }
        return CompareBeforeContent.unedited.rawValue
    }

    var beforeLabel: String {
        (primaryBeforeOptions + frameBeforeOptions)
            .first { $0.id == selectedBeforeID }?.label
            ?? CompareBeforeContent.unedited.label(language: model.appLanguage)
    }

    var primaryBeforeOptions: [CanvasCompareBeforeOption] {
        [
            CanvasCompareBeforeOption(id: CompareBeforeContent.main.rawValue, label: CompareBeforeContent.main.label(language: model.appLanguage), systemImage: "circle.hexagongrid.fill"),
            CanvasCompareBeforeOption(id: CompareBeforeContent.unedited.rawValue, label: CompareBeforeContent.unedited.label(language: model.appLanguage), systemImage: "slider.horizontal.3"),
            CanvasCompareBeforeOption(id: CompareBeforeContent.raw.rawValue, label: CompareBeforeContent.raw.label(language: model.appLanguage), systemImage: "camera.metering.unknown"),
        ]
    }

    var frameBeforeOptions: [CanvasCompareBeforeOption] {
        model.frames
            .filter { $0.id != frame.id }
            .map {
                CanvasCompareBeforeOption(
                    id: Self.beforeFramePrefix + $0.id.uuidString,
                    label: $0.compactDisplayName(language: model.appLanguage),
                    systemImage: $0.isVirtualCopy ? "square.on.square" : "photo"
                )
            }
    }

    /// Before(좌/상)에 표시할 이미지. 무보정본 우선, 없으면 raw로 폴백(또는 사용자 선택이 raw).
    var beforeImage: NSImage? {
        switch CompareBeforeContent(rawValue: selectedBeforeID) {
        case .some(.main):
            if frame.params.developTarget == .main {
                return frame.developedImage ?? frame.neutralPreviewImage ?? frame.rawPreviewImage
            }
            return frame.mainPreviewImage ?? frame.neutralPreviewImage ?? frame.rawPreviewImage
        case .some(.unedited):
            return frame.neutralPreviewImage ?? frame.rawPreviewImage
        case .some(.raw):
            return frame.rawPreviewImage ?? frame.neutralPreviewImage
        case .none:
            return comparisonFrame(for: selectedBeforeID).flatMap {
                $0.developedImage ?? $0.neutralPreviewImage ?? $0.rawPreviewImage ?? $0.thumbnailImage
            }
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

    static let beforeFramePrefix = "frame:"

    func comparisonFrame(for id: String) -> ScanFrame? {
        guard id.hasPrefix(Self.beforeFramePrefix) else { return nil }
        let rawID = String(id.dropFirst(Self.beforeFramePrefix.count))
        guard let uuid = UUID(uuidString: rawID) else { return nil }
        return model.frames.first { $0.id == uuid }
    }

    var debugPreviewImage: NSImage? {
        guard frame.debugOverlayEnabled else { return nil }
        return frame.debugPreviewImages[frame.debugOverlayStage]
    }

    @ViewBuilder
    var canvasBackgroundMenu: some View {
        CanvasBackgroundMenu()
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
                    fittedImage(image, in: imageFrame, straightenDelta: straightenDelta(from: frame.rawPreviewTransform))
                        .onTapGesture(count: 2) { resetViewport() }
                }
            case .developed:
                if let image = frame.developedImage ?? frame.rawPreviewImage ?? frame.thumbnailImage {
                    fittedImage(image, in: imageFrame, straightenDelta: straightenDelta(from: frame.developedPreviewTransform))
                        .onTapGesture(count: 2) { resetViewport() }
                    if let overlay = visibleDestinationGamutOverlay {
                        fittedImage(
                            overlay,
                            in: imageFrame,
                            straightenDelta: straightenDelta(from: frame.developedPreviewTransform)
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                    if let overlay = visibleClippingOverlay {
                        fittedImage(
                            overlay,
                            in: imageFrame,
                            straightenDelta: straightenDelta(from: frame.developedPreviewTransform)
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
            case .splitVertical:
                if let before = beforeImage, let after = frame.developedImage {
                    splitVerticalImage(
                        before: before,
                        after: after,
                        destinationGamutOverlay: visibleDestinationGamutOverlay,
                        clippingOverlay: visibleClippingOverlay,
                        in: imageFrame,
                        fraction: splitVerticalFraction
                    )
                    compareDivider(in: imageFrame, orientation: .vertical)
                        .zIndex(45)
                    compareLabels(in: imageFrame, orientation: .vertical)
                        .zIndex(40)
                }
            case .splitHorizontal:
                if let before = beforeImage, let after = frame.developedImage {
                    splitHorizontalImage(
                        before: before,
                        after: after,
                        destinationGamutOverlay: visibleDestinationGamutOverlay,
                        clippingOverlay: visibleClippingOverlay,
                        in: imageFrame,
                        fraction: splitHorizontalFraction
                    )
                    compareDivider(in: imageFrame, orientation: .horizontal)
                        .zIndex(45)
                    compareLabels(in: imageFrame, orientation: .horizontal)
                        .zIndex(40)
                }
            }
        }
    }

    var visibleClippingOverlay: NSImage? {
        model.clippingOverlayEnabled ? frame.clippingOverlayImage : nil
    }

    var visibleDestinationGamutOverlay: NSImage? {
        model.softProofEnabled
            && model.destinationGamutWarningEnabled
            && model.destinationGamutWarningAvailable
            && frame.displayedSoftProofRevision == model.softProofConfigurationRevision
            ? frame.destinationGamutOverlayImage
            : nil
    }

    @ViewBuilder
    var debugStageBadge: some View {
        if isDebugPreviewActive {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg.rectangle")
                Text(model.text(AppLocalizedPhrase.debugBadgeFormat, frame.debugOverlayStage.displayName))
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .liquidSurface(cornerRadius: 7)
        }
    }

    // 프록시 해상도(인터랙티브/정착)가 달라도 화면 픽셀로 축소되는 품질이 같도록 고품질 보간을
    // 명시한다 — 스왑 시 텍스처/선명도 차이가 보이지 않는다.

}
