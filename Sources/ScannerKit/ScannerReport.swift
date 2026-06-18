import Foundation

// MARK: - ScannerReport (plan §10 Diagnostics)
//
// 미검증 모델(8100/8300i) 사용자가 JSON 리포트를 보내면, capability 기반으로
// 지원 여부를 판단할 수 있게 한다 (plan §5.3, §16.4).
public struct ScannerReport: Codable, Sendable {
    public let app: String
    public let appVersion: String
    public let generatedAt: Date
    public let scanner: ScannerInfo
    public let backend: BackendInfo
    public let capabilities: CapReport
    public var testResults: TestResults

    public struct ScannerInfo: Codable, Sendable {
        public let id: String
        public let name: String
        public let vendor: String
        public let model: String
        public let usbVendorID: String?
        public let usbProductID: String?
        public init(_ d: ScannerDescriptor) {
            id = d.id; name = d.displayName; vendor = d.vendor; model = d.model
            usbVendorID = d.usbVendorID; usbProductID = d.usbProductID
        }
    }
    public struct BackendInfo: Codable, Sendable {
        public let type: String
        public let available: Bool
        public init(_ t: BackendType, available: Bool) {
            self.type = t.rawValue; self.available = available
        }
    }
    public struct CapReport: Codable, Sendable {
        public let resolutions: [Int]
        public let modes: [String]
        public let bitDepths: [Int]
        public let supportsInfrared: Bool
        public let supportsTransparency: Bool
        public let supportsMultiExposure: Bool
        public init(_ c: ScannerCapabilities) {
            resolutions = c.supportedResolutions.map(\.dpi)
            modes = c.supportedModes.map(\.rawValue)
            bitDepths = c.supportedBitDepths.map(\.rawValue)
            supportsInfrared = c.supportsInfrared
            supportsTransparency = c.supportsTransparency
            supportsMultiExposure = c.supportsMultiExposure
        }
    }
    public struct TestResults: Codable, Sendable {
        public var previewScan: String = "not_tested"
        public var fullScan3600: String = "not_tested"
        public var infraredScan: String = "not_tested"
        public var lastError: String?
    }

    public init(descriptor: ScannerDescriptor, backend: BackendType,
                backendAvailable: Bool, capabilities: ScannerCapabilities) {
        self.app = "Negaflow"
        self.appVersion = "0.1.0"
        self.generatedAt = Date()
        self.scanner = ScannerInfo(descriptor)
        self.backend = BackendInfo(backend, available: backendAvailable)
        self.capabilities = CapReport(capabilities)
        self.testResults = TestResults()
    }

    /// plan §10.3 — JSON 파일로 내보낸다.
    public func write(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(self)
        try data.write(to: url)
    }
}
