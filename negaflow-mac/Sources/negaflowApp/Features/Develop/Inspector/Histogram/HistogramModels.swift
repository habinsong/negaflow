import SwiftUI
import AppKit
import Chromabase

enum HistogramChannel: CaseIterable {
    case red
    case green
    case blue

    var title: String {
        title(language: .system)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .red: return AppLocalization.text(AppLocalizedPhrase.redChannelShort, language: language)
        case .green: return AppLocalization.text(AppLocalizedPhrase.greenChannelShort, language: language)
        case .blue: return AppLocalization.text(AppLocalizedPhrase.blueChannelShort, language: language)
        }
    }

    var color: Color {
        switch self {
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        }
    }

    var accessibilityLabel: String {
        accessibilityLabel(language: .system)
    }

    func accessibilityLabel(language: AppLanguage) -> String {
        switch self {
        case .red: return AppLocalization.text(AppLocalizedPhrase.redChannel, language: language)
        case .green: return AppLocalization.text(AppLocalizedPhrase.greenChannel, language: language)
        case .blue: return AppLocalization.text(AppLocalizedPhrase.blueChannel, language: language)
        }
    }
}

struct HistogramBins {
    let luma: [Int]
    let r: [Int]
    let g: [Int]
    let b: [Int]
    let totalPixels: Int
    private let shadowClipCounts: (red: Int, green: Int, blue: Int)
    private let highlightClipCounts: (red: Int, green: Int, blue: Int)

    init(
        luma: [Int],
        r: [Int],
        g: [Int],
        b: [Int],
        totalPixels: Int,
        shadowClipCounts: (red: Int, green: Int, blue: Int),
        highlightClipCounts: (red: Int, green: Int, blue: Int)
    ) {
        self.luma = luma
        self.r = r
        self.g = g
        self.b = b
        self.totalPixels = totalPixels
        self.shadowClipCounts = shadowClipCounts
        self.highlightClipCounts = highlightClipCounts
    }

    var maxCount: Int {
        [luma.max() ?? 1, r.max() ?? 1, g.max() ?? 1, b.max() ?? 1].max() ?? 1
    }

    var clippedChannels: [HistogramChannel] {
        HistogramChannel.allCases.filter { isClipped($0) }
    }

    var clippingText: String {
        clippingText(language: .system)
    }

    func clippingText(language: AppLanguage) -> String {
        AppLocalization.format(
            AppLocalizedPhrase.clippingChannelsFormat,
            language: language,
            clippedChannels.map { $0.title(language: language) }.joined(separator: "/")
        )
    }

    private func isClipped(_ channel: HistogramChannel) -> Bool {
        let shadowCount: Int
        let highlightCount: Int
        switch channel {
        case .red:
            shadowCount = shadowClipCounts.red
            highlightCount = highlightClipCounts.red
        case .green:
            shadowCount = shadowClipCounts.green
            highlightCount = highlightClipCounts.green
        case .blue:
            shadowCount = shadowClipCounts.blue
            highlightCount = highlightClipCounts.blue
        }
        let threshold = max(Int(Double(totalPixels) * 0.002), 1)
        return shadowCount > threshold || highlightCount > threshold
    }
}
