import SwiftUI
import AppKit
import Chromabase

enum FrameStripPresentationMode {
    case developed
    case raw

    var displaysSubtitle: Bool {
        switch self {
        case .developed:
            return true
        case .raw:
            return false
        }
    }

    @MainActor
    func subtitle(for frame: ScanFrame, language: AppLanguage) -> String? {
        switch self {
        case .developed:
            return frame.filmType.displayName(language: language)
        case .raw:
            return nil
        }
    }

    @MainActor
    func previewImage(for frame: ScanFrame) -> NSImage? {
        // 네거티브는 현상 썸네일/현상본만 표시한다. 최초 현상이 끝나기 전 rawPreviewImage 로
        // 폴백하면 필름스트립에 네거티브 원본이 잠깐 노출되므로 빈 자리로 유지한다.
        if frame.filmType.requiresInversion {
            return frame.thumbnailImage ?? frame.developedImage
        }
        switch self {
        case .developed:
            return frame.thumbnailImage ?? frame.developedImage ?? frame.rawPreviewImage
        case .raw:
            return frame.thumbnailImage ?? frame.rawPreviewImage ?? frame.developedImage
        }
    }

    @MainActor
    func accessibilitySubtitle(for frame: ScanFrame, language: AppLanguage) -> String {
        subtitle(for: frame, language: language) ?? frame.sourceSummary(language: language)
    }
}

