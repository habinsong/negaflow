import ImageIO

extension Sidecar {
    func exportMetadataXMPAttributes() -> [(String, String)] {
        var attributes: [(String, String)] = []
        if let exportMetadataPolicy {
            attributes.append(("negaflow:ExportMetadataPolicy", exportMetadataPolicy.rawValue))
        }
        guard let source = exportSourceMetadata else { return attributes }

        append(source.tiff, key: kCGImagePropertyTIFFMake, as: "tiff:Make", to: &attributes)
        append(source.tiff, key: kCGImagePropertyTIFFModel, as: "tiff:Model", to: &attributes)
        append(source.tiff, key: kCGImagePropertyTIFFArtist, as: "dc:creator", to: &attributes)
        append(source.tiff, key: kCGImagePropertyTIFFCopyright, as: "dc:rights", to: &attributes)
        append(source.exif, key: kCGImagePropertyExifLensModel, as: "aux:Lens", to: &attributes)
        append(source.iptc, key: kCGImagePropertyIPTCObjectName, as: "dc:title", to: &attributes)
        append(source.iptc, key: kCGImagePropertyIPTCCaptionAbstract, as: "dc:description", to: &attributes)
        append(source.iptc, key: kCGImagePropertyIPTCByline, as: "dc:creator", to: &attributes)
        append(source.iptc, key: kCGImagePropertyIPTCKeywords, as: "dc:subject", to: &attributes)
        append(source.iptc, key: kCGImagePropertyIPTCHeadline, as: "photoshop:Headline", to: &attributes)
        append(source.iptc, key: kCGImagePropertyIPTCCredit, as: "photoshop:Credit", to: &attributes)
        append(source.iptc, key: kCGImagePropertyIPTCSource, as: "photoshop:Source", to: &attributes)
        append(source.iptc, key: kCGImagePropertyIPTCCopyrightNotice, as: "dc:rights", to: &attributes)
        append(source.iptc, key: kCGImagePropertyIPTCRightsUsageTerms, as: "xmpRights:UsageTerms", to: &attributes)
        append(source.iptc, key: kCGImagePropertyIPTCCity, as: "photoshop:City", to: &attributes)
        append(source.iptc, key: kCGImagePropertyIPTCProvinceState, as: "photoshop:State", to: &attributes)
        append(source.iptc, key: kCGImagePropertyIPTCCountryPrimaryLocationName, as: "photoshop:Country", to: &attributes)
        append(source.iptc, key: kCGImagePropertyIPTCSubLocation, as: "Iptc4xmpCore:Location", to: &attributes)
        append(source.gps, key: kCGImagePropertyGPSLatitude, as: "exif:GPSLatitude", to: &attributes)
        append(source.gps, key: kCGImagePropertyGPSLongitude, as: "exif:GPSLongitude", to: &attributes)
        append(source.gps, key: kCGImagePropertyGPSAltitude, as: "exif:GPSAltitude", to: &attributes)
        return attributes
    }

    private func append(
        _ values: [String: ExportSourceMetadata.Value],
        key: CFString,
        as xmpKey: String,
        to attributes: inout [(String, String)]
    ) {
        guard let value = values[key as String] else { return }
        if let index = attributes.firstIndex(where: { $0.0 == xmpKey }) {
            let existing = attributes[index].1
            if existing != value.stringValue {
                attributes[index].1 = existing + ", " + value.stringValue
            }
        } else {
            attributes.append((xmpKey, value.stringValue))
        }
    }
}
