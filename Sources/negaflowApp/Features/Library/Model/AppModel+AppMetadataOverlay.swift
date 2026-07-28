import Foundation

struct AppMetadataOverlayDraft: Equatable {
    var title = ""
    var caption = ""
    var keywords = ""
    var copyright = ""
    var cameraMake = ""
    var cameraModel = ""
    var lensModel = ""
    var filmStock = ""
    var isoSpeed = ""
    var shutterSpeed = ""
    var aperture = ""
    var focalLength = ""

    init() {}

    init(_ overlay: AppMetadataOverlay?) {
        title = overlay?.title ?? ""
        caption = overlay?.caption ?? ""
        keywords = overlay?.keywords.joined(separator: ", ") ?? ""
        copyright = overlay?.copyright ?? ""
        let shot = overlay?.filmShot
        cameraMake = shot?.cameraMake ?? ""
        cameraModel = shot?.cameraModel ?? ""
        lensModel = shot?.lensModel ?? ""
        filmStock = shot?.filmStock ?? ""
        isoSpeed = shot?.isoSpeed.map(String.init) ?? ""
        shutterSpeed = shot?.exposureTimeSeconds.map(FilmShotMetadata.exposureTimeText) ?? ""
        aperture = shot?.fNumber.map { Self.decimalText($0) } ?? ""
        focalLength = shot?.focalLengthMM.map { Self.decimalText($0) } ?? ""
    }

    var keywordValues: [String] {
        keywords.split(separator: ",", omittingEmptySubsequences: true).map(String.init)
    }

    /// 읽을 수 없는 숫자는 조용히 버린다 — 적히지 않은 것과 같게 취급한다.
    var filmShotValues: FilmShotMetadata {
        FilmShotMetadata(
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            lensModel: lensModel,
            filmStock: filmStock,
            isoSpeed: Int(isoSpeed.trimmingCharacters(in: .whitespaces)),
            exposureTimeSeconds: FilmShotMetadata.exposureTime(fromText: shutterSpeed),
            fNumber: Self.decimalValue(aperture, droppingPrefix: "f/"),
            focalLengthMM: Self.decimalValue(focalLength, droppingSuffix: "mm")
        )
    }

    private static func decimalText(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private static func decimalValue(
        _ text: String,
        droppingPrefix prefix: String = "",
        droppingSuffix suffix: String = ""
    ) -> Double? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !prefix.isEmpty, value.hasPrefix(prefix) { value.removeFirst(prefix.count) }
        if !suffix.isEmpty, value.hasSuffix(suffix) { value.removeLast(suffix.count) }
        return Double(value.trimmingCharacters(in: .whitespaces))
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
                filmShot: draft.filmShotValues,
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
            filmShot: current.filmShot,
            sourceMetadataSHA256: frame.sourceMetadata?.appMetadataIdentitySHA256(),
            revision: current.revision + 1
        )
        frame.setAppMetadataOverlay(rebased)
        return true
    }
}
