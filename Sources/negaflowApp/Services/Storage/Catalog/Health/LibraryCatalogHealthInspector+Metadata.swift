import Foundation
import ScannerKit
import Chromabase

extension LibraryCatalogHealthInspector {
    static func inspectSourceMetadata(
        _ metadata: SourceMetadataSnapshot,
        frame: LibraryFrameRecord,
        frameIndex: Int,
        issues: inout [LibraryCatalogHealthIssue]
    ) {
        guard metadata.version == SourceMetadataSnapshot.currentVersion else {
            issues.append(issue(
                .unsupportedSourceMetadataVersion,
                .error,
                frameID: frame.id,
                frameIndex: frameIndex
            ))
            return
        }

        let invalidScalar = metadata.fileSizeBytes.map { $0 <= 0 } ?? false
            || metadata.imageIndex < 0
            || metadata.imageCount.map { $0 <= 0 || metadata.imageIndex >= $0 } ?? false
            || metadata.pixelWidth.map { $0 <= 0 } ?? false
            || metadata.pixelHeight.map { $0 <= 0 } ?? false
            || metadata.dpiWidth.map { !$0.isFinite || $0 <= 0 } ?? false
            || metadata.dpiHeight.map { !$0.isFinite || $0 <= 0 } ?? false
            || metadata.resolutionDPI.map { $0 <= 0 } ?? false
            || metadata.bitsPerColorSample.map { $0 <= 0 } ?? false
            || metadata.orientation.map { !(1...8).contains($0) } ?? false
        let mismatchesLegacyFacts = frame.sourceKind == FrameSource.importedFile.storageKey
            && (differs(metadata.pixelWidth, frame.sourcePixelWidth)
                || differs(metadata.pixelHeight, frame.sourcePixelHeight)
                || differs(metadata.resolutionDPI, frame.sourceResolutionDPI)
                || differs(metadata.bitsPerColorSample, frame.sourceBitDepth))
        let invalidSidecarState = metadata.sidecarXMPState != .loaded
            && metadata.sidecarXMP != nil
        let invalidMetadataHashes = !validSHA256(metadata.imageMetadataXMPViewSHA256)
            || !validSHA256(metadata.sidecarXMPFileSHA256)
            || (metadata.sidecarXMPState == .loaded && metadata.sidecarXMPFileSHA256 == nil)
            || ([.notFound, .tooLarge, .ambiguous].contains(metadata.sidecarXMPState)
                && metadata.sidecarXMPFileSHA256 != nil)
        let invalidEXIF = metadata.exif.map { exif in
            !validPositiveNumber(exif.exposureTimeSeconds)
                || !validPositiveNumber(exif.fNumber)
                || !validPositiveNumber(exif.focalLengthMM)
                || exif.isoSpeedRatings.count > SourceMetadataReader.maximumListCount
                || exif.isoSpeedRatings.contains(where: { $0 <= 0 })
                || !validStrings([
                    exif.dateTimeOriginalRaw,
                    exif.offsetTimeOriginalRaw,
                    exif.subsecondTimeOriginalRaw,
                    exif.cameraMake,
                    exif.cameraModel,
                    exif.lensModel,
                    exif.software,
                ].compactMap { $0 })
        } ?? false
        let invalidIPTC = metadata.iptc.map { iptc in
            !validStrings([
                iptc.title,
                iptc.headline,
                iptc.caption,
                iptc.credit,
                iptc.copyrightNotice,
                iptc.rightsUsageTerms,
                iptc.source,
                iptc.jobIdentifier,
                iptc.city,
                iptc.stateProvince,
                iptc.country,
                iptc.countryCode,
                iptc.sublocation,
            ].compactMap { $0 })
                || !validStringList(iptc.creators)
                || !validStringList(iptc.keywords)
        } ?? false
        let invalidImageMetadataXMPView = metadata.imageMetadataXMPView.map(invalidXMP) ?? false
        let invalidSidecarXMP = metadata.sidecarXMP.map(invalidXMP) ?? false
        let invalidTopLevelStrings = !validStrings([
            metadata.fileTypeIdentifier,
            metadata.colorModel,
            metadata.colorProfileName,
            metadata.namedColorSpace,
        ].compactMap { $0 })
        let invalidEncodedSize = (try? JSONEncoder().encode(metadata).count)
            .map { $0 > SourceMetadataReader.maximumEncodedSnapshotBytes } ?? true

        if invalidScalar
            || mismatchesLegacyFacts
            || invalidSidecarState
            || invalidMetadataHashes
            || invalidEXIF
            || invalidIPTC
            || invalidImageMetadataXMPView
            || invalidSidecarXMP
            || invalidTopLevelStrings
            || invalidEncodedSize {
            issues.append(issue(
                .invalidSourceMetadata,
                .error,
                frameID: frame.id,
                frameIndex: frameIndex
            ))
        }
    }

    static func invalidXMP(_ xmp: SourceXMPMetadata) -> Bool {
        xmp.rating.map { !$0.isFinite || !($0 == -1 || (0...5).contains($0)) } ?? false
            || !validStrings([
                xmp.createDateRaw,
                xmp.dateCreatedRaw,
                xmp.headline,
                xmp.credit,
                xmp.jobIdentifier,
                xmp.city,
                xmp.stateProvince,
                xmp.country,
                xmp.sublocation,
                xmp.label,
            ].compactMap { $0 })
            || !validLocalizedText(xmp.title)
            || !validLocalizedText(xmp.description)
            || !validLocalizedText(xmp.rights)
            || !validLocalizedText(xmp.usageTerms)
            || !validStringList(xmp.creators)
            || !validStringList(xmp.keywords)
    }

    static func validStrings(_ values: [String]) -> Bool {
        values.allSatisfy { value in
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && value.count <= SourceMetadataReader.maximumTextLength
        }
    }

    static func validStringList(_ values: [String]) -> Bool {
        guard values.count <= SourceMetadataReader.maximumListCount else { return false }
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.count <= SourceMetadataReader.maximumListItemLength else {
                return false
            }
        }
        return true
    }

    static func validLocalizedText(_ value: SourceLocalizedText?) -> Bool {
        guard let value else { return true }
        guard !value.valuesByLanguage.isEmpty,
              value.valuesByLanguage.count <= SourceMetadataReader.maximumListCount else {
            return false
        }
        return value.valuesByLanguage.allSatisfy { language, text in
            !language.isEmpty
                && language.count <= SourceMetadataReader.maximumListItemLength
                && text.count <= SourceMetadataReader.maximumTextLength
        }
    }

    static func validPositiveNumber(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && value > 0
    }

    static func validSHA256(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    static func requiredSHA256(_ value: String?) -> Bool {
        value != nil && validSHA256(value)
    }

    static func differs<T: Equatable>(_ lhs: T?, _ rhs: T?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs != rhs
    }


}
