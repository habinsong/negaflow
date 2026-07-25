import Foundation

// MARK: - ScannerDescriptor (plan §7.2)

/// 감지된 스캐너 한 대의 정보 모델.
/// UI는 이 값만 보고, 구체 백엔드 이름을 사용자에게 드러내지 않는다.
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

public struct ScannerOptionRange: Codable, Sendable, Equatable {
    public var minimum: Double
    public var maximum: Double
    public var step: Double?

    public init(minimum: Double, maximum: Double, step: Double? = nil) {
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
    }

    public func clamped(_ value: Double) -> Double {
        min(max(value, minimum), maximum)
    }

    public func quantized(
        _ value: Double,
        upperBound: Double? = nil,
        rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero
    ) -> Double {
        let upper = max(minimum, min(maximum, upperBound ?? maximum))
        let clampedValue = min(max(value, minimum), upper)
        guard let step, step > 0 else { return clampedValue }
        let rounded = minimum + ((clampedValue - minimum) / step).rounded(rule) * step
        if rounded <= upper { return max(rounded, minimum) }
        return max(minimum, minimum + floor((upper - minimum) / step) * step)
    }
}

/// 장치가 실제로 지원하는 기능. 모델명이 아닌 Capability 기반으로 UI를 구성한다 (plan §5.3).
public struct ScannerCapabilities: Codable, Sendable, Equatable {
    public var supportedResolutions: [Resolution]
    public var supportedModes: [ColorMode]
    public var supportedBitDepths: [BitDepth]
    public var sourceModes: [String]?
    public var transparencyModes: [String]?
    public var supportsPreview: Bool
    public var supportsTransparency: Bool
    public var supportsInfrared: Bool
    public var supportsMultiExposure: Bool
    public var supportsScanArea: Bool
    public var supportsPositionedScanArea: Bool?
    public var supportsLampWarmupStatus: Bool
    public var brightnessRange: ScannerOptionRange?
    public var contrastRange: ScannerOptionRange?
    public var hardwareExposureRange: ScannerOptionRange?
    public var scanOriginXRange: ScannerOptionRange?
    public var scanOriginYRange: ScannerOptionRange?
    public var scanWidthRange: ScannerOptionRange?
    public var scanHeightRange: ScannerOptionRange?
    public var disabledReasons: [String: String]?
    public var maxScanArea: ScanArea
    public var minScanArea: ScanArea
    public var scanAreaUnit: ScanAreaUnit
    public var outputFormats: [String]
    public var estimatedScanSpeeds: [Int: Double]   // dpi -> seconds

    public init(
        supportedResolutions: [Resolution] = [],
        supportedModes: [ColorMode] = [],
        supportedBitDepths: [BitDepth] = [],
        sourceModes: [String] = [],
        transparencyModes: [String] = [],
        supportsPreview: Bool = false,
        supportsTransparency: Bool = false,
        supportsInfrared: Bool = false,
        supportsMultiExposure: Bool = false,
        supportsScanArea: Bool = false,
        supportsPositionedScanArea: Bool? = false,
        supportsLampWarmupStatus: Bool = false,
        brightnessRange: ScannerOptionRange? = nil,
        contrastRange: ScannerOptionRange? = nil,
        hardwareExposureRange: ScannerOptionRange? = nil,
        scanOriginXRange: ScannerOptionRange? = nil,
        scanOriginYRange: ScannerOptionRange? = nil,
        scanWidthRange: ScannerOptionRange? = nil,
        scanHeightRange: ScannerOptionRange? = nil,
        disabledReasons: [String: String] = [:],
        maxScanArea: ScanArea = ScanArea(widthMM: 0, heightMM: 0),
        minScanArea: ScanArea = ScanArea(widthMM: 0, heightMM: 0),
        scanAreaUnit: ScanAreaUnit = .millimeter,
        outputFormats: [String] = [],
        estimatedScanSpeeds: [Int: Double] = [:]
    ) {
        self.supportedResolutions = supportedResolutions
        self.supportedModes = supportedModes
        self.supportedBitDepths = supportedBitDepths
        self.sourceModes = sourceModes
        self.transparencyModes = transparencyModes
        self.supportsPreview = supportsPreview
        self.supportsTransparency = supportsTransparency
        self.supportsInfrared = supportsInfrared
        self.supportsMultiExposure = supportsMultiExposure
        self.supportsScanArea = supportsScanArea
        self.supportsPositionedScanArea = supportsPositionedScanArea
        self.supportsLampWarmupStatus = supportsLampWarmupStatus
        self.brightnessRange = brightnessRange
        self.contrastRange = contrastRange
        self.hardwareExposureRange = hardwareExposureRange
        self.scanOriginXRange = scanOriginXRange
        self.scanOriginYRange = scanOriginYRange
        self.scanWidthRange = scanWidthRange
        self.scanHeightRange = scanHeightRange
        self.disabledReasons = disabledReasons
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
    public func disabledReason(for capability: String) -> String? { disabledReasons?[capability] }
}

public struct PhysicalScanAreaBounds: Sendable, Equatable {
    public var minimum: ScanArea
    public var maximum: ScanArea
    public var displayUnit: ScanAreaUnit

