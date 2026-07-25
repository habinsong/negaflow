import Foundation
import ImageIO

public enum ExportMetadataPolicy: String, Codable, CaseIterable, Sendable {
    case all
    case copyrightOnly
    case removeLocation
    case minimal
}

public struct ExportSourceMetadata: Codable, Equatable, Sendable {
    public var tiff: [String: Value]
    public var exif: [String: Value]
    public var iptc: [String: Value]
    public var gps: [String: Value]

    public init(
        tiff: [String: Value] = [:],
        exif: [String: Value] = [:],
        iptc: [String: Value] = [:],
        gps: [String: Value] = [:]
    ) {
        self.tiff = tiff
        self.exif = exif
        self.iptc = iptc
        self.gps = gps
    }

    public enum Value: Codable, Equatable, Sendable {
        case string(String)
        case number(Double)
        case integer(Int)
        case boolean(Bool)
        case strings([String])
        case numbers([Double])

        fileprivate init?(_ value: Any) {
            switch value {
            case let value as String where value.utf8.count <= 4_096:
                self = .string(value)
            case let value as NSNumber:
                if CFGetTypeID(value) == CFBooleanGetTypeID() {
                    self = .boolean(value.boolValue)
                } else if value.doubleValue.rounded() == value.doubleValue {
                    self = .integer(value.intValue)
                } else if value.doubleValue.isFinite {
                    self = .number(value.doubleValue)
                } else {
                    return nil
                }
            case let values as [String] where values.count <= 128
                && values.allSatisfy({ $0.utf8.count <= 4_096 }):
                self = .strings(values)
            case let values as [NSNumber] where values.count <= 128
                && values.allSatisfy({ $0.doubleValue.isFinite }):
                self = .numbers(values.map(\.doubleValue))
            default:
                return nil
            }
        }

        var propertyListValue: Any {
            switch self {
            case let .string(value): value
            case let .number(value): value as NSNumber
            case let .integer(value): value as NSNumber
            case let .boolean(value): value as NSNumber
            case let .strings(value): value
            case let .numbers(value): value.map { $0 as NSNumber }
            }
        }

        public var stringValue: String {
            switch self {
            case let .string(value):
                return value
            case let .number(value):
                return String(value)
            case let .integer(value):
                return String(value)
            case let .boolean(value):
                return value ? "true" : "false"
            case let .strings(value):
                return value.joined(separator: ", ")
            case let .numbers(value):
                return value.map { String($0) }.joined(separator: ", ")
            }
        }
    }

    public static func read(from url: URL) -> Self? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else {
            return nil
        }
        return Self(
            tiff: values(in: properties[kCGImagePropertyTIFFDictionary]),
            exif: values(in: properties[kCGImagePropertyExifDictionary]),
            iptc: values(in: properties[kCGImagePropertyIPTCDictionary]),
            gps: values(in: properties[kCGImagePropertyGPSDictionary])
        )
    }

    public func filtered(for policy: ExportMetadataPolicy) -> Self? {
        let result: Self
        switch policy {
        case .all:
            result = self
        case .removeLocation:
            var filteredIPTC = iptc
            Self.locationIPTCKeys.forEach { filteredIPTC.removeValue(forKey: $0) }
            result = Self(tiff: tiff, exif: exif, iptc: filteredIPTC)
        case .copyrightOnly:
            result = Self(
                tiff: tiff.filter { Self.copyrightTIFFKeys.contains($0.key) },
                iptc: iptc.filter { Self.copyrightIPTCKeys.contains($0.key) }
            )
        case .minimal:
            return nil
        }
        return result.isEmpty ? nil : result
    }

    var imageProperties: [CFString: Any] {
        var result: [CFString: Any] = [:]
        if !tiff.isEmpty { result[kCGImagePropertyTIFFDictionary] = propertyList(tiff) }
        if !exif.isEmpty { result[kCGImagePropertyExifDictionary] = propertyList(exif) }
        if !iptc.isEmpty { result[kCGImagePropertyIPTCDictionary] = propertyList(iptc) }
        if !gps.isEmpty { result[kCGImagePropertyGPSDictionary] = propertyList(gps) }
        return result
    }

    public var isEmpty: Bool {
        tiff.isEmpty && exif.isEmpty && iptc.isEmpty && gps.isEmpty
    }

    private static func values(in value: Any?) -> [String: Value] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        return dictionary.reduce(into: [:]) { result, pair in
            if let value = Value(pair.value) { result[pair.key] = value }
        }
    }

    private func propertyList(_ values: [String: Value]) -> [String: Any] {
        values.mapValues(\.propertyListValue)
    }

    private static let locationIPTCKeys: Set<String> = [
        kCGImagePropertyIPTCCity as String,
        kCGImagePropertyIPTCSubLocation as String,
        kCGImagePropertyIPTCProvinceState as String,
        kCGImagePropertyIPTCCountryPrimaryLocationCode as String,
        kCGImagePropertyIPTCCountryPrimaryLocationName as String,
    ]
    private static let copyrightTIFFKeys: Set<String> = [
        kCGImagePropertyTIFFArtist as String,
        kCGImagePropertyTIFFCopyright as String,
    ]
    private static let copyrightIPTCKeys: Set<String> = [
        kCGImagePropertyIPTCByline as String,
        kCGImagePropertyIPTCBylineTitle as String,
        kCGImagePropertyIPTCCredit as String,
        kCGImagePropertyIPTCSource as String,
        kCGImagePropertyIPTCCopyrightNotice as String,
        kCGImagePropertyIPTCRightsUsageTerms as String,
    ]
}
