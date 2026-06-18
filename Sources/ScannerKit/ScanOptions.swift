import Foundation
import Chromabase

// MARK: - ScanOptions (plan §7.4)

/// UI가 ScannerKit에 보내는 스캔 요청.
public struct ScanOptions: Codable, Sendable, Equatable {
    public var scannerID: String
    public var resolution: Resolution
    public var bitDepth: BitDepth
    public var colorMode: ColorMode
    public var filmType: FilmType
    public var scanArea: ScanArea
    public var infraredEnabled: Bool
    public var multiExposureEnabled: Bool
    public var outputRawTIFF: Bool
    public var temporaryOutputURL: URL?

    public init(
        scannerID: String,
        resolution: Resolution = .r3600,
        bitDepth: BitDepth = .sixteen,
        colorMode: ColorMode = .color,
        filmType: FilmType = .colorNegative,
        scanArea: ScanArea = .fullFrame35mm,
        infraredEnabled: Bool = false,
        multiExposureEnabled: Bool = false,
        outputRawTIFF: Bool = true,
        temporaryOutputURL: URL? = nil
    ) {
        self.scannerID = scannerID
        self.resolution = resolution
        self.bitDepth = bitDepth
        self.colorMode = colorMode
        self.filmType = filmType
        self.scanArea = scanArea
        self.infraredEnabled = infraredEnabled
        self.multiExposureEnabled = multiExposureEnabled
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

/// 스캔 결과. RawFileURL은 항상 존재, IR 채널은 optional.
public struct ScanResult: Codable, Sendable, Equatable {
    public var rawFileURL: URL
    public var previewImage: Data?
    public var width: Int
    public var height: Int
    public var resolution: Resolution
    public var bitDepth: BitDepth
    public var colorSpace: String
    public var hasInfraredChannel: Bool
    public var infraredFileURL: URL?
    public var scanDuration: Double
    public var backendUsed: BackendType
    public var warnings: [String]

    public init(
        rawFileURL: URL,
        previewImage: Data? = nil,
        width: Int,
        height: Int,
        resolution: Resolution,
        bitDepth: BitDepth,
        colorSpace: String = "Generic RGB",
        hasInfraredChannel: Bool = false,
        infraredFileURL: URL? = nil,
        scanDuration: Double = 0,
        backendUsed: BackendType = .mock,
        warnings: [String] = []
    ) {
        self.rawFileURL = rawFileURL
        self.previewImage = previewImage
        self.width = width
        self.height = height
        self.resolution = resolution
        self.bitDepth = bitDepth
        self.colorSpace = colorSpace
        self.hasInfraredChannel = hasInfraredChannel
        self.infraredFileURL = infraredFileURL
        self.scanDuration = scanDuration
        self.backendUsed = backendUsed
        self.warnings = warnings
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
        case timeout
        case unknown
    }
    public init(_ code: Code, _ message: String = "") { self.code = code; self.message = message }
    public var errorDescription: String? { message.isEmpty ? code.rawValue : "\(code.rawValue): \(message)" }
}
