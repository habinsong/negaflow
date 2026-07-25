import Foundation

// MARK: - Scanner plugin manifest & wire protocol
//
// negaflow(Apache-2.0)는 스캐너 백엔드를 내장하지 않는다. 스캐너 인식/제어는 설치형
// 외부 프로세스 플러그인이 담당하며, negaflow는 아래 JSON/CLI 계약으로만 통신한다.
// 본체는 플러그인 구현을 링크하거나 배포하지 않으며, 실제 라이선스 의무는 각 배포물과
// 통신 구조를 기준으로 따로 검토한다.
//
// 플러그인 설치 위치:
//   ~/Library/Application Support/negaflow/Plugins/<id>/manifest.json
//   실행파일은 manifest 의 `executable`(상대경로면 manifest 디렉토리 기준) 로 해석한다.

/// 플러그인 디렉토리의 manifest.json 스키마.
public struct ScannerPluginManifest: Codable, Sendable, Equatable {
    /// 이 호스트가 정확히 해석하는 manifest.json 스키마 버전.
    public static let supportedSchemaVersion = 1
    public static let legacyProtocolVersion = 1
    public static let streamProtocolVersion = 2
    public static let supportedProtocolVersions = legacyProtocolVersion...streamProtocolVersion

    public var schemaVersion: Int
    /// 누락된 기존 manifest는 protocol v1으로 해석한다.
    public var protocolVersion: Int?
    public var id: String
    public var name: String
    public var executable: String
    public var kind: String?          // "scanner"
    public var license: String?
    public var homepage: String?
    public var pluginVersion: String?

    public init(schemaVersion: Int, protocolVersion: Int? = nil,
                id: String, name: String, executable: String,
                kind: String? = "scanner", license: String? = nil,
                homepage: String? = nil, pluginVersion: String? = nil) {
        self.schemaVersion = schemaVersion
        self.protocolVersion = protocolVersion
        self.id = id
        self.name = name
        self.executable = executable
        self.kind = kind
        self.license = license
        self.homepage = homepage
        self.pluginVersion = pluginVersion
    }

    public var resolvedProtocolVersion: Int {
        protocolVersion ?? Self.legacyProtocolVersion
    }

    /// Scanner ID routing uses `plugin:<pluginId>:<deviceId>`, so plugin IDs must not
    /// contain the `:` delimiter or any filesystem/control characters.
    public static func isValidPluginID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard (1...64).contains(bytes.count), let first = bytes.first else { return false }

        func isASCIILetterOrDigit(_ byte: UInt8) -> Bool {
            (byte >= 0x30 && byte <= 0x39)
                || (byte >= 0x41 && byte <= 0x5A)
                || (byte >= 0x61 && byte <= 0x7A)
        }

        guard isASCIILetterOrDigit(first) else { return false }
        return bytes.allSatisfy { byte in
            isASCIILetterOrDigit(byte) || byte == 0x2D || byte == 0x2E || byte == 0x5F
        }
    }

    public var isSupportedByHost: Bool {
        schemaVersion == Self.supportedSchemaVersion
            && Self.supportedProtocolVersions.contains(resolvedProtocolVersion)
            && Self.isValidPluginID(id)
    }
}

/// 발견되어 실행 가능하게 해석된 설치 플러그인.
public struct ScannerPluginTrustIdentity: Codable, Sendable, Equatable {
    public let pluginID: String
    public let pluginVersion: String?
    public let manifestSHA256: String
    public let executableSHA256: String

    public init(
        pluginID: String,
        pluginVersion: String?,
        manifestSHA256: String,
        executableSHA256: String
    ) {
        self.pluginID = pluginID
        self.pluginVersion = pluginVersion
        self.manifestSHA256 = manifestSHA256
        self.executableSHA256 = executableSHA256
    }
}

public struct InstalledScannerPlugin: Sendable, Equatable, Identifiable {
    public let manifest: ScannerPluginManifest
    public let manifestURL: URL
    public let executableURL: URL
    public let trustIdentity: ScannerPluginTrustIdentity?

    public var id: String { manifest.id }
    public var name: String { manifest.name }

    public init(
        manifest: ScannerPluginManifest,
        manifestURL: URL,
        executableURL: URL,
        trustIdentity: ScannerPluginTrustIdentity? = nil
    ) {
        self.manifest = manifest
        self.manifestURL = manifestURL
        self.executableURL = executableURL
        self.trustIdentity = trustIdentity
    }
}

// MARK: - Wire protocol (플러그인 stdout JSON)
//
// negaflow 내부 타입(ScannerDescriptor 등)과 분리된 안정적 와이어 포맷.
// 플러그인 쪽에도 동일 스키마의 Codable 이 존재한다.

