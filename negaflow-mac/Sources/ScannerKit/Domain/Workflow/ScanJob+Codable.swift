import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

extension ScanJob {
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case sessionID
        case ordinal
        case attempt
        case kind
        case state
        case requestedOptions
        case framePublication
        case createdAt
        case updatedAt
        case startedAt
        case finishedAt
        case pendingCapture
        case captureManifest
        case failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try requireSupportedSchema(
            schemaVersion,
            current: Self.currentSchemaVersion,
            record: "ScanJob",
            key: .schemaVersion,
            container: container
        )
        self.schemaVersion = schemaVersion
        self.id = try container.decode(UUID.self, forKey: .id)
        self.sessionID = try container.decode(UUID.self, forKey: .sessionID)
        self.ordinal = try container.decode(Int.self, forKey: .ordinal)
        self.attempt = try container.decode(Int.self, forKey: .attempt)
        self.kind = try container.decode(ScanJobKind.self, forKey: .kind)
        self.state = try container.decode(ScanJobState.self, forKey: .state)
        self.requestedOptions = try container.decode(ScanOptions.self, forKey: .requestedOptions)
        guard container.contains(.framePublication) else {
            throw DecodingError.keyNotFound(
                CodingKeys.framePublication,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "ScanJob framePublication key가 누락되었습니다"
                )
            )
        }
        self.framePublication = try container.decodeIfPresent(
            ScanFramePublicationSnapshot.self,
            forKey: .framePublication
        )
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        self.finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        self.pendingCapture = try container.decodeIfPresent(PendingCaptureSnapshot.self, forKey: .pendingCapture)
        self.captureManifest = try container.decodeIfPresent(CaptureManifest.self, forKey: .captureManifest)
        self.failure = try container.decodeIfPresent(ScannerErrorSnapshot.self, forKey: .failure)
        try decodeValidated(self, decoder: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(ordinal, forKey: .ordinal)
        try container.encode(attempt, forKey: .attempt)
        try container.encode(kind, forKey: .kind)
        try container.encode(state, forKey: .state)
        try container.encode(requestedOptions, forKey: .requestedOptions)
        try container.encode(framePublication, forKey: .framePublication)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(finishedAt, forKey: .finishedAt)
        try container.encodeIfPresent(pendingCapture, forKey: .pendingCapture)
        try container.encodeIfPresent(captureManifest, forKey: .captureManifest)
        try container.encodeIfPresent(failure, forKey: .failure)
    }
}
