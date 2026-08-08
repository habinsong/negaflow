import Foundation
import Chromabase

// MARK: - ScanOptions (plan §7.4)

/// UI가 ScannerKit에 보내는 스캔 요청.
public struct ScanOptions: Codable, Sendable, Equatable {
    /// protocol v2 플러그인 요청과 결과 스트림을 결합하는 앱 소유 식별자.
    /// nil이면 외부 백엔드가 실제 scan 호출 시 새 UUID를 생성한다.
    public var requestID: UUID?
    public var scannerID: String
    public var resolution: Resolution
    public var bitDepth: BitDepth
    public var colorMode: ColorMode
    public var filmType: FilmType
    public var scanArea: ScanArea
    public var infraredEnabled: Bool
    public var multiExposureEnabled: Bool
    public var hardwareExposureTime: Int?
    public var brightnessAdjustment: Double?
    public var contrastAdjustment: Double?
    public var outputRawTIFF: Bool
    public var temporaryOutputURL: URL?

    public init(
        requestID: UUID? = nil,
        scannerID: String,
        resolution: Resolution = .r3600,
        bitDepth: BitDepth = .sixteen,
        colorMode: ColorMode = .color,
        filmType: FilmType = .colorNegative,
        scanArea: ScanArea = .fullFrame35mm,
        infraredEnabled: Bool = false,
        multiExposureEnabled: Bool = false,
        hardwareExposureTime: Int? = nil,
        brightnessAdjustment: Double? = nil,
        contrastAdjustment: Double? = nil,
        outputRawTIFF: Bool = true,
        temporaryOutputURL: URL? = nil
    ) {
        self.requestID = requestID
        self.scannerID = scannerID
        self.resolution = resolution
        self.bitDepth = bitDepth
        self.colorMode = colorMode
        self.filmType = filmType
        self.scanArea = scanArea
        self.infraredEnabled = infraredEnabled
        self.multiExposureEnabled = multiExposureEnabled
        self.hardwareExposureTime = hardwareExposureTime
        self.brightnessAdjustment = brightnessAdjustment
        self.contrastAdjustment = contrastAdjustment
        self.outputRawTIFF = outputRawTIFF
        self.temporaryOutputURL = temporaryOutputURL
    }

    /// Preview 요청용 편의 생성자.
    public static func preview(scannerID: String, filmType: FilmType = .colorNegative) -> ScanOptions {
        ScanOptions(
            scannerID: scannerID, resolution: .preview, bitDepth: .eight,
            colorMode: .color, filmType: filmType, infraredEnabled: false,
            outputRawTIFF: false
        )
    }

    /// plan §4.2 — 강한 기본값(3600dpi / 16bit / Color Negative / Auto base / IR off).
    public static func strongDefault(scannerID: String) -> ScanOptions {
        ScanOptions(scannerID: scannerID)
    }
}

// MARK: - ScanResult (plan §7.5)

/// 백엔드가 실제 적용값을 증명할 수 있는지 명시한다. Legacy protocol v1은 적용값을
/// 보고하는 계약이 없으므로 요청값을 복사하지 않고 unknown으로 보존한다.
public enum AppliedScanOptionsEvidence: Sendable, Equatable, Codable {
    case verified(ScanOptions)
    case unknownLegacy(protocolVersion: Int)

    private static let legacyProtocolVersion = 1