    public init(minimum: ScanArea, maximum: ScanArea, displayUnit: ScanAreaUnit) {
        self.minimum = minimum
        self.maximum = maximum
        self.displayUnit = displayUnit
    }
}

public extension ScannerCapabilities {
    /// `ScanArea` 값은 항상 mm로 정규화한다. pixel 단위 capability나 불완전한 범위는 물리 영역으로
    /// 해석하지 않아 UI와 요청에서 fail-closed 한다.
    var physicalScanAreaBounds: PhysicalScanAreaBounds? {
        let values = [
            minScanArea.originXMM, minScanArea.originYMM,
            minScanArea.widthMM, minScanArea.heightMM,
            maxScanArea.originXMM, maxScanArea.originYMM,
            maxScanArea.widthMM, maxScanArea.heightMM,
        ]
        guard supportsScanArea,
              scanAreaUnit != .pixel,
              values.allSatisfy(\.isFinite),
              minScanArea.originXMM >= 0,
              minScanArea.originYMM >= 0,
              maxScanArea.originXMM >= 0,
              maxScanArea.originYMM >= 0,
              minScanArea.widthMM > 0,
              minScanArea.heightMM > 0,
              maxScanArea.widthMM >= minScanArea.widthMM,
              maxScanArea.heightMM >= minScanArea.heightMM else {
            return nil
        }
        return PhysicalScanAreaBounds(
            minimum: minScanArea,
            maximum: maxScanArea,
            displayUnit: scanAreaUnit
        )
    }

    func clampedPhysicalScanArea(_ requested: ScanArea) -> ScanArea? {
        guard let bounds = physicalScanAreaBounds,
              requested.originXMM.isFinite,
              requested.originYMM.isFinite,
              requested.widthMM.isFinite,
              requested.heightMM.isFinite else {
            return nil
        }
        let rawWidth = min(max(requested.widthMM, bounds.minimum.widthMM), bounds.maximum.widthMM)
        let rawHeight = min(max(requested.heightMM, bounds.minimum.heightMM), bounds.maximum.heightMM)
        let rawOriginX = min(
            max(requested.originXMM, bounds.maximum.originXMM),
            bounds.maximum.originXMM + bounds.maximum.widthMM - rawWidth
        )
        let rawOriginY = min(
            max(requested.originYMM, bounds.maximum.originYMM),
            bounds.maximum.originYMM + bounds.maximum.heightMM - rawHeight
        )
        let originXMM = scanOriginXRange?.quantized(rawOriginX, rule: .down) ?? rawOriginX
        let originYMM = scanOriginYRange?.quantized(rawOriginY, rule: .down) ?? rawOriginY
        let requiredWidth = rawOriginX + rawWidth - originXMM
        let requiredHeight = rawOriginY + rawHeight - originYMM
        let widthMM = scanWidthRange?.quantized(
            requiredWidth,
            upperBound: bounds.maximum.originXMM + bounds.maximum.widthMM - originXMM,
            rule: .up
        )
            ?? min(max(requested.widthMM, bounds.minimum.widthMM), bounds.maximum.widthMM)
        let heightMM = scanHeightRange?.quantized(
            requiredHeight,
            upperBound: bounds.maximum.originYMM + bounds.maximum.heightMM - originYMM,
            rule: .up
        )
            ?? min(max(requested.heightMM, bounds.minimum.heightMM), bounds.maximum.heightMM)
        return ScanArea(
            originXMM: originXMM,
            originYMM: originYMM,
            widthMM: widthMM,
            heightMM: heightMM
        )
    }
}

public extension ScanAreaUnit {
    var symbol: String {
        switch self {
        case .millimeter: return "mm"
        case .inch: return "in"
        case .pixel: return "px"
        }
    }

    func displayValue(fromMillimeters value: Double) -> Double? {
        guard value.isFinite else { return nil }
        switch self {
        case .millimeter: return value
        case .inch: return value / 25.4
        case .pixel: return nil
        }
    }

    func millimeters(fromDisplayValue value: Double) -> Double? {
        guard value.isFinite else { return nil }
        switch self {
        case .millimeter: return value
        case .inch: return value * 25.4
        case .pixel: return nil
        }
    }
}
