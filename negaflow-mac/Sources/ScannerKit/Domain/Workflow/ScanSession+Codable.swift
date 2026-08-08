import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

extension ScanSession {
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case createdAt
        case closedAt
        case device
        case backend
        case environment
        case jobs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try requireSupportedSchema(
            schemaVersion,
            current: Self.currentSchemaVersion,
            record: "ScanSession",
            key: .schemaVersion,
            container: container
        )
        self.schemaVersion = schemaVersion
        self.id = try container.decode(UUID.self, forKey: .id)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.closedAt = try container.decodeIfPresent(Date.self, forKey: .closedAt)
        self.device = try container.decode(ScannerDescriptor.self, forKey: .device)
        self.backend = try container.decode(ScanBackendSnapshot.self, forKey: .backend)
        self.environment = try container.decode(ScanEnvironmentSnapshot.self, forKey: .environment)
        self.jobs = try container.decode([ScanJob].self, forKey: .jobs)
        try decodeValidated(self, decoder: decoder)
    }
}