public struct PluginDevice: Codable, Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var vendor: String
    public var model: String
    public var connectionType: String?
    public var usbVendorID: String?
    public var usbProductID: String?
    public var serialNumber: String?
    public var verifiedStatus: String?
    public var driverVersion: String?
}

public struct PluginDetectResponse: Codable, Sendable, Equatable {
    public var devices: [PluginDevice]
}

/// capability 조회 때 detect가 보고한 장치 식별 정보를 다시 전달한다.
/// 플러그인은 주소가 바뀐 장치를 같은 backend의 다른 모델과 구분할 수 있다.
public struct PluginCapabilityRequest: Codable, Sendable, Equatable {
    public var deviceID: String
    public var vendor: String
    public var model: String

    public init(deviceID: String, vendor: String, model: String) {
        self.deviceID = deviceID
        self.vendor = vendor
        self.model = model
    }
}

public struct PluginCapabilities: Codable, Sendable, Equatable {
    public var resolutionsDPI: [Int]
    public var modes: [String]
    public var bitDepths: [Int]
    public var sourceModes: [String]?
    public var transparencyModes: [String]?
    public var supportsPreview: Bool?
    public var supportsTransparency: Bool?
    public var supportsInfrared: Bool?
    public var supportsMultiExposure: Bool?
    public var supportsScanArea: Bool?
    public var supportsPositionedScanArea: Bool?
    public var brightnessRange: ScannerOptionRange?
    public var contrastRange: ScannerOptionRange?
    public var hardwareExposureRange: ScannerOptionRange?
    public var scanOriginXRange: ScannerOptionRange?
    public var scanOriginYRange: ScannerOptionRange?
    public var scanWidthRange: ScannerOptionRange?
    public var scanHeightRange: ScannerOptionRange?
    public var disabledReasons: [String: String]?
    public var minScanAreaWidthMM: Double?
    public var minScanAreaHeightMM: Double?
    public var minScanAreaOriginXMM: Double?
    public var minScanAreaOriginYMM: Double?
    public var maxScanAreaWidthMM: Double?
    public var maxScanAreaHeightMM: Double?
    public var maxScanAreaOriginXMM: Double?
    public var maxScanAreaOriginYMM: Double?
    public var scanAreaUnit: String?
    public var outputFormats: [String]?
    /// 플러그인이 capability 조회 때 만든 불투명 스냅샷. Host는 해석하지 않고 같은
    /// scannerID의 다음 scan 요청에 그대로 돌려준다.
    public var capabilityToken: String?
}

public struct PluginScanOptions: Codable, Sendable, Equatable {
    /// protocol v2에서만 전송한다. v1에서는 두 필드 모두 JSON에서 생략된다.
    public var protocolVersion: Int?
    public var requestID: UUID?
    public var deviceID: String
    public var resolutionDPI: Int      // 0 = preview
    public var bitDepth: Int
    public var colorMode: String
    public var filmType: String
    public var preview: Bool
    public var multiExposure: Bool
    public var infrared: Bool          // IR 지원 기기에서 적외선 채널/모드로 스캔
    public var brightnessAdjustment: Double?
    public var contrastAdjustment: Double?
    public var scanArea: ScanArea?
    public var hardwareExposureTime: Int?
    public var outputRawTIFF: Bool?
    public var capabilityToken: String?
    public var outputPath: String

    public init(protocolVersion: Int? = nil, requestID: UUID? = nil,
                deviceID: String, resolutionDPI: Int, bitDepth: Int, colorMode: String,
                filmType: String, preview: Bool, multiExposure: Bool, infrared: Bool = false,
                brightnessAdjustment: Double? = nil, contrastAdjustment: Double? = nil,
                scanArea: ScanArea? = nil, hardwareExposureTime: Int? = nil,
                outputRawTIFF: Bool? = nil,
                capabilityToken: String? = nil,
                outputPath: String) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.deviceID = deviceID
        self.resolutionDPI = resolutionDPI
        self.bitDepth = bitDepth
        self.colorMode = colorMode
        self.filmType = filmType
        self.preview = preview
        self.multiExposure = multiExposure
        self.infrared = infrared
        self.brightnessAdjustment = brightnessAdjustment
        self.contrastAdjustment = contrastAdjustment
        self.scanArea = scanArea
        self.hardwareExposureTime = hardwareExposureTime
        self.outputRawTIFF = outputRawTIFF
        self.capabilityToken = capabilityToken
        self.outputPath = outputPath
    }
}

