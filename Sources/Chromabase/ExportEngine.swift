import Foundation
import CoreImage
import CoreGraphics
import ImageIO

// MARK: - ExportEngine (plan §9.6, §8.3)
//
// JPEG 95% 기본 / 16bit TIFF 옵션 / Raw 보관. (plan §4.2)
// 출력은 sRGB로 변환 (plan §8.3 MVP).
// EXIF(scanner/dpi/film/software) 자동 주입.
public enum ExportEngine {
    public static func write(_ image: CIImage, to url: URL, format: ExportFormat,
                             using context: CIContext, metadata: ExportMeta? = nil,
                             options: ExportOptions = .standard) throws {
        let sized = resized(image, longEdge: options.longEdge)
        switch format {
        case .jpeg:
            try writeJPEG(sized, to: url, using: context, quality: 0.95, metadata: metadata, options: options)
        case .png:
            try writePNG(sized, to: url, using: context, metadata: metadata, options: options)
        case .tiff16:
            try writeTIFF(sized, to: url, using: context, bitsPerComponent: 16, metadata: metadata, options: options)
        case .rawScanTIFF:
            try writeTIFF(sized, to: url, using: context, bitsPerComponent: 16, metadata: metadata, options: options)
        }
    }

    /// 긴 변을 `longEdge`로 맞춰 비율 유지 축소(업스케일 안 함). nil이면 원본 그대로.
    static func resized(_ image: CIImage, longEdge: Int?) -> CIImage {
        guard let longEdge, longEdge > 0 else { return image }
        let extent = image.extent
        let currentLong = max(extent.width, extent.height)
        guard currentLong > CGFloat(longEdge) else { return image }
        let scale = CGFloat(longEdge) / currentLong
        return image
            .applyingFilter("CILanczosScaleTransform", parameters: [
                "inputScale": scale,
                "inputAspectRatio": 1.0,
            ])
            .cropped(to: CGRect(
                x: 0, y: 0,
                width: (extent.width * scale).rounded(),
                height: (extent.height * scale).rounded()
            ))
    }

    static func writeJPEG(_ image: CIImage, to url: URL, using context: CIContext,
                          quality: CGFloat, metadata: ExportMeta? = nil,
                          options: ExportOptions = .standard) throws {
        let cs = options.colorSpace.cgColorSpace
        var props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        props.merge(metadataProperties(metadata)) { _, new in new }
        // 8bit 양자화 직전 dithering으로 명부/하늘 banding 완화(OutputDither). 출력 계층에서만 적용.
        let cg = context.createCGImage(OutputDither.apply(to: image), from: image.extent, format: .RGBA8, colorSpace: cs)
        guard let cg else { throw ChromabaseError.writeFailed("createCGImage nil: \(url.path)") }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        else { throw ChromabaseError.writeFailed("CGImageDestinationCreateWithURL nil: \(url.path)") }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ChromabaseError.writeFailed("CGImageDestinationFinalize failed: \(url.path)")
        }
    }

    static func writePNG(_ image: CIImage, to url: URL, using context: CIContext,
                         metadata: ExportMeta? = nil, options: ExportOptions = .standard) throws {
        let cs = options.colorSpace.cgColorSpace
        guard let cg = context.createCGImage(OutputDither.apply(to: image), from: image.extent, format: .RGBA8, colorSpace: cs)
        else { throw ChromabaseError.writeFailed("createCGImage nil: \(url.path)") }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw ChromabaseError.writeFailed("CGImageDestinationCreateWithURL nil: \(url.path)") }
        CGImageDestinationAddImage(dest, cg, metadataProperties(metadata) as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ChromabaseError.writeFailed("CGImageDestinationFinalize failed: \(url.path)")
        }
    }

    static func writeTIFF(_ image: CIImage, to url: URL, using context: CIContext,
                          bitsPerComponent: Int, metadata: ExportMeta? = nil,
                          options: ExportOptions = .standard) throws {
        let cs = options.colorSpace.cgColorSpace
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)
        else { throw ChromabaseError.writeFailed(url.path) }
        let format: CIFormat = bitsPerComponent == 16 ? .RGBA16 : .RGBA8
        let cg = context.createCGImage(image, from: image.extent, format: format, colorSpace: cs)
        guard let cg else { throw ChromabaseError.writeFailed(url.path) }
        let props = metadataProperties(metadata) as CFDictionary
        CGImageDestinationAddImage(dest, cg, props)
        guard CGImageDestinationFinalize(dest) else {
            throw ChromabaseError.writeFailed(url.path)
        }
    }

    /// ExportMeta → CGImageDestination props(EXIF + TIFF dictionary).
    /// transform이 픽셀에 구워졌으므로 orientation=1.
    static func metadataProperties(_ meta: ExportMeta?) -> [CFString: Any] {
        guard let meta = meta else { return [:] }
        var exif: [String: Any] = [:]
        var tiff: [String: Any] = [:]
        if let make = meta.scannerModel {
            // Make = 제조사, Model = 모델명. scannerModel 이 "Plustek OpticFilm 8200i" 면
            // 첫 토큰을 Make, 나머지를 Model 로 분리.
            let parts = make.split(separator: " ", maxSplits: 1).map(String.init)
            exif["Make"] = parts.first
            tiff["Make"] = parts.first
            exif["Model"] = parts.count > 1 ? parts[1] : make
            tiff["Model"] = parts.count > 1 ? parts[1] : make
        }
        if let dpi = meta.resolutionDPI, dpi > 0 {
            exif["XResolution"] = dpi as NSNumber
            exif["YResolution"] = dpi as NSNumber
            exif["ResolutionUnit"] = 2   // inches
            tiff["XResolution"] = dpi as NSNumber
            tiff["YResolution"] = dpi as NSNumber
            tiff["ResolutionUnit"] = 2
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy:MM:dd HH:mm:ss"
        exif["DateTimeOriginal"] = df.string(from: Date())
        exif["DateTimeDigitized"] = df.string(from: Date())
        if let software = meta.software { exif["Software"] = software; tiff["Software"] = software }
        if let film = meta.filmType { exif["UserComment"] = "FilmType: \(film)" }
        exif["Orientation"] = 1   // transform 구움
        var props: [CFString: Any] = [:]
        props[kCGImagePropertyExifDictionary] = exif
        props[kCGImagePropertyTIFFDictionary] = tiff
        props[kCGImagePropertyOrientation] = 1
        return props
    }
}

