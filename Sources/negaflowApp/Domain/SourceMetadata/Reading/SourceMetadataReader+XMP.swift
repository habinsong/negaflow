import Foundation
import ImageIO

extension SourceMetadataReader {
    static func readXMP(
        _ metadata: CGImageMetadata,
        alternateTexts: [String: [String: String]] = [:],
        bounds: inout MetadataBounds
    ) -> (metadata: SourceXMPMetadata, containsStandardGPSMetadata: Bool) {
        let createDateRaw = boundedString(
            metadataString(metadata, path: "xmp:CreateDate"),
            bounds: &bounds
        )
        let dateCreatedRaw = boundedString(
            metadataString(metadata, path: "photoshop:DateCreated"),
            bounds: &bounds
        )
        let xmp = SourceXMPMetadata(
            createDateRaw: createDateRaw,
            dateCreatedRaw: dateCreatedRaw,
            title: boundedLocalizedText(
                metadata,
                path: "dc:title",
                alternateTexts: alternateTexts,
                bounds: &bounds
            ),
            description: boundedLocalizedText(
                metadata,
                path: "dc:description",
                alternateTexts: alternateTexts,
                bounds: &bounds
            ),
            creators: boundedMetadataStrings(
                metadata,
                path: "dc:creator",
                bounds: &bounds
            ),
            rights: boundedLocalizedText(
                metadata,
                path: "dc:rights",
                alternateTexts: alternateTexts,
                bounds: &bounds
            ),
            usageTerms: boundedLocalizedText(
                metadata,
                path: "xmpRights:UsageTerms",
                alternateTexts: alternateTexts,
                bounds: &bounds
            ),
            headline: boundedString(
                metadataString(metadata, path: "photoshop:Headline"),
                bounds: &bounds
            ),
            credit: boundedString(
                metadataString(metadata, path: "photoshop:Credit"),
                bounds: &bounds
            ),
            jobIdentifier: boundedString(
                metadataString(metadata, path: "photoshop:TransmissionReference"),
                bounds: &bounds
            ),
            keywords: boundedMetadataStrings(
                metadata,
                path: "dc:subject",
                bounds: &bounds
            ),
            city: boundedString(
                metadataString(metadata, path: "photoshop:City"),
                bounds: &bounds
            ),
            stateProvince: boundedString(
                metadataString(metadata, path: "photoshop:State"),
                bounds: &bounds
            ),
            country: boundedString(
                metadataString(metadata, path: "photoshop:Country"),
                bounds: &bounds
            ),
            sublocation: boundedString(
                metadataString(metadata, path: "Iptc4xmpCore:Location"),
                bounds: &bounds
            ),
            rating: metadataRating(metadata, path: "xmp:Rating", bounds: &bounds),
            label: boundedString(
                metadataString(metadata, path: "xmp:Label"),
                bounds: &bounds
            )
        )
        let containsGPS = metadataTagValue(metadata, path: "exif:GPSLatitude") != nil
            || metadataTagValue(metadata, path: "exif:GPSLongitude") != nil
        return (xmp, containsGPS)
    }

    static func metadataString(
        _ metadata: CGImageMetadata,
        path: String
    ) -> String? {
        CGImageMetadataCopyStringValueWithPath(metadata, nil, path as CFString) as String?
            ?? metadataTagValue(metadata, path: path).flatMap(stringValue)
    }

    static func metadataRating(
        _ metadata: CGImageMetadata,
        path: String,
        bounds: inout MetadataBounds
    ) -> Double? {
        guard let value = metadataTagValue(metadata, path: path) else { return nil }
        let rating: Double?
        if let number = value as? NSNumber {
            rating = number.doubleValue
        } else if let string = value as? String {
            rating = Double(string)
        } else {
            rating = nil
        }
        guard let rating,
              rating.isFinite,
              rating == -1 || (0...5).contains(rating) else {
            bounds.discardedInvalidValues = true
            return nil
        }
        return rating
    }

