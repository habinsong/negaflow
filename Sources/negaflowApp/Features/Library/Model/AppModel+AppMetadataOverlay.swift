import Foundation

struct AppMetadataOverlayDraft: Equatable {
    var title = ""
    var caption = ""
    var keywords = ""
    var copyright = ""

    init() {}

    init(_ overlay: AppMetadataOverlay?) {
        title = overlay?.title ?? ""
        caption = overlay?.caption ?? ""
        keywords = overlay?.keywords.joined(separator: ", ") ?? ""
        copyright = overlay?.copyright ?? ""
    }

    var keywordValues: [String] {
        keywords.split(separator: ",", omittingEmptySubsequences: true).map(String.init)
    }
}

extension AppModel {
    @discardableResult
    func applyAppMetadataOverlay(
        _ draft: AppMetadataOverlayDraft,
        to targetFrames: [ScanFrame]
    ) -> Bool {
        let targets = targetFrames.filter {
            ownsFrame($0) && !$0.isPreviewScan
        }
        guard allowsLibraryMutation, !targets.isEmpty else { return false }
        let now = Date()
        for frame in targets {
            let overlay = AppMetadataOverlay(
                title: draft.title,
                caption: draft.caption,
                keywords: draft.keywordValues,
                copyright: draft.copyright,
                sourceMetadataSHA256: frame.sourceMetadata?.appMetadataIdentitySHA256(),
                revision: (frame.appMetadataOverlay?.revision ?? 0) + 1,
                updatedAt: now
            )
            frame.setAppMetadataOverlay(overlay.isEmpty ? nil : overlay)
        }
        invalidateLibraryQueryContext()
        return true
    }

    @discardableResult
    func resolveAppMetadataOverlayConflict(for frame: ScanFrame) -> Bool {
        guard allowsLibraryMutation,
              ownsFrame(frame),
              let current = frame.appMetadataOverlay,
              current.conflicts(with: frame.sourceMetadata) else { return false }
        let rebased = AppMetadataOverlay(
            title: current.title,
            caption: current.caption,
            keywords: current.keywords,
            copyright: current.copyright,
            sourceMetadataSHA256: frame.sourceMetadata?.appMetadataIdentitySHA256(),
            revision: current.revision + 1
        )
        frame.setAppMetadataOverlay(rebased)
        return true
    }
}