/// 출력 파일에 들어갈 EXIF/TIFF 메타데이터.
public struct ExportMeta: Sendable {
    public var scannerModel: String?
    public var resolutionDPI: Int?
    public var filmType: String?
    public var software: String?
    public init(scannerModel: String? = nil, resolutionDPI: Int? = nil,
                filmType: String? = nil, software: String? = nil) {
        self.scannerModel = scannerModel
        self.resolutionDPI = resolutionDPI
        self.filmType = filmType
        self.software = software
    }
}

// MARK: - Sidecar (non-destructive editing, plan §8.11)
//
// 각 프레임마다 sidecar JSON을 저장한다. 스캔 원본은 보존된다.
public struct Sidecar: Codable, Sendable {
    public var appVersion: String
    public var engineVersion: String
    public var scannerModel: String?
    public var backendUsed: String?
    public var scanResolution: Int?
    public var bitDepth: Int?
    public var filmType: String
    public var crop: CropRect?
    public var baseSample: BaseSample?
    public var scannerProfile: ScannerProfileInfo?
    public var filmBaseDiagnostics: FilmBaseDiagnostics?
    public var scannerProfileGradeDiagnostics: ScannerProfileGradeDiagnostics?
    public var presetName: String?
    public var parameters: DevelopParameters
    public var virtualCopy: VirtualCopyInfo?
    public var rating: Int
    public var pickState: FramePickState
    public var developHistory: [DevelopHistoryEntry]
    public var developSnapshots: [DevelopSnapshotRecord]
    public var exportHistory: [ExportRecord]

    public struct CropRect: Codable, Sendable {
        public var x: Double; public var y: Double; public var w: Double; public var h: Double
        public init(x: Double, y: Double, w: Double, h: Double) {
            self.x = x; self.y = y; self.w = w; self.h = h
        }
    }
    public struct BaseSample: Codable, Sendable {
        public var r: Double; public var g: Double; public var b: Double
        public var source: String
        public init(_ fb: FilmBase) { r = fb.rgb.x; g = fb.rgb.y; b = fb.rgb.z; source = fb.source.rawValue }
    }
    public struct ScannerProfileInfo: Codable, Sendable {
        public var id: String
        public var scanner: String
        public var kind: String
        public var filmKey: String
        public var source: String
        public var profileVersion: Int
        public var profileHash: String
        public var validationStatus: String

        public init(_ profile: ScannerProfile) {
            id = profile.id
            scanner = profile.scanner
            kind = profile.kind
            filmKey = profile.filmKey
            source = "builtIn"
            profileVersion = profile.schemaVersion
            profileHash = profile.profileHash
            validationStatus = profile.validationStatus.rawValue
        }
    }
    public struct FilmBaseDiagnostics: Codable, Sendable {
        public var rgb: [Double]
        public var source: String
        public var dmin: [Double]
        public var dmax: [Double]?
        public var densityRange: [Double]?
        public var confidence: Double

