import Foundation
import Chromabase

@MainActor
extension ScanFrame {
    private static let assignedPhotoNumberPrefix = "negaflow:photo-number:"

    /// 표시용 이름.
    var displayName: String {
        displayName(language: .system)
    }

    func displayName(language: AppLanguage) -> String {
        let baseName = preferredDisplayName(language: language)
        guard let virtualCopyNumber else { return baseName }
        if preferredBaseDisplayName != nil {
            return AppLocalization.format(AppLocalizedPhrase.namedFrameCopyDisplayFormat, language: language, baseName, virtualCopyNumber)
        }
        return AppLocalization.format(
            AppLocalizedPhrase.frameCopyDisplayFormat,
            language: language,
            presentationIndex,
            virtualCopyNumber
        )
    }

    var compactDisplayName: String {
        compactDisplayName(language: .system)
    }

    func compactDisplayName(language: AppLanguage) -> String {
        guard let virtualCopyNumber else { return displayName(language: language) }
        if preferredBaseDisplayName != nil {
            return AppLocalization.format(AppLocalizedPhrase.namedFrameCopyDisplayFormat, language: language, preferredDisplayName(language: language), virtualCopyNumber)
        }
        return AppLocalization.format(
            AppLocalizedPhrase.frameCompactCopyDisplayFormat,
            language: language,
            presentationIndex,
            virtualCopyNumber
        )
    }

    var isVirtualCopy: Bool { virtualCopyNumber != nil }

    var isSourceAvailable: Bool {
        FileManager.default.fileExists(atPath: rawScanURL.path)
    }

    var rootFrameID: UUID { sourceFrameID ?? id }

    var rootFrameDisplayName: String { rootFrameDisplayName(language: .system) }

    func rootFrameDisplayName(language: AppLanguage) -> String {
        if assignedPhotoNumber != nil {
            return preferredDisplayName(language: language)
        }
        return sourceFrameDisplayName ?? preferredDisplayName(language: language)
    }

    var assignedPhotoNumber: Int? {
        guard let customDisplayName,
              customDisplayName.hasPrefix(Self.assignedPhotoNumberPrefix) else {
            return nil
        }
        let value = customDisplayName.dropFirst(Self.assignedPhotoNumberPrefix.count)
        guard let number = Int(value), number > 0 else { return nil }
        return number
    }

    var literalCustomDisplayName: String? {
        guard assignedPhotoNumber == nil else { return nil }
        return customDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    func assignPhotoNumber(_ number: Int) {
        guard number > 0 else { return }
        customDisplayName = Self.assignedPhotoNumberPrefix + String(number)
    }

    private var preferredBaseDisplayName: String? {
        literalCustomDisplayName
            ?? sourceFrameDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? (sourceKind == .importedFile ? sourceFileBaseName : nil)
    }

    private func preferredDisplayName(language: AppLanguage) -> String {
        if let assignedPhotoNumber {
            return AppLocalization.format(
                AppLocalizedPhrase.frameDisplayFormat,
                language: language,
                assignedPhotoNumber
            )
        }
        return preferredBaseDisplayName
            ?? AppLocalization.format(
                AppLocalizedPhrase.frameDisplayFormat,
                language: language,
                presentationIndex
            )
    }

    var presentationIndex: Int {
        if let assignedPhotoNumber { return assignedPhotoNumber }
        guard sourceKind == .scannerTIFF else { return scanIndex }
        let baseName = rawScanURL.deletingPathExtension().lastPathComponent
        guard let marker = baseName.range(of: "_frame_", options: .backwards) else {
            return scanIndex
        }
        let suffix = baseName[marker.upperBound...]
        guard !suffix.isEmpty,
              suffix.allSatisfy(\.isNumber),
              let fileIndex = Int(suffix),
              fileIndex > 0 else {
            return scanIndex
        }
        return fileIndex
    }

    var sourceSummary: String {
        sourceSummary(language: .system)
    }

    func sourceSummary(language: AppLanguage) -> String {
        var parts: [String] = []
        if let sourcePixelWidth, let sourcePixelHeight {
            parts.append("\(sourcePixelWidth)×\(sourcePixelHeight) px")
        }
        if let sourceResolutionDPI {
            parts.append("\(sourceResolutionDPI) dpi")
        } else if sourceKind == .importedFile {
            parts.append(AppLocalization.text(AppLocalizedPhrase.dpiUnspecified, language: language))
        }
        if let sourceBitDepth {
            parts.append("\(sourceBitDepth)-bit")
        }
        return parts.isEmpty ? sourceKind.originLabel(language: language) : parts.joined(separator: " · ")
    }

    var selectionSummary: String {
        selectionSummary(language: .system)
    }

    func selectionSummary(language: AppLanguage) -> String {
        let ratingText = rating > 0
            ? AppLocalization.format(AppLocalizedPhrase.ratingStarFormat, language: language, rating)
            : AppLocalization.text(AppLocalizedPhrase.unrated, language: language)
        let stateText: String
        switch pickState {
        case .unflagged: stateText = AppLocalization.text(AppLocalizedPhrase.unflagged, language: language)
        case .picked: stateText = AppLocalization.text(AppLocalizedPhrase.picked, language: language)
        case .rejected: stateText = AppLocalization.text(AppLocalizedPhrase.rejected, language: language)
        }
        return AppLocalization.format(AppLocalizedPhrase.selectionSummaryFormat, language: language, ratingText, stateText)
    }

    var sidecarVirtualCopyInfo: Sidecar.VirtualCopyInfo? {
        guard let virtualCopyNumber else { return nil }
        return Sidecar.VirtualCopyInfo(
            sourceFrameID: rootFrameID.uuidString,
            sourceFrameName: rootFrameDisplayName,
            copyNumber: virtualCopyNumber
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
