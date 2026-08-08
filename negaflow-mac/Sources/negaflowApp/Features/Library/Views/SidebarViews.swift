import SwiftUI
import AppKit
import Chromabase

/// 카드가 어떤 그림을 보여줄지 정하는 규칙. 결과(`FrameStripPresentationMode`)를 부모 body 에서
/// 계산해 값으로 넘기면, 현상이 끝나 프레임이 갱신돼도 부모가 다시 그려지기 전까지 카드가
/// 예전 판단(원본)에 머문다 — 폴더 일괄 적용 뒤 썸네일이 바뀌지 않던 원인이다. 규칙만 넘기고
/// 판단은 프레임을 관찰하는 카드가 직접 한다.
enum FrameStripPresentationPolicy: Equatable {
    /// 라이브러리 필름스트립 — 언제나 원본을 보여준다.
    case raw
    /// 현상 결과가 준비돼 있으면 그것을, 아니면 원본을 보여준다.
    case developedWhenAvailable
}

enum FrameStripPresentationMode: Equatable {
    case developed
    case raw

    @MainActor
    static func resolve(
        for frame: ScanFrame,
        policy: FrameStripPresentationPolicy
    ) -> FrameStripPresentationMode {
        guard policy == .developedWhenAvailable else { return .raw }
        guard frame.thumbnailImage != nil || frame.developedImage != nil else { return .raw }
        // 네거티브는 현상 전에도 포지티브 썸네일이 먼저 올라온다. 그 그림이 이미 현상 결과다.
        return frame.hasDevelopedOnce
            || (frame.filmType.requiresInversion && frame.thumbnailImage != nil)
            ? .developed
            : .raw
    }

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
        switch self {
        case .developed:
            if frame.filmType.requiresInversion {
                return frame.thumbnailImage ?? frame.developedImage
            }
            return frame.thumbnailImage ?? frame.developedImage ?? frame.rawPreviewImage
        case .raw:
            return frame.rawPreviewImage ?? frame.thumbnailImage ?? frame.developedImage
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
    var presentationPolicy: FrameStripPresentationPolicy = .developedWhenAvailable
    var thumbnailAspectRatio: CGFloat? = nil
    var thumbnailTitleSpacing: CGFloat? = nil
    var ratingControlHeight: CGFloat? = nil
    let onSelect: () -> Void

    /// 프레임을 관찰하는 이 뷰 안에서 판단한다 — 현상이 끝나면 곧바로 현상 결과로 바뀐다.
    private var presentationMode: FrameStripPresentationMode {
        FrameStripPresentationMode.resolve(for: frame, policy: presentationPolicy)
    }

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
        // 카드는 스크롤에서 수십 장이 동시에 살아 있다. interactive 글래스는 카드마다 포인터를
        // 따라가는 실시간 변형을 돌려 스크롤 프레임을 갉아먹으므로 정적 표면을 쓴다.
        .liquidSurface(cornerRadius: 9)
        // 카드 하나가 접근성 요소 하나다. 안쪽 요소를 따로 노출하면 카드 수만큼 노드가
        // 곱해지고, 그 트리를 레이아웃마다 훑는 비용이 모듈 전환을 초 단위로 늘린다.
        .accessibilityElement(children: .combine)
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

    /// 별 다섯 개를 **하나의 조작 영역**으로 둔다.
    ///
    /// 별마다 `Button` 을 두면 카드 한 장이 응답자(responder) 다섯 개와 접근성 노드 열다섯 개를
    /// 더 만든다. 격자에는 그런 카드가 수백 장 살아 있고, SwiftUI 는 레이아웃마다 응답자 트리를
    /// 전부 훑는다(`AccessibilityNode.updateFocus` → `MultiViewResponder.visit`). 실측에서
    /// 라이브러리로 모듈을 전환하는 데 4.5초가 걸렸고, 이 다섯 버튼과 카드 접근성 수정자를
    /// 걷어내자 1.9초로 떨어졌다. 동작은 그대로 두고 구조만 하나로 합친다.
    var body: some View {
        let starWidth: CGFloat = isCompact ? 12 : 16
        let spacing: CGFloat = isCompact ? 0 : 1
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= frame.rating ? "star.fill" : "star")
                    .font(.system(size: isCompact ? 7 : 9))
                    .foregroundStyle(value <= frame.rating ? Color.blue : Color.secondary.opacity(0.45))
                    .frame(width: starWidth, height: controlHeight)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { event in
                let step = starWidth + spacing
                let index = Int(event.location.x / max(1, step)) + 1
                frame.toggleRating(min(5, max(1, index)))
            }
        )
        .help(model.text(AppLocalizedPhrase.starHelpFormat, frame.rating))
        // 별점은 값을 가진 컨트롤 하나다. 별마다 선택 상태를 두는 것보다 이쪽이 보조기술에서도
        // 다루기 쉽고, 노드도 하나로 끝난다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.text(AppLocalizedPhrase.starHelpFormat, frame.rating))
        .accessibilityValue(model.text(AppLocalizedPhrase.starHelpFormat, frame.rating))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: frame.setRating(min(5, frame.rating + 1))
            case .decrement: frame.setRating(max(0, frame.rating - 1))
            @unknown default: break
            }
        }
    }
}






