import Foundation

public struct ScannerCLIDetectedBackend: Codable, Sendable, Equatable {
    public let backend: String
    public let devices: [ScannerDescriptor]

    public init(backend: BackendType, devices: [ScannerDescriptor]) {
        self.backend = backend.rawValue
        self.devices = devices
    }
}

public struct ScannerCLIDetectPayload: Codable, Sendable, Equatable {
    public let backends: [ScannerCLIDetectedBackend]

    public init(backends: [ScannerCLIDetectedBackend]) {
        self.backends = backends
    }
}

public struct ScannerCLICapabilitiesPayload: Codable, Sendable, Equatable {
    public let scannerID: String
    public let backend: String
    public let capabilities: ScannerCLICapabilitySnapshot

    public init(
        scannerID: String,
        backend: BackendType,
        capabilities: ScannerCapabilities
    ) {
        self.scannerID = scannerID
        self.backend = backend.rawValue
        self.capabilities = ScannerCLICapabilitySnapshot(capabilities)
    }
}

public struct ScannerCLIErrorPayload: Codable, Sendable, Equatable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct ScannerCLIEmptyPayload: Codable, Sendable, Equatable {
    public init() {}
}
