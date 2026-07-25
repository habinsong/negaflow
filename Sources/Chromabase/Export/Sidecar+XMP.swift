import Foundation

public extension Sidecar {
    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    func writeXMP(to url: URL) throws {
        try xmpPacket().write(to: url, atomically: true, encoding: .utf8)
    }

    func xmpPacket() -> String {
        let xmpRating = pickState == .rejected ? -1 : rating
        var attributes: [(String, String)] = [
            ("xmp:CreatorTool", "negaflow \(appVersion)"),
            ("negaflow:AppVersion", appVersion),
            ("negaflow:EngineVersion", engineVersion),
            ("negaflow:FilmType", filmType),
            ("negaflow:DevelopTarget", parameters.developTarget.rawValue),
            ("negaflow:BaseEstimationMode", parameters.baseEstimationMode.rawValue),
            ("negaflow:Exposure", Self.xmpNumber(parameters.exposure)),
            ("negaflow:Contrast", Self.xmpNumber(parameters.contrast)),
            ("negaflow:Density", Self.xmpNumber(parameters.density)),
            ("negaflow:Highlight", Self.xmpNumber(parameters.highlight)),
            ("negaflow:Shadow", Self.xmpNumber(parameters.shadow)),
            ("negaflow:Whites", Self.xmpNumber(parameters.whites)),
            ("negaflow:Blacks", Self.xmpNumber(parameters.blacks)),
            ("negaflow:Warmth", Self.xmpNumber(parameters.warmth)),
            ("negaflow:Tint", Self.xmpNumber(parameters.tint)),
            ("negaflow:ColorDepth", Self.xmpNumber(parameters.colorDepth)),
            ("negaflow:Vibrance", Self.xmpNumber(parameters.vibrance)),
            ("negaflow:Saturation", Self.xmpNumber(parameters.saturation)),
            ("negaflow:Grain", Self.xmpNumber(parameters.grain)),
            ("negaflow:Sharpness", Self.xmpNumber(parameters.sharpness)),
            ("negaflow:Halation", Self.xmpNumber(parameters.halation)),
            ("negaflow:Clarity", Self.xmpNumber(parameters.clarity)),
            ("negaflow:Vignette", Self.xmpNumber(parameters.vignette)),
            ("negaflow:DefectRemoval", Self.xmpNumber(parameters.defectRemoval)),
            ("negaflow:NoiseReduction", Self.xmpNumber(parameters.noiseReduction)),
            ("negaflow:NoiseReductionLuma", Self.xmpNumber(parameters.noiseReductionLuma)),
            ("negaflow:NoiseReductionChroma", Self.xmpNumber(parameters.noiseReductionChroma)),
            ("negaflow:NoiseReductionDarkTone", Self.xmpNumber(parameters.noiseReductionDarkTone)),
            ("negaflow:NoiseReductionDetail", Self.xmpNumber(parameters.noiseReductionDetail)),
            ("negaflow:NoiseReductionGrainProtect", Self.xmpNumber(parameters.noiseReductionGrainProtect)),
            ("xmp:Rating", String(xmpRating)),
            ("negaflow:Rating", String(rating)),
            ("negaflow:PickState", pickState.rawValue),
            ("negaflow:HistoryCount", String(developHistory.count)),
            ("negaflow:SnapshotCount", String(developSnapshots.count)),
            ("negaflow:ExportCount", String(exportHistory.count)),
        ]
        attributes.append(contentsOf: exportMetadataXMPAttributes())

        if let sourceDate {
            attributes.append(("xmp:CreateDate", Self.xmpDate(sourceDate)))
        }
        if let exportRecipe {
            attributes.append(("negaflow:ExportRecipeSHA256", exportRecipe.configurationSHA256))
            if let presetID = exportRecipe.presetID {
                attributes.append(("negaflow:ExportRecipePresetID", presetID))
            }
            if let presetName = exportRecipe.presetName {
                attributes.append(("negaflow:ExportRecipePresetName", presetName))
            }
        }
        if let metadataDate {
            let timestamp = Self.xmpDate(metadataDate)
            attributes.append(("xmp:ModifyDate", timestamp))
            attributes.append(("xmp:MetadataDate", timestamp))
        }
        if let scannerModel {
            attributes.append(("negaflow:ScannerModel", scannerModel))
        }
        if let backendUsed {
            attributes.append(("negaflow:BackendUsed", backendUsed))
        }
        if let scanResolution {
            attributes.append(("negaflow:ScanResolution", String(scanResolution)))
        }
        if let bitDepth {
            attributes.append(("negaflow:BitDepth", String(bitDepth)))
        }
        if let presetName {
            attributes.append(("negaflow:PresetName", presetName))
        }
        if let scannerProfile {
            attributes.append(("negaflow:ScannerProfileID", scannerProfile.id))
            attributes.append(("negaflow:ScannerProfileScanner", scannerProfile.scanner))
            attributes.append(("negaflow:ScannerProfileKind", scannerProfile.kind))
            attributes.append(("negaflow:ScannerProfileFilmKey", scannerProfile.filmKey))
            attributes.append(("negaflow:ScannerProfileValidationStatus", scannerProfile.validationStatus))
        }
        if let filmStockDminID = parameters.filmStockDminID {
            attributes.append(("negaflow:FilmStockDminID", filmStockDminID))
        }
        if let manualBaseRGB = parameters.manualBaseRGB {
            attributes.append(("negaflow:ManualBaseR", Self.xmpNumber(manualBaseRGB.x)))
            attributes.append(("negaflow:ManualBaseG", Self.xmpNumber(manualBaseRGB.y)))
            attributes.append(("negaflow:ManualBaseB", Self.xmpNumber(manualBaseRGB.z)))
        }
        if let baseSample {
            attributes.append(("negaflow:BaseSampleR", Self.xmpNumber(baseSample.r)))
            attributes.append(("negaflow:BaseSampleG", Self.xmpNumber(baseSample.g)))
            attributes.append(("negaflow:BaseSampleB", Self.xmpNumber(baseSample.b)))
            attributes.append(("negaflow:BaseSampleSource", baseSample.source))
        }
        if let crop {
            attributes.append(("negaflow:CropX", Self.xmpNumber(crop.x)))
            attributes.append(("negaflow:CropY", Self.xmpNumber(crop.y)))
            attributes.append(("negaflow:CropW", Self.xmpNumber(crop.w)))
            attributes.append(("negaflow:CropH", Self.xmpNumber(crop.h)))
        }
        if let virtualCopy {
            attributes.append(("negaflow:VirtualCopyNumber", String(virtualCopy.copyNumber)))
            attributes.append(("negaflow:VirtualCopySource", virtualCopy.sourceFrameName))
            attributes.append(("negaflow:VirtualCopyRawShared", virtualCopy.rawShared ? "true" : "false"))
        }

        let attributeLines = attributes
            .map { "            \($0.0)=\"\(Self.xmpEscaped($0.1))\"" }
            .joined(separator: "\n")

        return """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="negaflow">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
                xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                xmlns:dc="http://purl.org/dc/elements/1.1/"
                xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
                xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
                xmlns:exif="http://ns.adobe.com/exif/1.0/"
                xmlns:aux="http://ns.adobe.com/exif/1.0/aux/"
                xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
                xmlns:xmpRights="http://ns.adobe.com/xap/1.0/rights/"
                xmlns:Iptc4xmpCore="http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/"
                xmlns:negaflow="https://negaflow.app/ns/1.0/"
        \(attributeLines)>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

    private static func xmpNumber(_ value: Double) -> String {
        String(format: "%.6g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func xmpDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func xmpEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
