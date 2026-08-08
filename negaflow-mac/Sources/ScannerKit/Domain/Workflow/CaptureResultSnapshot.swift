import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

public struct CaptureResultSnapshot: Codable, Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let resolution: Resolution
    public let bitDepth: BitDepth
    public let reportedResolution: Resolution?
    public let reportedBitDepth: BitDepth?
    public let colorSpace: String
    public let hasInfraredChannel: Bool
    public let reportedDuration: Double
    public let backendUsed: BackendType
    public let warnings: [String]

    public init(_ result: ScanResult) {
        self.width = result.width
        self.height = result.height
        self.resolution = result.resolution
        self.bitDepth = result.bitDepth
        self.reportedResolution = result.reportedResolution
        self.reportedBitDepth = result.reportedBitDepth
        self.colorSpace = result.colorSpace
        self.hasInfraredChannel = result.hasInfraredChannel
        self.reportedDuration = result.scanDuration
        self.backendUsed = result.backendUsed
        self.warnings = result.warnings
    }

    /// resolution/bitDepth가 백엔드가 명시적으로 보고한 값인 경우의 편의 initializer.
    /// Legacy fallback은 아래 optional reported initializer를 사용한다.
    public init(
        width: Int,
        height: Int,
        resolution: Resolution,
        bitDepth: BitDepth,
        colorSpace: String,
        hasInfraredChannel: Bool,
        reportedDuration: Double,
        backendUsed: BackendType,
        warnings: [String] = []
    ) {
        self.width = width
        self.height = height
        self.resolution = resolution
        self.bitDepth = bitDepth
        self.reportedResolution = resolution
        self.reportedBitDepth = bitDepth
        self.colorSpace = colorSpace
        self.hasInfraredChannel = hasInfraredChannel
        self.reportedDuration = reportedDuration
        self.backendUsed = backendUsed
        self.warnings = warnings
    }

    public init(
        width: Int,
        height: Int,
        resolution: Resolution,
        bitDepth: BitDepth,
        reportedResolution: Resolution?,
        reportedBitDepth: BitDepth?,
        colorSpace: String,
        hasInfraredChannel: Bool,
        reportedDuration: Double,
        backendUsed: BackendType,
        warnings: [String] = []
    ) {
        self.width = width
        self.height = height
        self.resolution = resolution
        self.bitDepth = bitDepth
        self.reportedResolution = reportedResolution
        self.reportedBitDepth = reportedBitDepth
        self.colorSpace = colorSpace
        self.hasInfraredChannel = hasInfraredChannel
        self.reportedDuration = reportedDuration
        self.backendUsed = backendUsed
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case width
        case height
        case resolution
        case bitDepth
        case reportedResolution
        case reportedBitDepth
        case colorSpace
        case hasInfraredChannel
        case reportedDuration
        case backendUsed
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.reportedResolution, .reportedBitDepth]
            where !container.contains(key) {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "CaptureResultSnapshot reported provenance key가 누락되었습니다"
                )
            )
        }
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        resolution = try container.decode(Resolution.self, forKey: .resolution)
        bitDepth = try container.decode(BitDepth.self, forKey: .bitDepth)
        reportedResolution = try container.decodeIfPresent(Resolution.self, forKey: .reportedResolution)
        reportedBitDepth = try container.decodeIfPresent(BitDepth.self, forKey: .reportedBitDepth)
        colorSpace = try container.decode(String.self, forKey: .colorSpace)
        hasInfraredChannel = try container.decode(Bool.self, forKey: .hasInfraredChannel)
        reportedDuration = try container.decode(Double.self, forKey: .reportedDuration)
        backendUsed = try container.decode(BackendType.self, forKey: .backendUsed)
        warnings = try container.decode([String].self, forKey: .warnings)
        try decodeValidated(self, decoder: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(bitDepth, forKey: .bitDepth)
        try container.encode(reportedResolution, forKey: .reportedResolution)
        try container.encode(reportedBitDepth, forKey: .reportedBitDepth)
        try container.encode(colorSpace, forKey: .colorSpace)
        try container.encode(hasInfraredChannel, forKey: .hasInfraredChannel)
        try container.encode(reportedDuration, forKey: .reportedDuration)
        try container.encode(backendUsed, forKey: .backendUsed)
        try container.encode(warnings, forKey: .warnings)
    }

    func validate() throws {
        guard width > 0, height > 0 else {
            throw ScanWorkflowValidationError.invalidValue("캡처 결과 크기는 1x1 이상이어야 합니다")
        }
        guard resolution.dpi >= 0 else {
            throw ScanWorkflowValidationError.invalidValue("캡처 결과 해상도는 음수일 수 없습니다")
        }
        if let reportedResolution {
            guard reportedResolution.dpi >= 0, reportedResolution == resolution else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "captureResult reportedResolution이 operational resolution과 다릅니다"
                )
            }
        }
        if let reportedBitDepth, reportedBitDepth != bitDepth {
            throw ScanWorkflowValidationError.invariantViolation(
                "captureResult reportedBitDepth가 operational bitDepth와 다릅니다"
            )
        }
        try requireNonempty(colorSpace, field: "captureResult.colorSpace")
        guard reportedDuration.isFinite, reportedDuration >= 0 else {
            throw ScanWorkflowValidationError.invalidValue(
                "captureResult.reportedDuration은 0 이상의 유한값이어야 합니다"
            )
        }
    }
}
