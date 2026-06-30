import SwiftUI
import Chromabase

extension FramePickState {
    var displayName: String {
        switch self {
        case .unflagged: return "Unflagged"
        case .picked: return "Pick"
        case .rejected: return "Reject"
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
    @ObservedObject var frame: ScanFrame

    var body: some View {
        Group {
            LabeledContent("Rating") {
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
                    .help("Rating 초기화")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Pick")
                SegmentedPicker(
                    options: FramePickState.allCases,
                    label: { $0.displayName },
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
    @ObservedObject var frame: ScanFrame

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    frame.setRating(value)
                } label: {
                    Image(systemName: value <= frame.rating ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(value <= frame.rating ? Color.accentColor : Color.secondary.opacity(0.55))
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(value) star")
            }
        }
    }
}

struct FrameRatingStarsView: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(value <= rating ? Color.accentColor : Color.secondary.opacity(0.45))
            }
        }
        .accessibilityLabel("Rating \(rating)")
    }
}
