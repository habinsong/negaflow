import Foundation

/// 비파괴 현상 상태와 내보내기 이력을 원본과 분리해 기록합니다.
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
    public var sourceDate: Date?
    public var metadataDate: Date?
    public var renderManifest: RenderManifest?
    public var exportRecipe: ExportRecipeInfo?
    public var exportEncoding: ExportEncodingInfo?
    public var exportMetadataPolicy: ExportMetadataPolicy?
    public var exportSourceMetadata: ExportSourceMetadata?

    public struct CropRect: Codable, Sendable {
        public var x: Double; public var y: Double; public var w: Double; public var h: Double

        public init(x: Double, y: Double, w: Double, h: Double) {
            self.x = x; self.y = y; self.w = w; self.h = h
        }
    }

    public struct BaseSample: Codable, Sendable {
        public var r: Double; public var g: Double; public var b: Double
        public var source: String

        public init(_ fb: FilmBase) {
            r = fb.rgb.x; g = fb.rgb.y; b = fb.rgb.z; source = fb.source.rawValue
        }
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
        public var confidence: Double?
        public var confidenceBasis: String?
        public var confidenceIsCalibratedProbability: Bool?
        public var measurement: FilmBaseMeasurementDiagnostics?

        public init(_ fb: FilmBase) {
            rgb = [fb.rgb.x, fb.rgb.y, fb.rgb.z]
            source = fb.source.rawValue
            dmin = rgb.map { -log10(max($0, 1e-6)) }
            dmax = nil
            densityRange = nil
            measurement = fb.measurementDiagnostics
            confidence = measurement?.evidenceScore
            confidenceBasis = measurement == nil ? nil : "measuredEvidenceScoreV1"
            confidenceIsCalibratedProbability = measurement?.isCalibratedProbability
        }
    }

    public struct ExportRecord: Codable, Sendable {
        public var path: String; public var format: String; public var at: Date

        public init(path: String, format: String, at: Date) {
            self.path = path; self.format = format; self.at = at
        }
    }

    public struct ExportRecipeInfo: Codable, Sendable, Equatable {
        public var presetID: String?
        public var presetName: String?
        public var configurationSHA256: String

        public init(presetID: String?, presetName: String?, configurationSHA256: String) {
            self.presetID = presetID
            self.presetName = presetName
            self.configurationSHA256 = configurationSHA256
        }
    }

    public struct ExportEncodingInfo: Codable, Sendable, Equatable {
        public var colorSpace: ExportColorSpace
        public var dpi: Int
        public var longEdge: Int?
        public var jpegQuality: Double
        public var tiffCompression: ExportTIFFCompression
        public var tiffBitDepth: ExportTIFFBitDepth
        public var preserveAlpha: Bool
        public var metadataPolicy: ExportMetadataPolicy?
        public var outputSharpening: Double?
        public var outputSharpeningMedium: OutputSharpeningMedium?

        public init(_ options: ExportOptions) {
            colorSpace = options.colorSpace
            dpi = options.dpi
            longEdge = options.longEdge
            jpegQuality = options.jpegQuality
            tiffCompression = options.tiffCompression
            tiffBitDepth = options.tiffBitDepth
            preserveAlpha = options.preserveAlpha
            metadataPolicy = options.metadataPolicy
            outputSharpening = options.outputSharpening
            outputSharpeningMedium = options.outputSharpeningMedium
        }
    }

    public struct DevelopSnapshotRecord: Codable, Sendable {
        public var id: String
        public var name: String
        public var createdAt: Date
        public var presetID: String?
        public var parameters: DevelopParameters

        public init(id: String, name: String, createdAt: Date, presetID: String?, parameters: DevelopParameters) {
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

        public init(sourceFrameID: String?, sourceFrameName: String, copyNumber: Int, rawShared: Bool = true) {
            self.sourceFrameID = sourceFrameID
            self.sourceFrameName = sourceFrameName
            self.copyNumber = copyNumber
            self.rawShared = rawShared
        }
    }

    enum CodingKeys: String, CodingKey {
        case appVersion, engineVersion, scannerModel, backendUsed, scanResolution, bitDepth
        case filmType, crop, baseSample, scannerProfile, filmBaseDiagnostics
        case scannerProfileGradeDiagnostics, presetName, parameters, virtualCopy, rating, pickState
        case developHistory, developSnapshots, exportHistory, sourceDate, metadataDate, renderManifest
        case exportRecipe, exportEncoding, exportMetadataPolicy, exportSourceMetadata
    }

    public init(
        filmType: FilmType,
        parameters: DevelopParameters,
        appVersion: String = NegaflowProductVersion.applicationVersion(),
        engineVersion: String = NegaflowProductVersion.rendererVersion
    ) {
        self.appVersion = appVersion
        self.engineVersion = engineVersion
        self.filmType = filmType.rawValue
        self.parameters = parameters
        self.virtualCopy = nil
        self.rating = 0
        self.pickState = .unflagged
        self.developHistory = []
        self.developSnapshots = []
        self.exportHistory = []
        self.sourceDate = nil
        self.metadataDate = nil
        self.renderManifest = nil
        self.exportRecipe = nil
        self.exportEncoding = nil
        self.exportMetadataPolicy = nil
        self.exportSourceMetadata = nil
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
        sourceDate = try c.decodeIfPresent(Date.self, forKey: .sourceDate)
        metadataDate = try c.decodeIfPresent(Date.self, forKey: .metadataDate)
        renderManifest = try c.decodeIfPresent(RenderManifest.self, forKey: .renderManifest)
        exportRecipe = try c.decodeIfPresent(ExportRecipeInfo.self, forKey: .exportRecipe)
        exportEncoding = try c.decodeIfPresent(ExportEncodingInfo.self, forKey: .exportEncoding)
        exportMetadataPolicy = try c.decodeIfPresent(
            ExportMetadataPolicy.self,
            forKey: .exportMetadataPolicy
        )
        exportSourceMetadata = try c.decodeIfPresent(
            ExportSourceMetadata.self,
            forKey: .exportSourceMetadata
        )
    }
}
