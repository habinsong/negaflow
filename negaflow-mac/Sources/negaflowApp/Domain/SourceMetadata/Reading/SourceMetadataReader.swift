import Foundation
import ImageIO

enum SourceMetadataReader {

    static let maximumTextLength = 16_384
    static let maximumListItemLength = 1_024
    static let maximumListCount = 512
    static let maximumSidecarBytes: Int64 = 8 * 1_024 * 1_024
    static let maximumSnapshotTextBytes = 256 * 1_024
    static let maximumEncodedSnapshotBytes = 2 * 1_024 * 1_024
    static let exifDateRegex = try? NSRegularExpression(
        pattern: #"^([0-9]{4}):([0-9]{2}):([0-9]{2}) ([0-9]{2}):([0-9]{2}):([0-9]{2})$"#
    )
    static let timeZoneOffsetRegex = try? NSRegularExpression(
        pattern: #"^([+-])([0-9]{2}):([0-9]{2})$"#
    )
    static let xmpContentDateRegex = try? NSRegularExpression(
        pattern: #"^([0-9]{4})(?:-([0-9]{2})(?:-([0-9]{2})(?:T([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.([0-9]+))?)?(Z|[+-][0-9]{2}:[0-9]{2})?)?)?)?$"#,
        options: [.caseInsensitive]
    )
    static let exifUnknownDatePlaceholder = "    :  :     :  :  "
    static let exifUnknownOffsetPlaceholder = "   :  "

    static func read(
        from url: URL,
        fileManager: FileManager = .default
    ) -> SourceMetadataSnapshot {
        let standardizedURL = url.standardizedFileURL
        let resourceValues = try? standardizedURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
        ])
        let fileSize = resourceValues?.isRegularFile == true
            ? resourceValues?.fileSize.map(Int64.init)
            : nil

        var bounds = MetadataBounds()
        var snapshot = SourceMetadataSnapshot(fileSizeBytes: fileSize)
        if let source = CGImageSourceCreateWithURL(standardizedURL as CFURL, nil) {
            let imageCount = CGImageSourceGetCount(source)
            if imageCount > 0 {
                snapshot.imageCount = imageCount
            } else {
                bounds.discardedInvalidValues = true
            }
            snapshot.fileTypeIdentifier = boundedString(
                CGImageSourceGetType(source) as String?,
                bounds: &bounds
            )
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] {
                apply(properties: properties, to: &snapshot, bounds: &bounds)
            }
            if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
                let xmp = readXMP(metadata, bounds: &bounds)
                snapshot.imageMetadataXMPView = xmp.metadata.isEmpty ? nil : xmp.metadata
                if let normalizedData = CGImageMetadataCreateXMPData(metadata, nil) as Data? {
                    snapshot.imageMetadataXMPViewSHA256 = sha256(normalizedData)
                }
                snapshot.containsStandardGPSMetadata =
                    snapshot.containsStandardGPSMetadata || xmp.containsStandardGPSMetadata
            }
        } else if fileSize != nil {
            bounds.discardedInvalidValues = true
        }

        let sidecar = readSidecarXMP(
            for: standardizedURL,
            fileManager: fileManager,
            bounds: &bounds
        )
        snapshot.sidecarXMPState = sidecar.state
        snapshot.sidecarXMP = sidecar.metadata
        snapshot.sidecarXMPFileSHA256 = sidecar.sha256
        snapshot.containsStandardGPSMetadata =
            snapshot.containsStandardGPSMetadata || sidecar.containsStandardGPSMetadata
        snapshot.discardedOversizedValues = bounds.discardedOversizedValues
        snapshot.discardedInvalidValues = bounds.discardedInvalidValues
        return snapshot
    }


}