struct FrameStripItemView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var frame: ScanFrame
    let isSelected: Bool
    var itemSize: CGSize = CGSize(width: 206, height: 140)
    var presentationMode: FrameStripPresentationMode = .developed
    var thumbnailAspectRatio: CGFloat? = nil
    var thumbnailTitleSpacing: CGFloat? = nil
    var ratingControlHeight: CGFloat? = nil
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 0) {
                    thumbnail
                        .overlay(alignment: .topLeading) {
                            if frame.pickState != .unflagged {
                                Image(systemName: frame.pickState.systemImage)
                                    .font((isCompact ? AppTypography.compactIcon : .caption2).weight(.semibold))
                                    .foregroundStyle(frame.pickState.tint)
                                    .padding(isCompact ? 4 : 5)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            VStack(alignment: .trailing, spacing: 4) {
                                if frame.isDeveloping {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                                if let stack = model.stack(containing: frame.id) {
                                    LibraryStackBadge(stack: stack)
                                }
                            }
                            .padding(isCompact ? 4 : 5)
                        }
                        .overlay(alignment: .bottomLeading) {
                            if !model.isSourceAvailable(frame) {
                                Label(model.text(AppLocalizedPhrase.sourceOffline), systemImage: "questionmark.circle.fill")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .foregroundStyle(.white)
                                    .background(.black.opacity(0.72), in: Capsule())
                                    .padding(isCompact ? 4 : 5)
                            }
                        }
                    if let thumbnailTitleSpacing {
                        Color.clear
                            .frame(height: thumbnailTitleSpacing)
                    } else {
                        Spacer(minLength: cardSpacing)
                    }
                    VStack(alignment: .leading, spacing: textSpacing) {
                        Text(frame.displayName(language: model.appLanguage))
                            .font((isCompact ? Font.caption2 : .caption).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(AppTypography.minimumScaleFactor)
                            .allowsTightening(true)
                        if let subtitle = presentationMode.subtitle(for: frame, language: model.appLanguage), showsSubtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(AppTypography.minimumScaleFactor)
                                .allowsTightening(true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .buttonStyle(.plain)
            .frame(maxHeight: .infinity)
            HStack(spacing: isCompact ? 2 : 4) {
                FrameRatingButtons(
                    frame: frame,
                    isCompact: isCompact,
                    controlHeight: resolvedRatingControlHeight
                )
                Spacer(minLength: 0)
                if showsPickLabel, frame.pickState != .unflagged {
                    Text(frame.pickState.displayName(language: model.appLanguage))
                        .font(.caption2)
                        .foregroundStyle(frame.pickState.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(AppTypography.minimumScaleFactor)
                        .allowsTightening(true)
                }
            }
        }
        .padding(cardPadding)
        .frame(width: itemSize.width, height: itemSize.height)
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.18),
                              lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .liquidSurface(cornerRadius: 9, interactive: true)
        .accessibilityLabel(model.text(
            AppLocalizedPhrase.frameAccessibilityFormat,
            frame.displayName(language: model.appLanguage),
            presentationMode.accessibilitySubtitle(for: frame, language: model.appLanguage),
            frame.selectionSummary(language: model.appLanguage)
        ))
        .accessibilityIdentifier("negaflow.frame-card")
        .accessibilityValue(model.isSourceAvailable(frame) ? "online" : "offline")
        .accessibilitySelectionTrait(isSelected)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let reservedTextHeight: CGFloat = showsSubtitle ? 31 : 15
        let reservedHeight = reservedTextHeight
            + resolvedRatingControlHeight
            + (thumbnailTitleSpacing ?? cardSpacing)
            + cardPadding * 2
        let availableHeight = max(24, itemSize.height - reservedHeight)
        let targetHeight = thumbnailAspectRatio.map {
            max(64, itemSize.width - cardPadding * 2) / $0
        } ?? (itemSize.height * (isCompact ? 0.40 : thumbnailHeightFraction))
        let thumbnailHeight = max(24, min(targetHeight, availableHeight))
        let thumbnailSize = CGSize(
            width: max(64, itemSize.width - cardPadding * 2),
            height: thumbnailHeight
        )
        ZStack {
            RoundedRectangle(cornerRadius: thumbnailCornerRadius)
                .fill(Color.gray.opacity(0.22))
            if let img = presentationMode.previewImage(for: frame) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: thumbnailCornerRadius))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
    }

    private var resolvedRatingControlHeight: CGFloat {
        ratingControlHeight ?? (isCompact ? 14 : 20)
    }

    private var isCompact: Bool {
        itemSize.height < 112
    }

    private var cardPadding: CGFloat {
        isCompact ? 5 : 8
    }

    private var cardSpacing: CGFloat {
        isCompact ? 4 : 6
    }

    private var textSpacing: CGFloat {
        isCompact ? 1 : 2
    }

    private var thumbnailCornerRadius: CGFloat {
        isCompact ? 5 : 6
    }

    private var thumbnailHeightFraction: CGFloat {
        switch presentationMode {
        case .developed: 0.52
        case .raw: 0.58
        }
    }

    private var showsSubtitle: Bool {
        itemSize.height >= 104 && presentationMode.displaysSubtitle
    }

    private var showsPickLabel: Bool {
        itemSize.width >= 145 && itemSize.height >= 96
    }
}

struct HoverStepIconButton: View {
    let systemName: String
    var text: String? = nil
    let help: String
    let isDisabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if let text {
                    Text(text)
                } else {
                    Image(systemName: systemName)
                }
            }
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 22)
                .background(
                    Color.primary.opacity(isHovered && !isDisabled ? 0.12 : 0),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct FrameRatingButtons: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var frame: ScanFrame
    let isCompact: Bool
    let controlHeight: CGFloat

    var body: some View {
        HStack(spacing: isCompact ? 0 : 1) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    frame.toggleRating(value)
                } label: {
                    Image(systemName: value <= frame.rating ? "star.fill" : "star")
                        .font(.system(size: isCompact ? 7 : 9))
                        .foregroundStyle(value <= frame.rating ? Color.blue : Color.secondary.opacity(0.45))
                        .frame(width: isCompact ? 12 : 16, height: controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.text(AppLocalizedPhrase.starHelpFormat, value))
                .accessibilityLabel(model.text(AppLocalizedPhrase.starHelpFormat, value))
                .accessibilitySelectionState(
                    frame.rating == value,
                    selectedValue: model.accessibilityText(.selected),
                    unselectedValue: model.accessibilityText(.notSelected),
                    unselectedHint: model.accessibilityText(.select)
                )
            }
        }
    }
}
