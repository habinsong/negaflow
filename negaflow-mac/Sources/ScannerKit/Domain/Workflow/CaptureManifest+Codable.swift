import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

extension CaptureManifest {
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case sessionID
        case jobID
        case attempt
        case kind
        case requestedOptions
        case appliedOptionsEvidence
        case result
        case captureStartedAt
        case captureCompletedAt
        case rgbFile
        case infraredFile
        case rgbObservation
        case infraredObservation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try requireSupportedSchema(
            schemaVersion,
            current: Self.currentSchemaVersion,
            record: "CaptureManifest",
            key: .schemaVersion,
            container: container
        )
        self.schemaVersion = schemaVersion
        self.id = try container.decode(UUID.self, forKey: .id)
        self.sessionID = try container.decode(UUID.self, forKey: .sessionID)
        self.jobID = try container.decode(UUID.self, forKey: .jobID)
        self.attempt = try container.decode(Int.self, forKey: .attempt)
        self.kind = try container.decode(ScanJobKind.self, forKey: .kind)
        self.requestedOptions = try container.decode(ScanOptions.self, forKey: .requestedOptions)
        self.appliedOptionsEvidence = try container.decode(
            AppliedScanOptionsEvidence.self,
            forKey: .appliedOptionsEvidence
        )
        self.result = try container.decode(CaptureResultSnapshot.self, forKey: .result)
        self.captureStartedAt = try container.decode(Date.self, forKey: .captureStartedAt)
        self.captureCompletedAt = try container.decode(Date.self, forKey: .captureCompletedAt)
        self.rgbFile = try container.decode(CaptureFileIdentity.self, forKey: .rgbFile)
        self.infraredFile = try container.decodeIfPresent(CaptureFileIdentity.self, forKey: .infraredFile)
        self.rgbObservation = try container.decode(
            CaptureFileObservation.self,
            forKey: .rgbObservation
        )
        self.infraredObservation = try container.decodeIfPresent(
            CaptureFileObservation.self,
            forKey: .infraredObservation
        )
        try decodeValidated(self, decoder: decoder)
    }
}