/// Protocol v2 result가 echo하는 적용 스캔 옵션. Host가 요청 wire와 필드별 exact match를
/// 검증하므로, 플러그인은 옵션을 임의 변환하지 않고 지원할 수 없는 요청을 명시적으로 실패시킨다.
public struct PluginAppliedScanOptions: Codable, Sendable, Equatable {
    public var deviceID: String
    public var resolutionDPI: Int
    public var bitDepth: Int
    public var colorMode: String
    public var filmType: String
    public var scanArea: ScanArea
    public var infrared: Bool
    public var multiExposure: Bool
    public var hardwareExposureTime: Int?
    public var brightnessAdjustment: Double?
    public var contrastAdjustment: Double?
    public var outputRawTIFF: Bool

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case resolutionDPI
        case bitDepth
        case colorMode
        case filmType
        case scanArea
        case infrared
        case multiExposure
        case hardwareExposureTime
        case brightnessAdjustment
        case contrastAdjustment
        case outputRawTIFF
    }

    public init(
        deviceID: String,
        resolutionDPI: Int,
        bitDepth: Int,
        colorMode: String,
        filmType: String,
        scanArea: ScanArea,
        infrared: Bool,
        multiExposure: Bool,
        hardwareExposureTime: Int? = nil,
        brightnessAdjustment: Double? = nil,
        contrastAdjustment: Double? = nil,
        outputRawTIFF: Bool
    ) {
        self.deviceID = deviceID
        self.resolutionDPI = resolutionDPI
        self.bitDepth = bitDepth
        self.colorMode = colorMode
        self.filmType = filmType
        self.scanArea = scanArea
        self.infrared = infrared
        self.multiExposure = multiExposure
        self.hardwareExposureTime = hardwareExposureTime
        self.brightnessAdjustment = brightnessAdjustment
        self.contrastAdjustment = contrastAdjustment
        self.outputRawTIFF = outputRawTIFF
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in [
            CodingKeys.hardwareExposureTime,
            .brightnessAdjustment,
            .contrastAdjustment
        ] where !container.contains(key) {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "protocol v2 appliedOptions는 optional key도 명시해야 합니다"
                )
            )
        }
        deviceID = try container.decode(String.self, forKey: .deviceID)
        resolutionDPI = try container.decode(Int.self, forKey: .resolutionDPI)
        bitDepth = try container.decode(Int.self, forKey: .bitDepth)
        colorMode = try container.decode(String.self, forKey: .colorMode)
        filmType = try container.decode(String.self, forKey: .filmType)
        scanArea = try container.decode(ScanArea.self, forKey: .scanArea)
        infrared = try container.decode(Bool.self, forKey: .infrared)
        multiExposure = try container.decode(Bool.self, forKey: .multiExposure)
        hardwareExposureTime = try container.decodeIfPresent(Int.self, forKey: .hardwareExposureTime)
        brightnessAdjustment = try container.decodeIfPresent(Double.self, forKey: .brightnessAdjustment)
        contrastAdjustment = try container.decodeIfPresent(Double.self, forKey: .contrastAdjustment)
        outputRawTIFF = try container.decode(Bool.self, forKey: .outputRawTIFF)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(resolutionDPI, forKey: .resolutionDPI)
        try container.encode(bitDepth, forKey: .bitDepth)
        try container.encode(colorMode, forKey: .colorMode)
        try container.encode(filmType, forKey: .filmType)
        try container.encode(scanArea, forKey: .scanArea)
        try container.encode(infrared, forKey: .infrared)
        try container.encode(multiExposure, forKey: .multiExposure)
        try container.encode(hardwareExposureTime, forKey: .hardwareExposureTime)
        try container.encode(brightnessAdjustment, forKey: .brightnessAdjustment)
        try container.encode(contrastAdjustment, forKey: .contrastAdjustment)
        try container.encode(outputRawTIFF, forKey: .outputRawTIFF)
    }
}

/// scan 서브커맨드가 stdout 으로 NDJSON(줄 단위) 스트리밍하는 이벤트.
public struct PluginScanEvent: Codable, Sendable, Equatable {
    public var type: String            // "progress" | "result" | "error"
    /// protocol v2 이벤트에서는 모두 필수다. v1 wire 호환을 위해 optional로 decode한다.
    public var protocolVersion: Int?
    public var requestID: UUID?
    public var sequence: UInt64?
    public var phase: String?
    public var fraction: Double?
    public var message: String?
    public var width: Int?
    public var height: Int?
    public var path: String?
    public var resolutionDPI: Int?
    public var bitDepth: Int?
    // IR(적외선) 채널 결과(옵션 — 구버전 플러그인은 보내지 않는다).
    public var irPath: String?         // 본 스캔과 같은 해상도/영역의 IR 채널 TIFF
    public var hasInfrared: Bool?
    public var warnings: [String]?
    /// protocol v2 result에서 필수. v1 wire 호환을 위해 optional로 decode한다.
    public var appliedOptions: PluginAppliedScanOptions?
}
