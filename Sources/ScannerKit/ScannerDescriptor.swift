import Foundation

// MARK: - ScannerDescriptor (plan §7.2)

/// 감지된 스캐너 한 대의 정보 모델.
/// UI는 이 값만 보고, ImageCaptureCore/SANE 같은 백엔드 이름을 사용자에게 드러내지 않는다.
public struct ScannerDescriptor: Codable, Sendable, Equatable, Identifiable {
    /// 백엔드 내부 식별자. 예: "plustek-8200i-usb-001"
    public let id: String
    public var displayName: String
    public var vendor: String
    public var model: String
    public var backendType: BackendType
    public var connectionType: ConnectionType
    public var usbVendorID: String?
    public var usbProductID: String?
    public var serialNumber: String?
    public var verifiedStatus: VerifiedStatus
    public var firmwareVersion: String?
    public var driverVersion: String?

    public init(
        id: String,
        displayName: String,
        vendor: String,
        model: String,
        backendType: BackendType,
        connectionType: ConnectionType = .usb,
        usbVendorID: String? = nil,
        usbProductID: String? = nil,
        serialNumber: String? = nil,
        verifiedStatus: VerifiedStatus = .compatibleTarget,
        firmwareVersion: String? = nil,
        driverVersion: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.vendor = vendor
        self.model = model
        self.backendType = backendType
        self.connectionType = connectionType
        self.usbVendorID = usbVendorID
        self.usbProductID = usbProductID
        self.serialNumber = serialNumber
        self.verifiedStatus = verifiedStatus
        self.firmwareVersion = firmwareVersion
        self.driverVersion = driverVersion
    }

    /// plan §5.3 — 모델명 하드코딩 금지. 이 값은 표시용 메타데이터일 뿐이다.
    public var verifiedBadge: String {
        switch verifiedStatus {
        case .verified:         return "Verified"
        case .compatibleTarget: return "Compatible"
        case .experimental:     return "Experimental"
        }
    }
}

// MARK: - ScannerCapabilities (plan §7.3)

/// 장치가 실제로 지원하는 기능. 모델명이 아닌 Capability 기반으로 UI를 구성한다 (plan §5.3).
public struct ScannerCapabilities: Codable, Sendable, Equatable {
    public var supportedResolutions: [Resolution]
    public var supportedModes: [ColorMode]
    public var supportedBitDepths: [BitDepth]
    public var supportsPreview: Bool
    public var supportsTransparency: Bool
    public var supportsInfrared: Bool
    public var supportsMultiExposure: Bool
    public var supportsScanArea: Bool
    public var supportsLampWarmupStatus: Bool
    public var maxScanArea: ScanArea
    public var minScanArea: ScanArea
    public var scanAreaUnit: ScanAreaUnit
    public var outputFormats: [String]
    public var estimatedScanSpeeds: [Int: Double]   // dpi -> seconds

    public init(
        supportedResolutions: [Resolution] = [.r900, .r1800, .r3600, .r7200],
        supportedModes: [ColorMode] = [.color, .gray, .infrared],
        supportedBitDepths: [BitDepth] = [.eight, .sixteen],
        supportsPreview: Bool = true,
        supportsTransparency: Bool = true,
        supportsInfrared: Bool = true,
        supportsMultiExposure: Bool = false,
        supportsScanArea: Bool = true,
        supportsLampWarmupStatus: Bool = true,
        maxScanArea: ScanArea = .fullFrame35mm,
        minScanArea: ScanArea = ScanArea(widthMM: 4, heightMM: 4),
        scanAreaUnit: ScanAreaUnit = .millimeter,
        outputFormats: [String] = ["tiff", "jpeg"],
        estimatedScanSpeeds: [Int: Double] = [900: 4, 1800: 9, 3600: 28, 7200: 95]
    ) {
        self.supportedResolutions = supportedResolutions
        self.supportedModes = supportedModes
        self.supportedBitDepths = supportedBitDepths
        self.supportsPreview = supportsPreview
        self.supportsTransparency = supportsTransparency
        self.supportsInfrared = supportsInfrared
        self.supportsMultiExposure = supportsMultiExposure
        self.supportsScanArea = supportsScanArea
        self.supportsLampWarmupStatus = supportsLampWarmupStatus
        self.maxScanArea = maxScanArea
        self.minScanArea = minScanArea
        self.scanAreaUnit = scanAreaUnit
        self.outputFormats = outputFormats
        self.estimatedScanSpeeds = estimatedScanSpeeds
    }

    /// Capability 기반 게이트. 예: "8200i면 IR 켠다"가 아니라 "IR 모드가 있으면 IR UI를 켠다".
    public func supports(resolution r: Resolution) -> Bool { supportedResolutions.contains(r) }
    public func supports(depth d: BitDepth) -> Bool { supportedBitDepths.contains(d) }
    public func supports(mode m: ColorMode) -> Bool { supportedModes.contains(m) }
}