    private enum Kind: String, Codable {
        case verified
        case unknownLegacy
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case options
        case protocolVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .verified:
            guard !container.contains(.protocolVersion) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .protocolVersion,
                    in: container,
                    debugDescription: "verified evidence에는 protocolVersion을 기록할 수 없습니다"
                )
            }
            self = .verified(try container.decode(ScanOptions.self, forKey: .options))
        case .unknownLegacy:
            guard !container.contains(.options) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .options,
                    in: container,
                    debugDescription: "unknownLegacy evidence에는 options를 기록할 수 없습니다"
                )
            }
            let version = try container.decode(Int.self, forKey: .protocolVersion)
            guard version == Self.legacyProtocolVersion else {
                throw DecodingError.dataCorruptedError(
                    forKey: .protocolVersion,
                    in: container,
                    debugDescription: "unknownLegacy evidence는 protocol v1에만 유효합니다"
                )
            }
            self = .unknownLegacy(protocolVersion: version)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .verified(options):
            try container.encode(Kind.verified, forKey: .kind)
            try container.encode(options, forKey: .options)
        case let .unknownLegacy(protocolVersion):
            guard protocolVersion == Self.legacyProtocolVersion else {
                throw EncodingError.invalidValue(
                    protocolVersion,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "unknownLegacy evidence는 protocol v1에만 유효합니다"
                    )
                )
            }
            try container.encode(Kind.unknownLegacy, forKey: .kind)
            try container.encode(protocolVersion, forKey: .protocolVersion)
        }
    }
}

/// 스캔 결과. RawFileURL은 항상 존재, IR 채널은 optional.
public struct ScanResult: Codable, Sendable, Equatable {
    public var rawFileURL: URL
    public var previewImage: Data?
    public var width: Int
    public var height: Int
    /// 소비자가 처리에 사용할 정규화 값. Legacy v1에서는 요청 fallback일 수 있다.
    public var resolution: Resolution
    public var bitDepth: BitDepth
    /// 백엔드가 결과에서 명시적으로 보고하고 host가 유효성을 확인한 값.
    /// Legacy v1이 생략하거나 잘못 보고한 경우 nil이며 요청 fallback을 복사하지 않는다.
    public var reportedResolution: Resolution?
    public var reportedBitDepth: BitDepth?
    public var colorSpace: String
    public var hasInfraredChannel: Bool
    public var infraredFileURL: URL?
    public var scanDuration: Double
    public var backendUsed: BackendType
    public var warnings: [String]
    public var appliedOptionsEvidence: AppliedScanOptionsEvidence

