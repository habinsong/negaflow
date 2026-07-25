import Chromabase
import Foundation

@MainActor
enum PrintPackageCaptionFormatter {
    static func caption(
        for frame: ScanFrame,
        mode: PrintPackageCaptionMode
    ) -> String? {
        switch mode {
        case .none:
            nil
        case .fileName:
            frame.rawScanURL.lastPathComponent
        case .frameNumber:
            "\(frame.scanIndex)"
        case .rating:
            frame.rating > 0 ? String(repeating: "★", count: frame.rating) : "—"
        }
    }
}
