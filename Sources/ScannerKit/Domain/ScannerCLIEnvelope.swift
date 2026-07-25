import Foundation

public struct ScannerCLIEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case schema, schemaVersion, command, status, payload, error
    }

    public static var schemaName: String { "negaflow.scanner-cli" }
    public static var currentVersion: Int { 1 }

    public let schema: String
    public let schemaVersion: Int
    public let command: String
    public let status: String
    public let payload: Payload?
    public let error: ScannerCLIErrorPayload?

    public init(command: String, payload: Payload) {
        schema = Self.schemaName
        schemaVersion = Self.currentVersion
        self.command = command
        status = "ok"
        self.payload = payload
        error = nil
    }

    public init(command: String, error: ScannerCLIErrorPayload) {
        schema = Self.schemaName
        schemaVersion = Self.currentVersion
        self.command = command
        status = "error"
        payload = nil
        self.error = error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(command, forKey: .command)
        try container.encode(status, forKey: .status)
        if let payload {
            try container.encode(payload, forKey: .payload)
        } else {
            try container.encodeNil(forKey: .payload)
        }
        if let error {
            try container.encode(error, forKey: .error)
        } else {
            try container.encodeNil(forKey: .error)
        }
    }
}