    static func metadataTagValue(
        _ metadata: CGImageMetadata,
        path: String
    ) -> Any? {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString) else {
            return nil
        }
        return CGImageMetadataTagCopyValue(tag)
    }

    static func boundedMetadataStrings(
        _ metadata: CGImageMetadata,
        path: String,
        bounds: inout MetadataBounds
    ) -> [String] {
        guard let value = metadataTagValue(metadata, path: path) else { return [] }
        if let tags = value as? [CGImageMetadataTag] {
            return boundedStrings(
                tags.compactMap(CGImageMetadataTagCopyValue),
                bounds: &bounds
            )
        }
        return boundedStrings(value, bounds: &bounds)
    }

    static func boundedLocalizedText(
        _ metadata: CGImageMetadata,
        path: String,
        alternateTexts: [String: [String: String]],
        bounds: inout MetadataBounds
    ) -> SourceLocalizedText? {
        let values: [String: String]
        if let preserved = alternateTexts[path] {
            values = preserved
        } else if let defaultValue = metadataString(metadata, path: path) {
            values = ["x-default": defaultValue]
        } else {
            return nil
        }
        guard !values.isEmpty, values.count <= maximumListCount else {
            if !values.isEmpty { bounds.discardedOversizedValues = true }
            return nil
        }
        var byteCount = 0
        for (language, text) in values {
            guard !language.isEmpty,
                  language.count <= maximumListItemLength,
                  text.count <= maximumTextLength else {
                bounds.discardedOversizedValues = true
                return nil
            }
            byteCount += language.utf8.count + text.utf8.count
        }
        guard bounds.reserveTextBytes(byteCount) else { return nil }
        return SourceLocalizedText(valuesByLanguage: values)
    }


}

final class XMPAlternateTextReader: NSObject, XMLParserDelegate {
    struct Result {
        var valuesByPath: [String: [String: String]]
        var hadInvalidValues: Bool
    }

    private static let dublinCoreNamespace = "http://purl.org/dc/elements/1.1/"
    private static let xmpRightsNamespace = "http://ns.adobe.com/xap/1.0/rights/"
    private static let rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

    private var currentPath: String?
    private var currentLanguage: String?
    private var currentText = ""
    private var valuesByPath: [String: [String: String]] = [:]
    private var hadInvalidValues = false

    static func read(from data: Data) -> Result {
        let reader = XMPAlternateTextReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            return Result(valuesByPath: [:], hadInvalidValues: true)
        }
        return Result(
            valuesByPath: reader.valuesByPath,
            hadInvalidValues: reader.hadInvalidValues
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if let path = Self.metadataPath(elementName: elementName, namespaceURI: namespaceURI) {
            currentPath = path
            return
        }
        guard namespaceURI == Self.rdfNamespace,
              elementName == "li",
              currentPath != nil else { return }
        currentLanguage = attributeDict["xml:lang"] ?? attributeDict["lang"]
        if currentLanguage == nil { hadInvalidValues = true }
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentLanguage != nil else { return }
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard currentLanguage != nil,
              let string = String(data: CDATABlock, encoding: .utf8) else { return }
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if namespaceURI == Self.rdfNamespace,
           elementName == "li",
           let path = currentPath,
           let language = currentLanguage {
            if valuesByPath[path]?[language] != nil {
                hadInvalidValues = true
            } else {
                valuesByPath[path, default: [:]][language] = currentText
            }
            currentLanguage = nil
            currentText = ""
            return
        }
        if Self.metadataPath(elementName: elementName, namespaceURI: namespaceURI) == currentPath {
            currentPath = nil
        }
    }

    private static func metadataPath(
        elementName: String,
        namespaceURI: String?
    ) -> String? {
        switch (namespaceURI, elementName) {
        case (dublinCoreNamespace, "title"):
            return "dc:title"
        case (dublinCoreNamespace, "description"):
            return "dc:description"
        case (dublinCoreNamespace, "rights"):
            return "dc:rights"
        case (xmpRightsNamespace, "UsageTerms"):
            return "xmpRights:UsageTerms"
        default:
            return nil
        }
    }
}
