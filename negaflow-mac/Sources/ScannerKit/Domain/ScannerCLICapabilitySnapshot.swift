import Foundation

public struct ScannerCLISpeedEstimate: Codable, Sendable, Equatable {
    public let dpi: Int
    public let seconds: Double

    public init(dpi: Int, seconds: Double) {
        self.dpi = dpi
        self.seconds = seconds
    }
}

/// CLI와 앱이 같은 raw capability payload를 소비하는지 검증하기 위한 versioned wire snapshot.
/// Dictionary의 JSON key 표현에 의존하지 않도록 speed는 정렬된 entry 배열로 고정한다.
public struct ScannerCLICapabilitySnapshot: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case resolutionsDPI, modes, bitDepths, sourceModes, transparencyModes
        case supportsPreview, supportsTransparency, supportsInfrared
        case supportsMultiExposure, supportsScanArea, supportsPositionedScanArea, supportsLampWarmupStatus
        case brightnessRange, contrastRange, hardwareExposureRange
        case scanOriginXRange, scanOriginYRange, scanWidthRange, scanHeightRange
        case disabledReasons
        case maxScanArea, minScanArea, scanAreaUnit, outputFormats, estimatedScanSpeeds
    }

    public let resolutionsDPI: [Int]
    public let modes: [String]
    public let bitDepths: [Int]
    public let sourceModes: [String]?
    public let transparencyModes: [String]?
    public let supportsPreview: Bool
    public let supportsTransparency: Bool
    public let supportsInfrared: Bool
    public let supportsMultiExposure: Bool
    public let supportsScanArea: Bool
    public let supportsPositionedScanArea: Bool
    public let supportsLampWarmupStatus: Bool
    public let brightnessRange: ScannerOptionRange?
    public let contrastRange: ScannerOptionRange?
    public let hardwareExposureRange: ScannerOptionRange?
    public let scanOriginXRange: ScannerOptionRange?
    public let scanOriginYRange: ScannerOptionRange?
    public let scanWidthRange: ScannerOptionRange?
    public let scanHeightRange: ScannerOptionRange?
    public let disabledReasons: [String: String]?
    public let maxScanArea: ScanArea
    public let minScanArea: ScanArea
    public let scanAreaUnit: String
    public let outputFormats: [String]
    public let estimatedScanSpeeds: [ScannerCLISpeedEstimate]

    public init(_ capabilities: ScannerCapabilities) {
        resolutionsDPI = capabilities.supportedResolutions.map(\.dpi)
        modes = capabilities.supportedModes.map(\.rawValue)
        bitDepths = capabilities.supportedBitDepths.map(\.rawValue)
        sourceModes = capabilities.sourceModes
        transparencyModes = capabilities.transparencyModes
        supportsPreview = capabilities.supportsPreview
        supportsTransparency = capabilities.supportsTransparency
        supportsInfrared = capabilities.supportsInfrared
        supportsMultiExposure = capabilities.supportsMultiExposure
        supportsScanArea = capabilities.supportsScanArea
        supportsPositionedScanArea = capabilities.supportsPositionedScanArea == true
        supportsLampWarmupStatus = capabilities.supportsLampWarmupStatus
        brightnessRange = capabilities.brightnessRange
        contrastRange = capabilities.contrastRange
        hardwareExposureRange = capabilities.hardwareExposureRange
        scanOriginXRange = capabilities.scanOriginXRange
        scanOriginYRange = capabilities.scanOriginYRange
        scanWidthRange = capabilities.scanWidthRange
        scanHeightRange = capabilities.scanHeightRange
        disabledReasons = capabilities.disabledReasons
        maxScanArea = capabilities.maxScanArea
        minScanArea = capabilities.minScanArea
        scanAreaUnit = capabilities.scanAreaUnit.rawValue
        outputFormats = capabilities.outputFormats
        estimatedScanSpeeds = capabilities.estimatedScanSpeeds
            .map { ScannerCLISpeedEstimate(dpi: $0.key, seconds: $0.value) }
            .sorted { $0.dpi < $1.dpi }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resolutionsDPI, forKey: .resolutionsDPI)
        try container.encode(modes, forKey: .modes)
        try container.encode(bitDepths, forKey: .bitDepths)
        try Self.encode(sourceModes, forKey: .sourceModes, into: &container)
        try Self.encode(transparencyModes, forKey: .transparencyModes, into: &container)
        try container.encode(supportsPreview, forKey: .supportsPreview)
        try container.encode(supportsTransparency, forKey: .supportsTransparency)
        try container.encode(supportsInfrared, forKey: .supportsInfrared)
        try container.encode(supportsMultiExposure, forKey: .supportsMultiExposure)
        try container.encode(supportsScanArea, forKey: .supportsScanArea)
        try container.encode(supportsPositionedScanArea, forKey: .supportsPositionedScanArea)
        try container.encode(supportsLampWarmupStatus, forKey: .supportsLampWarmupStatus)
        try Self.encode(brightnessRange, forKey: .brightnessRange, into: &container)
        try Self.encode(contrastRange, forKey: .contrastRange, into: &container)
        try Self.encode(hardwareExposureRange, forKey: .hardwareExposureRange, into: &container)
        try Self.encode(scanOriginXRange, forKey: .scanOriginXRange, into: &container)
        try Self.encode(scanOriginYRange, forKey: .scanOriginYRange, into: &container)
        try Self.encode(scanWidthRange, forKey: .scanWidthRange, into: &container)
        try Self.encode(scanHeightRange, forKey: .scanHeightRange, into: &container)
        try Self.encode(disabledReasons, forKey: .disabledReasons, into: &container)
        try container.encode(maxScanArea, forKey: .maxScanArea)
        try container.encode(minScanArea, forKey: .minScanArea)
        try container.encode(scanAreaUnit, forKey: .scanAreaUnit)
        try container.encode(outputFormats, forKey: .outputFormats)
        try container.encode(estimatedScanSpeeds, forKey: .estimatedScanSpeeds)
    }

    private static func encode<Value: Encodable>(
        _ value: Value?,
        forKey key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }
}
