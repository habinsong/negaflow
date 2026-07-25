import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

public struct ScanFramePublicationSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let frameID: UUID
    public let scanIndex: Int
    public let initialTransform: ImageTransform
    public let developTarget: DevelopTarget
    public let scannerProfileID: String?
    public let presetID: String?
    public let storageGroupName: String
    public let regionDefectDisplayROI: CGRect?
    public let regionDefectSensitivity: Double?

    public init(
        frameID: UUID = UUID(),
        scanIndex: Int,
        initialTransform: ImageTransform,
        developTarget: DevelopTarget,
        scannerProfileID: String? = nil,
        presetID: String? = "neutral",
        storageGroupName: String,
        regionDefectDisplayROI: CGRect? = nil,
        regionDefectSensitivity: Double? = nil
    ) throws {
        self.schemaVersion = Self.currentSchemaVersion
        self.frameID = frameID
        self.scanIndex = scanIndex
        self.initialTransform = initialTransform
        self.developTarget = developTarget
        self.scannerProfileID = scannerProfileID
        self.presetID = presetID
        self.storageGroupName = storageGroupName
        self.regionDefectDisplayROI = regionDefectDisplayROI
        self.regionDefectSensitivity = regionDefectSensitivity
        try validate()
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ScanWorkflowValidationError.invariantViolation(
                "지원하지 않는 ScanFramePublicationSnapshot schemaVersion: \(schemaVersion)"
            )
        }
        guard scanIndex > 0 else {
            throw ScanWorkflowValidationError.invalidValue(
                "framePublication.scanIndex는 1 이상이어야 합니다"
            )
        }
        guard initialTransform.straightenAngle.isFinite,
              initialTransform.cropAspect?.isFinite ?? true,
              initialTransform.cropRect.map({ crop in
                  crop.x.isFinite && crop.y.isFinite && crop.z.isFinite && crop.w.isFinite
              }) ?? true else {
            throw ScanWorkflowValidationError.invalidValue(
                "framePublication.initialTransform에 유효하지 않은 값이 있습니다"
            )
        }
        try requireOptionalNonempty(
            scannerProfileID,
            field: "framePublication.scannerProfileID"
        )
        try requireOptionalNonempty(presetID, field: "framePublication.presetID")
        try requireNonempty(storageGroupName, field: "framePublication.storageGroupName")
        guard (regionDefectDisplayROI == nil) == (regionDefectSensitivity == nil) else {
            throw ScanWorkflowValidationError.invariantViolation(
                "framePublication 영역 결함 제거 ROI와 민감도는 함께 존재해야 합니다"
            )
        }
        if let roi = regionDefectDisplayROI, let sensitivity = regionDefectSensitivity {
            guard roi.origin.x.isFinite,
                  roi.origin.y.isFinite,
                  roi.size.width.isFinite,
                  roi.size.height.isFinite,
                  roi.size.width > 0,
                  roi.size.height > 0,
                  sensitivity.isFinite,
                  sensitivity > 0 else {
                throw ScanWorkflowValidationError.invalidValue(
                    "framePublication 영역 결함 제거 값이 유효하지 않습니다"
                )
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case frameID
        case scanIndex
        case initialTransform
        case developTarget
        case scannerProfileID
        case presetID
        case storageGroupName
        case regionDefectDisplayROI
        case regionDefectSensitivity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try requireSupportedSchema(
            schemaVersion,
            current: Self.currentSchemaVersion,
            record: "ScanFramePublicationSnapshot",
            key: .schemaVersion,
            container: container
        )
        for key in [
            CodingKeys.scannerProfileID,
            .presetID,
            .regionDefectDisplayROI,
            .regionDefectSensitivity,
        ] where !container.contains(key) {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "frame publication optional key가 누락되었습니다"
                )
            )
        }
        self.schemaVersion = schemaVersion
        self.frameID = try container.decode(UUID.self, forKey: .frameID)
        self.scanIndex = try container.decode(Int.self, forKey: .scanIndex)
        self.initialTransform = try container.decode(ImageTransform.self, forKey: .initialTransform)
        self.developTarget = try container.decode(DevelopTarget.self, forKey: .developTarget)
        self.scannerProfileID = try container.decodeIfPresent(String.self, forKey: .scannerProfileID)
        self.presetID = try container.decodeIfPresent(String.self, forKey: .presetID)
        self.storageGroupName = try container.decode(String.self, forKey: .storageGroupName)
        self.regionDefectDisplayROI = try container.decodeIfPresent(
            CGRect.self,
            forKey: .regionDefectDisplayROI
        )
        self.regionDefectSensitivity = try container.decodeIfPresent(
            Double.self,
            forKey: .regionDefectSensitivity
        )
        try decodeValidated(self, decoder: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(frameID, forKey: .frameID)
        try container.encode(scanIndex, forKey: .scanIndex)
        try container.encode(initialTransform, forKey: .initialTransform)
        try container.encode(developTarget, forKey: .developTarget)
        try container.encode(scannerProfileID, forKey: .scannerProfileID)
        try container.encode(presetID, forKey: .presetID)
        try container.encode(storageGroupName, forKey: .storageGroupName)
        try container.encode(regionDefectDisplayROI, forKey: .regionDefectDisplayROI)
        try container.encode(regionDefectSensitivity, forKey: .regionDefectSensitivity)
    }
}

/// ScannerError를 문자열 로그가 아닌 안정된 코드와 메시지로 보존한다.
