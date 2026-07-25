import Foundation
import ScannerKit

extension CLI {
    static let jsonCommands: Set<String> = ["detect", "capabilities"]

    func writeJSON<Payload: Codable & Sendable>(_ payload: Payload, command: String) throws {
        try Self.writeJSONDocument(ScannerCLIEnvelope(command: command, payload: payload))
    }

    func writeJSONError(code: String, message: String, command: String) {
        let envelope = ScannerCLIEnvelope<ScannerCLIEmptyPayload>(
            command: command,
            error: ScannerCLIErrorPayload(code: code, message: message)
        )
        try? Self.writeJSONDocument(envelope)
    }

    private static func writeJSONDocument<Value: Encodable>(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
