import Foundation

// MARK: - Scanner plugin manifest & wire protocol
//
// negaflow(Apache-2.0)는 스캐너 백엔드를 내장하지 않는다. 스캐너 인식/제어는 설치형
// 외부 프로세스 플러그인이 담당하며, negaflow는 아래 JSON/CLI 계약으로만 통신한다.
// (별도 프로세스·파이프·CLI = 단순 취합이므로 GPL 플러그인과 라이센스가 결합되지 않는다.)
//
// 플러그인 설치 위치:
//   ~/Library/Application Support/negaflow/Plugins/<id>/manifest.json
//   실행파일은 manifest 의 `executable`(상대경로면 manifest 디렉토리 기준) 로 해석한다.

/// 플러그인 디렉토리의 manifest.json 스키마.
public struct ScannerPluginManifest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var executable: String
    public var kind: String?          // "scanner"
    public var license: String?
    public var homepage: String?
    public var pluginVersion: String?

    public init(schemaVersion: Int, id: String, name: String, executable: String,
                kind: String? = "scanner", license: String? = nil,
                homepage: String? = nil, pluginVersion: String? = nil) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.executable = executable
        self.kind = kind
        self.license = license
        self.homepage = homepage
        self.pluginVersion = pluginVersion
    }
}

/// 발견되어 실행 가능하게 해석된 설치 플러그인.
public struct InstalledScannerPlugin: Sendable, Equatable, Identifiable {
    public let manifest: ScannerPluginManifest
    public let manifestURL: URL
    public let executableURL: URL

    public var id: String { manifest.id }
    public var name: String { manifest.name }

    public init(manifest: ScannerPluginManifest, manifestURL: URL, executableURL: URL) {
        self.manifest = manifest
        self.manifestURL = manifestURL
        self.executableURL = executableURL
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

public struct PluginCapabilities: Codable, Sendable, Equatable {
    public var resolutionsDPI: [Int]
    public var modes: [String]
    public var bitDepths: [Int]
    public var supportsPreview: Bool?
    public var supportsTransparency: Bool?
    public var supportsInfrared: Bool?
    public var supportsMultiExposure: Bool?
    public var supportsScanArea: Bool?
    public var maxScanAreaWidthMM: Double?
    public var maxScanAreaHeightMM: Double?
    public var outputFormats: [String]?
}

public struct PluginScanOptions: Codable, Sendable, Equatable {
    public var deviceID: String
    public var resolutionDPI: Int      // 0 = preview
    public var bitDepth: Int
    public var colorMode: String
    public var filmType: String
    public var preview: Bool
    public var multiExposure: Bool
    public var infrared: Bool          // IR 지원 기기에서 적외선 채널/모드로 스캔
    public var outputPath: String

    public init(deviceID: String, resolutionDPI: Int, bitDepth: Int, colorMode: String,
                filmType: String, preview: Bool, multiExposure: Bool, infrared: Bool = false,
                outputPath: String) {
        self.deviceID = deviceID
        self.resolutionDPI = resolutionDPI
        self.bitDepth = bitDepth
        self.colorMode = colorMode
        self.filmType = filmType
        self.preview = preview
        self.multiExposure = multiExposure
        self.infrared = infrared
        self.outputPath = outputPath
    }
}

/// scan 서브커맨드가 stdout 으로 NDJSON(줄 단위) 스트리밍하는 이벤트.
public struct PluginScanEvent: Codable, Sendable, Equatable {
    public var type: String            // "progress" | "result" | "error"
    public var phase: String?
    public var fraction: Double?
    public var message: String?
    public var width: Int?
    public var height: Int?
    public var path: String?
    public var resolutionDPI: Int?
    public var bitDepth: Int?
}
