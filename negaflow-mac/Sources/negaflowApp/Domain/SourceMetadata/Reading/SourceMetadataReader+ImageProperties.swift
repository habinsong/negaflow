import Foundation
import ImageIO

extension SourceMetadataReader {
    static func apply(
        properties: [CFString: Any],
        to snapshot: inout SourceMetadataSnapshot,
        bounds: inout MetadataBounds
    ) {
        snapshot.pixelWidth = positiveRoundedInt(properties[kCGImagePropertyPixelWidth])
        snapshot.pixelHeight = positiveRoundedInt(properties[kCGImagePropertyPixelHeight])
        snapshot.bitsPerColorSample = positiveRoundedInt(properties[kCGImagePropertyDepth])
        snapshot.orientation = orientationValue(properties[kCGImagePropertyOrientation])
        snapshot.colorModel = boundedString(
            stringValue(properties[kCGImagePropertyColorModel]),
            bounds: &bounds
        )
        snapshot.colorProfileName = boundedString(
            stringValue(properties[kCGImagePropertyProfileName]),
            bounds: &bounds
        )
        snapshot.namedColorSpace = boundedString(
            stringValue(properties[kCGImagePropertyNamedColorSpace]),
            bounds: &bounds
        )
        let tiffResolution = tiffDPI(properties)
        let dpiX = tiffResolution.isAuthoritative
            ? tiffResolution.x
            : positiveDouble(properties[kCGImagePropertyDPIWidth])
        let dpiY = tiffResolution.isAuthoritative
            ? tiffResolution.y
            : positiveDouble(properties[kCGImagePropertyDPIHeight])
        snapshot.dpiWidth = dpiX
        snapshot.dpiHeight = dpiY
        snapshot.resolutionDPI = normalizedDPI(x: dpiX, y: dpiY)

        let tiff = nestedDictionary(properties[kCGImagePropertyTIFFDictionary])
        let exifValues = nestedDictionary(properties[kCGImagePropertyExifDictionary])
        let dateTimeRaw = boundedString(
            stringValue(exifValues[kCGImagePropertyExifDateTimeOriginal as String]),
            bounds: &bounds
        )
        let offsetRaw = boundedString(
            stringValue(exifValues[kCGImagePropertyExifOffsetTimeOriginal as String]),
            bounds: &bounds
        )
        let subsecondRaw = boundedString(
            stringValue(exifValues[kCGImagePropertyExifSubsecTimeOriginal as String]),
            bounds: &bounds
        )
        let exif = SourceEXIFMetadata(
            dateTimeOriginalRaw: dateTimeRaw,
            offsetTimeOriginalRaw: offsetRaw,
            subsecondTimeOriginalRaw: subsecondRaw,
            cameraMake: boundedString(
                stringValue(tiff[kCGImagePropertyTIFFMake as String]),
                bounds: &bounds
            ),
            cameraModel: boundedString(
                stringValue(tiff[kCGImagePropertyTIFFModel as String]),
                bounds: &bounds
            ),
            lensModel: boundedString(
                stringValue(exifValues[kCGImagePropertyExifLensModel as String]),
                bounds: &bounds
            ),
            software: boundedString(
                stringValue(tiff[kCGImagePropertyTIFFSoftware as String]),
                bounds: &bounds
            ),
            exposureTimeSeconds: positiveDouble(
                exifValues[kCGImagePropertyExifExposureTime as String]
            ),
            fNumber: positiveDouble(exifValues[kCGImagePropertyExifFNumber as String]),
            isoSpeedRatings: boundedPositiveInts(
                exifValues[kCGImagePropertyExifISOSpeedRatings as String],
                bounds: &bounds
            ),
            focalLengthMM: positiveDouble(
                exifValues[kCGImagePropertyExifFocalLength as String]
            )
        )
        snapshot.exif = exif.isEmpty ? nil : exif

        let iptcValues = nestedDictionary(properties[kCGImagePropertyIPTCDictionary])
        let iptc = SourceIPTCMetadata(
            title: boundedString(
                stringValue(iptcValues[kCGImagePropertyIPTCObjectName as String]),
                bounds: &bounds
            ),
            headline: boundedString(
                stringValue(iptcValues[kCGImagePropertyIPTCHeadline as String]),
                bounds: &bounds
            ),
            caption: boundedString(
                stringValue(iptcValues[kCGImagePropertyIPTCCaptionAbstract as String]),
                bounds: &bounds
            ),
            creators: boundedStrings(
                iptcValues[kCGImagePropertyIPTCByline as String],
                bounds: &bounds
            ),
            credit: boundedString(
                stringValue(iptcValues[kCGImagePropertyIPTCCredit as String]),
                bounds: &bounds
            ),
            copyrightNotice: boundedString(
                stringValue(iptcValues[kCGImagePropertyIPTCCopyrightNotice as String]),
                bounds: &bounds
            ),
            rightsUsageTerms: boundedString(
                stringValue(iptcValues[kCGImagePropertyIPTCRightsUsageTerms as String]),
                bounds: &bounds
            ),
            source: boundedString(
                stringValue(iptcValues[kCGImagePropertyIPTCSource as String]),
                bounds: &bounds
            ),
            jobIdentifier: boundedString(
                stringValue(
                    iptcValues[kCGImagePropertyIPTCOriginalTransmissionReference as String]
                ),
                bounds: &bounds
            ),
            keywords: boundedStrings(
                iptcValues[kCGImagePropertyIPTCKeywords as String],
                bounds: &bounds
            ),
            city: boundedString(
                stringValue(iptcValues[kCGImagePropertyIPTCCity as String]),
                bounds: &bounds
            ),
            stateProvince: boundedString(
                stringValue(iptcValues[kCGImagePropertyIPTCProvinceState as String]),
                bounds: &bounds
            ),
            country: boundedString(
                stringValue(
                    iptcValues[kCGImagePropertyIPTCCountryPrimaryLocationName as String]
                ),
                bounds: &bounds
            ),
            countryCode: boundedString(
                stringValue(
                    iptcValues[kCGImagePropertyIPTCCountryPrimaryLocationCode as String]
                ),
                bounds: &bounds
            ),
            sublocation: boundedString(
                stringValue(iptcValues[kCGImagePropertyIPTCSubLocation as String]),
                bounds: &bounds
            )
        )
        snapshot.iptc = iptc.isEmpty ? nil : iptc
        snapshot.containsStandardGPSMetadata =
            !nestedDictionary(properties[kCGImagePropertyGPSDictionary]).isEmpty
    }

