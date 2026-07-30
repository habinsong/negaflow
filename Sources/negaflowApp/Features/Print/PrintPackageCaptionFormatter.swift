import Chromabase
import Foundation

@MainActor
enum PrintPackageCaptionFormatter {
    static func caption(
        for frame: ScanFrame,
        mode: PrintPackageCaptionMode,
        sequenceNumber: Int
    ) -> String? {
        switch mode {
        case .none:
            nil
        case .fileName:
            frame.rawScanURL.lastPathComponent
        case .frameNumber:
            "\(frame.scanIndex)"
        case .sequenceNumber:
            "\(sequenceNumber)"
        case .rating:
            frame.rating > 0 ? String(repeating: "★", count: frame.rating) : "—"
        case .customText:
            nil
        }
    }
}
