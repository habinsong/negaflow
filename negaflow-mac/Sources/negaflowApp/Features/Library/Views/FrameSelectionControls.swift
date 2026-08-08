import SwiftUI
import Chromabase

extension FramePickState {
    var displayName: String {
        displayName(language: .system)
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .unflagged: return AppLocalization.text(AppLocalizedPhrase.unflagged, language: language)
        case .picked: return AppLocalization.text(AppLocalizedPhrase.picked, language: language)
        case .rejected: return AppLocalization.text(AppLocalizedPhrase.rejected, language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .unflagged: return "flag"
        case .picked: return "flag.fill"
        case .rejected: return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .unflagged: return .secondary
        case .picked: return .green
        case .rejected: return .red
        }
    }
}

struct FrameSelectionControls: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var frame: ScanFrame

    var body: some View {
        Group {
            LabeledContent(model.text(AppLocalizedPhrase.rating)) {
                HStack(spacing: 6) {
                    RatingButtons(frame: frame)
                    Spacer(minLength: 6)
                    Button {
                        frame.setRating(0)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.caption.weight(.semibold))
                            .frame(width: 24, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(frame.rating == 0)
                    .opacity(frame.rating == 0 ? 0.35 : 1)
                    .help(model.text(AppLocalizedPhrase.resetRating))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(model.text(AppLocalizedPhrase.picked))
                SegmentedPicker(
                    options: FramePickState.allCases,
                    label: { $0.displayName(language: model.appLanguage) },
                    selection: Binding(
                        get: { frame.pickState },
                        set: { frame.pickState = $0 }
                    )
                )
            }
        }
    }
}

private struct RatingButtons: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var frame: ScanFrame

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    frame.toggleRating(value)
                } label: {
                    Image(systemName: value <= frame.rating ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(value <= frame.rating ? Color.blue : Color.secondary.opacity(0.55))
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.text(AppLocalizedPhrase.starHelpFormat, value))
            }
        }
    }
}

struct FrameRatingStarsView: View {
    @EnvironmentObject private var model: AppModel
    let rating: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(value <= rating ? Color.blue : Color.secondary.opacity(0.45))
            }
        }
        .accessibilityLabel(model.text(AppLocalizedPhrase.ratingAccessibilityFormat, rating))
    }
}
