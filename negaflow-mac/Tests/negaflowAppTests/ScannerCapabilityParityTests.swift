import XCTest
import ScannerKit
@testable import negaflowApp

@MainActor
final class ScannerCapabilityParityTests: XCTestCase {
    func testCLIWireSnapshotAndAppGatesConsumeSameCapabilities() throws {
        let capabilities = ScannerCapabilities(
            supportedResolutions: [Resolution(1800), Resolution(3600)],
            supportedModes: [.color],
            supportedBitDepths: [.sixteen],
            sourceModes: ["Transparency"],
            transparencyModes: ["Negative"],
            supportsPreview: true,
            supportsTransparency: true,
            supportsInfrared: false,
            supportsMultiExposure: false,
            supportsScanArea: true,
            supportsPositionedScanArea: true,
            supportsLampWarmupStatus: false,
            brightnessRange: ScannerOptionRange(minimum: -100, maximum: 100),
            scanOriginXRange: ScannerOptionRange(minimum: 1, maximum: 37, step: 0.1),
            scanOriginYRange: ScannerOptionRange(minimum: 2, maximum: 26, step: 0.1),
            scanWidthRange: ScannerOptionRange(minimum: 4, maximum: 36, step: 0.1),
            scanHeightRange: ScannerOptionRange(minimum: 4, maximum: 24, step: 0.1),
            disabledReasons: ["infrared": "device did not report this option"],
            maxScanArea: ScanArea(originXMM: 1, originYMM: 2, widthMM: 36, heightMM: 24),
            minScanArea: ScanArea(originXMM: 1, originYMM: 2, widthMM: 4, heightMM: 4),
            outputFormats: ["tiff"],
            estimatedScanSpeeds: [1800: 30, 3600: 90]
        )
        let payload = ScannerCLICapabilitiesPayload(
            scannerID: "plugin:fixture:parity",
            backend: .plugin,
            capabilities: capabilities
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ScannerCLICapabilitiesPayload.self, from: data)
        let model = AppModel()
        model.capabilities = capabilities

        XCTAssertTrue(model.hasUsableScanCapabilities)
        XCTAssertEqual(decoded.capabilities.resolutionsDPI, capabilities.supportedResolutions.map(\.dpi))
        XCTAssertEqual(decoded.capabilities.modes, capabilities.supportedModes.map(\.rawValue))
        XCTAssertEqual(decoded.capabilities.bitDepths, capabilities.supportedBitDepths.map(\.rawValue))
        XCTAssertEqual(decoded.capabilities.supportsPreview, capabilities.supportsPreview)
        XCTAssertEqual(decoded.capabilities.supportsInfrared, capabilities.supportsInfrared)
        XCTAssertEqual(decoded.capabilities.supportsMultiExposure, capabilities.supportsMultiExposure)
        XCTAssertEqual(decoded.capabilities.supportsScanArea, capabilities.supportsScanArea)
        XCTAssertEqual(
            decoded.capabilities.supportsPositionedScanArea,
            capabilities.supportsPositionedScanArea == true
        )
        XCTAssertEqual(decoded.capabilities.brightnessRange, capabilities.brightnessRange)
        XCTAssertEqual(decoded.capabilities.scanOriginXRange, capabilities.scanOriginXRange)
        XCTAssertEqual(decoded.capabilities.scanOriginYRange, capabilities.scanOriginYRange)
        XCTAssertEqual(decoded.capabilities.scanWidthRange, capabilities.scanWidthRange)
        XCTAssertEqual(decoded.capabilities.scanHeightRange, capabilities.scanHeightRange)
        XCTAssertEqual(decoded.capabilities.disabledReasons, capabilities.disabledReasons)
        XCTAssertEqual(decoded.capabilities.minScanArea, capabilities.minScanArea)
        XCTAssertEqual(decoded.capabilities.maxScanArea, capabilities.maxScanArea)
    }
}