    public init(
        rawFileURL: URL,
        previewImage: Data? = nil,
        width: Int,
        height: Int,
        resolution: Resolution,
        bitDepth: BitDepth,
        reportedResolution: Resolution? = nil,
        reportedBitDepth: BitDepth? = nil,
        colorSpace: String = "Generic RGB",
        hasInfraredChannel: Bool = false,
        infraredFileURL: URL? = nil,
        scanDuration: Double = 0,
        backendUsed: BackendType = .mock,
        warnings: [String] = [],
        appliedOptionsEvidence: AppliedScanOptionsEvidence
    ) {
        self.rawFileURL = rawFileURL
        self.previewImage = previewImage
        self.width = width
        self.height = height
        self.resolution = resolution
        self.bitDepth = bitDepth
        switch appliedOptionsEvidence {
        case .verified(let options):
            self.reportedResolution = reportedResolution ?? options.resolution
            self.reportedBitDepth = reportedBitDepth ?? options.bitDepth
        case .unknownLegacy:
            self.reportedResolution = reportedResolution
            self.reportedBitDepth = reportedBitDepth
        }
        self.colorSpace = colorSpace
        self.hasInfraredChannel = hasInfraredChannel
        self.infraredFileURL = infraredFileURL
        self.scanDuration = scanDuration
        self.backendUsed = backendUsed
        self.warnings = warnings
        self.appliedOptionsEvidence = appliedOptionsEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case rawFileURL
        case previewImage
        case width
        case height
        case resolution
        case bitDepth
        case reportedResolution
        case reportedBitDepth
        case colorSpace
        case hasInfraredChannel
        case infraredFileURL
        case scanDuration
        case backendUsed
        case warnings
        case appliedOptionsEvidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.reportedResolution, .reportedBitDepth]
            where !container.contains(key) {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "ScanResult reported provenance key가 누락되었습니다"
                )
            )
        }
        rawFileURL = try container.decode(URL.self, forKey: .rawFileURL)
        previewImage = try container.decodeIfPresent(Data.self, forKey: .previewImage)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        resolution = try container.decode(Resolution.self, forKey: .resolution)
        bitDepth = try container.decode(BitDepth.self, forKey: .bitDepth)
        reportedResolution = try container.decodeIfPresent(Resolution.self, forKey: .reportedResolution)
        reportedBitDepth = try container.decodeIfPresent(BitDepth.self, forKey: .reportedBitDepth)
        colorSpace = try container.decode(String.self, forKey: .colorSpace)
        hasInfraredChannel = try container.decode(Bool.self, forKey: .hasInfraredChannel)
        infraredFileURL = try container.decodeIfPresent(URL.self, forKey: .infraredFileURL)
        scanDuration = try container.decode(Double.self, forKey: .scanDuration)
        backendUsed = try container.decode(BackendType.self, forKey: .backendUsed)
        warnings = try container.decode([String].self, forKey: .warnings)
        appliedOptionsEvidence = try container.decode(
            AppliedScanOptionsEvidence.self,
            forKey: .appliedOptionsEvidence
        )
        guard hasValidReportedProvenance else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "ScanResult reported provenance가 operational/evidence 값과 모순됩니다"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        guard hasValidReportedProvenance else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "ScanResult reported provenance가 operational/evidence 값과 모순됩니다"
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawFileURL, forKey: .rawFileURL)
        try container.encodeIfPresent(previewImage, forKey: .previewImage)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(bitDepth, forKey: .bitDepth)
        try container.encode(reportedResolution, forKey: .reportedResolution)
        try container.encode(reportedBitDepth, forKey: .reportedBitDepth)
        try container.encode(colorSpace, forKey: .colorSpace)
        try container.encode(hasInfraredChannel, forKey: .hasInfraredChannel)
        try container.encodeIfPresent(infraredFileURL, forKey: .infraredFileURL)
        try container.encode(scanDuration, forKey: .scanDuration)
        try container.encode(backendUsed, forKey: .backendUsed)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(appliedOptionsEvidence, forKey: .appliedOptionsEvidence)
    }

    private var hasValidReportedProvenance: Bool {
        guard resolution.dpi >= 0 else { return false }
        switch appliedOptionsEvidence {
        case .verified(let options):
            return resolution == options.resolution
                && bitDepth == options.bitDepth
                && reportedResolution == options.resolution
                && reportedBitDepth == options.bitDepth
        case .unknownLegacy:
            return reportedResolution.map { $0.dpi >= 0 && $0 == resolution } ?? true
                && reportedBitDepth.map { $0 == bitDepth } ?? true
        }
    }
}

// MARK: - Scan progress & status (plan §9.7)

public enum ScanPhase: String, Codable, Sendable {
    case idle
    case connecting
    case warmingLamp
    case ready
    case previewScanning
    case waitingForFilmHolder
    case scanningRGB
    case scanningIR
    case processingNegative
    case renderingLook
    case exporting
    case complete
    case scannerBusy
    case disconnected
    case error
    case backendFallbackActive
}

public struct ScanProgress: Sendable, Equatable {
    public var phase: ScanPhase
    /// 0.0 ~ 1.0. 측정 불가면 nil.
    public var fraction: Double?
    public var message: String

    public init(phase: ScanPhase, fraction: Double? = nil, message: String = "") {
        self.phase = phase
        self.fraction = fraction
        self.message = message
    }
}

public struct ScannerError: Error, LocalizedError, Sendable, Equatable {
    public let code: Code
    public let message: String
    public enum Code: String, Sendable {
        case notConnected
        case busy
        case unsupportedOption
        case driverConflict
        case ioFailure
        case cancelled
        case interrupted
        case timeout
        case unknown
    }
    public init(_ code: Code, _ message: String = "") { self.code = code; self.message = message }
    public var errorDescription: String? { message.isEmpty ? code.rawValue : "\(code.rawValue): \(message)" }
}