    static func boundedString(
        _ value: String?,
        bounds: inout MetadataBounds
    ) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard value.count <= maximumTextLength,
              bounds.reserveTextBytes(value.utf8.count) else {
            bounds.discardedOversizedValues = true
            return nil
        }
        return value
    }

    static func boundedStrings(
        _ value: Any?,
        bounds: inout MetadataBounds
    ) -> [String] {
        let rawValues: [Any]
        switch value {
        case let values as [Any]:
            rawValues = values
        case .some(let value):
            rawValues = [value]
        case .none:
            return []
        }
        guard rawValues.count <= maximumListCount else {
            bounds.discardedOversizedValues = true
            return []
        }
        var result: [String] = []
        var byteCount = 0
        for rawValue in rawValues {
            guard let rawString = stringValue(rawValue) else {
                bounds.discardedInvalidValues = true
                return []
            }
            let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                bounds.discardedInvalidValues = true
                return []
            }
            guard rawString.count <= maximumListItemLength else {
                bounds.discardedOversizedValues = true
                return []
            }
            byteCount += rawString.utf8.count
            result.append(rawString)
        }
        guard bounds.reserveTextBytes(byteCount) else { return [] }
        return result
    }

    static func boundedPositiveInts(
        _ value: Any?,
        bounds: inout MetadataBounds
    ) -> [Int] {
        let rawValues: [Any]
        switch value {
        case let values as [Any]: rawValues = values
        case .some(let value): rawValues = [value]
        case .none: return []
        }
        guard rawValues.count <= maximumListCount else {
            bounds.discardedOversizedValues = true
            return []
        }
        var result: [Int] = []
        for raw in rawValues {
            let number: Double?
            if let value = raw as? NSNumber {
                number = value.doubleValue
            } else if let value = raw as? String {
                number = Double(value)
            } else {
                number = nil
            }
            guard let number,
                  number.isFinite,
                  number > 0,
                  number.rounded() == number,
                  number < Double(Int.max) else {
                bounds.discardedInvalidValues = true
                return []
            }
            result.append(Int(number))
        }
        return result
    }

    static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String: return value
        case let value as NSString: return value as String
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    static func positiveDouble(_ value: Any?) -> Double? {
        let result: Double?
        switch value {
        case let value as NSNumber: result = value.doubleValue
        case let value as String: result = Double(value)
        default: result = nil
        }
        guard let result, result.isFinite, result > 0 else { return nil }
        return result
    }

    static func positiveRoundedInt(_ value: Any?) -> Int? {
        guard let value = positiveDouble(value) else { return nil }
        let rounded = value.rounded()
        guard rounded < Double(Int.max) else { return nil }
        return Int(rounded)
    }

    static func orientationValue(_ value: Any?) -> Int? {
        let orientation: Int?
        switch value {
        case let number as NSNumber: orientation = number.intValue
        case let string as String: orientation = Int(string)
        default: orientation = nil
        }
        guard let orientation, (1...8).contains(orientation) else { return nil }
        return orientation
    }

    static func nestedDictionary(_ value: Any?) -> [String: Any] {
        if let dictionary = value as? [String: Any] { return dictionary }
        if let dictionary = value as? [CFString: Any] {
            return Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key as String, $0.value) })
        }
        return [:]
    }

    static func tiffDPI(
        _ properties: [CFString: Any]
    ) -> (isAuthoritative: Bool, x: Double?, y: Double?) {
        let tiff = nestedDictionary(properties[kCGImagePropertyTIFFDictionary])
        let xKey = kCGImagePropertyTIFFXResolution as String
        let yKey = kCGImagePropertyTIFFYResolution as String
        let unitKey = kCGImagePropertyTIFFResolutionUnit as String
        let hasRawResolution = tiff[xKey] != nil || tiff[yKey] != nil
        guard hasRawResolution else { return (false, nil, nil) }

        let resolutionUnit: Int
        if let rawUnit = tiff[unitKey] {
            guard let numericUnit = positiveDouble(rawUnit),
                  numericUnit.rounded() == numericUnit,
                  numericUnit < Double(Int.max) else {
                return (true, nil, nil)
            }
            resolutionUnit = Int(numericUnit)
        } else {
            // TIFF 6.0은 ResolutionUnit을 생략한 경우 inch(2)를 기본값으로 정의한다.
            resolutionUnit = 2
        }

        let factor: Double
        switch resolutionUnit {
        case 1:
            // TIFF 6.0의 1은 절대 측정 단위가 없다는 뜻이므로 ImageIO가 승격한
            // 최상위 DPI 숫자도 물리 해상도 사실로 사용하지 않는다.
            return (true, nil, nil)
        case 2:
            factor = 1
        case 3:
            factor = 2.54
        default:
            return (true, nil, nil)
        }
        let x = positiveDouble(tiff[xKey]).map { $0 * factor }
        let y = positiveDouble(tiff[yKey]).map { $0 * factor }
        return (
            true,
            x?.isFinite == true ? x : nil,
            y?.isFinite == true ? y : nil
        )
    }

    static func normalizedDPI(x: Double?, y: Double?) -> Int? {
        switch (x, y) {
        case let (x?, y?): return positiveRoundedInt((x + y) / 2)
        case let (x?, nil): return positiveRoundedInt(x)
        case let (nil, y?): return positiveRoundedInt(y)
        case (nil, nil): return nil
        }
    }


}
