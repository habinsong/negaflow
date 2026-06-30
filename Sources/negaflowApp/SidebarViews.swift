import SwiftUI
import AppKit
import Chromabase

struct DetectingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.large)
            Text("스캐너를 찾는 중…").foregroundStyle(.white.opacity(0.8))
        }
    }
}

struct FrameStripItemView: View {
    @ObservedObject var frame: ScanFrame
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 6) {
                    thumbnail
                        .overlay(alignment: .topLeading) {
                            if frame.pickState != .unflagged {
                                Image(systemName: frame.pickState.systemImage)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(frame.pickState.tint)
                                    .padding(5)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if frame.isDeveloping {
                                ProgressView()
                                    .controlSize(.mini)
                                    .padding(5)
                            }
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(frame.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .allowsTightening(true)
                        Text(frame.filmType.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .allowsTightening(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            HStack(spacing: 4) {
                FrameRatingButtons(frame: frame)
                Spacer(minLength: 0)
                Text(frame.pickState.displayName)
                    .font(.caption2)
                    .foregroundStyle(frame.pickState.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
            }
        }
        .padding(8)
        .frame(width: 206, height: 140)
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.18),
                              lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .liquidSurface(cornerRadius: 9, interactive: true)
        .accessibilityLabel("\(frame.displayName), \(frame.filmType.displayName), \(frame.selectionSummary)")
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.22))
            if let img = frame.thumbnailImage ?? frame.developedImage ?? frame.rawPreviewImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 190, height: 72)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .frame(width: 190, height: 72)
    }
}

private struct FrameRatingButtons: View {
    @ObservedObject var frame: ScanFrame

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    frame.setRating(value)
                } label: {
                    Image(systemName: value <= frame.rating ? "star.fill" : "star")
                        .font(.caption2)
                        .foregroundStyle(value <= frame.rating ? Color.accentColor : Color.secondary.opacity(0.45))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(value) star")
                .accessibilityLabel("\(value) star")
            }
        }
    }
}