        public init(_ fb: FilmBase) {
            rgb = [fb.rgb.x, fb.rgb.y, fb.rgb.z]
            source = fb.source.rawValue
            dmin = rgb.map { -log10(max($0, 1e-6)) }
            dmax = nil
            densityRange = nil
            switch fb.source {
            case .border:
                confidence = 0.86
            case .auto:
                confidence = 0.62
            case .manual:
                confidence = 1.0
            }
        }
    }
    public struct ExportRecord: Codable, Sendable {
        public var path: String; public var format: String; public var at: Date
        public init(path: String, format: String, at: Date) {
            self.path = path; self.format = format; self.at = at
        }
    }
    public struct DevelopSnapshotRecord: Codable, Sendable {
        public var id: String
        public var name: String
        public var createdAt: Date
        public var presetID: String?
        public var parameters: DevelopParameters

        public init(
            id: String,
            name: String,
            createdAt: Date,
            presetID: String?,
            parameters: DevelopParameters
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.presetID = presetID
            self.parameters = parameters
        }
    }
    public struct VirtualCopyInfo: Codable, Sendable, Equatable {
        public var sourceFrameID: String?
        public var sourceFrameName: String
        public var copyNumber: Int
        public var rawShared: Bool

        public init(
            sourceFrameID: String?,
            sourceFrameName: String,
            copyNumber: Int,
            rawShared: Bool = true
        ) {
            self.sourceFrameID = sourceFrameID
            self.sourceFrameName = sourceFrameName
            self.copyNumber = copyNumber
            self.rawShared = rawShared
        }
    }

    enum CodingKeys: String, CodingKey {
        case appVersion, engineVersion, scannerModel, backendUsed, scanResolution, bitDepth
        case filmType, crop, baseSample, scannerProfile, filmBaseDiagnostics
        case scannerProfileGradeDiagnostics, presetName, parameters, virtualCopy, rating, pickState, developHistory, developSnapshots, exportHistory
    }

    public init(filmType: FilmType, parameters: DevelopParameters) {
        self.appVersion = "0.1.0"
        self.engineVersion = "chromabase-0.1"
        self.filmType = filmType.rawValue
        self.parameters = parameters
        self.virtualCopy = nil
        self.rating = 0
        self.pickState = .unflagged
        self.developHistory = []
        self.developSnapshots = []
        self.exportHistory = []
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appVersion = try c.decode(String.self, forKey: .appVersion)
        engineVersion = try c.decode(String.self, forKey: .engineVersion)
        scannerModel = try c.decodeIfPresent(String.self, forKey: .scannerModel)
        backendUsed = try c.decodeIfPresent(String.self, forKey: .backendUsed)
        scanResolution = try c.decodeIfPresent(Int.self, forKey: .scanResolution)
        bitDepth = try c.decodeIfPresent(Int.self, forKey: .bitDepth)
        filmType = try c.decode(String.self, forKey: .filmType)
        crop = try c.decodeIfPresent(CropRect.self, forKey: .crop)
        baseSample = try c.decodeIfPresent(BaseSample.self, forKey: .baseSample)
        scannerProfile = try c.decodeIfPresent(ScannerProfileInfo.self, forKey: .scannerProfile)
        filmBaseDiagnostics = try c.decodeIfPresent(FilmBaseDiagnostics.self, forKey: .filmBaseDiagnostics)
        scannerProfileGradeDiagnostics = try c.decodeIfPresent(ScannerProfileGradeDiagnostics.self, forKey: .scannerProfileGradeDiagnostics)
        presetName = try c.decodeIfPresent(String.self, forKey: .presetName)
        parameters = try c.decode(DevelopParameters.self, forKey: .parameters)
        virtualCopy = try c.decodeIfPresent(VirtualCopyInfo.self, forKey: .virtualCopy)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        pickState = try c.decodeIfPresent(FramePickState.self, forKey: .pickState) ?? .unflagged
        developHistory = try c.decodeIfPresent([DevelopHistoryEntry].self, forKey: .developHistory) ?? []
        developSnapshots = try c.decodeIfPresent([DevelopSnapshotRecord].self, forKey: .developSnapshots) ?? []
        exportHistory = try c.decodeIfPresent([ExportRecord].self, forKey: .exportHistory) ?? []
    }

    public func write(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(self).write(to: url)
    }

    public func writeXMP(to url: URL) throws {
        try xmpPacket().write(to: url, atomically: true, encoding: .utf8)
    }

    public func xmpPacket() -> String {
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
            ("xmp:Rating", String(rating)),
            ("negaflow:Rating", String(rating)),
            ("negaflow:PickState", pickState.rawValue),
            ("negaflow:HistoryCount", String(developHistory.count)),
            ("negaflow:SnapshotCount", String(developSnapshots.count)),
            ("negaflow:ExportCount", String(exportHistory.count)),
        ]

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

    private static func xmpEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
