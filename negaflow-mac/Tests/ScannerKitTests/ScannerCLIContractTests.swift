import Foundation
import XCTest
@testable import ScannerKit

final class ScannerCLIContractTests: XCTestCase {
    func testCapabilitySnapshotMapsEveryHostCapabilityWithoutGuessing() throws {
        let capabilities = Self.makeCapabilities()
        let snapshot = ScannerCLICapabilitySnapshot(capabilities)

        XCTAssertEqual(snapshot.resolutionsDPI, [900, 3600])
        XCTAssertEqual(snapshot.modes, ["color", "gray"])
        XCTAssertEqual(snapshot.bitDepths, [8, 16])
        XCTAssertEqual(snapshot.sourceModes, ["Transparency"])
        XCTAssertEqual(snapshot.transparencyModes, ["Positive", "Negative"])
        XCTAssertEqual(snapshot.supportsPreview, capabilities.supportsPreview)
        XCTAssertEqual(snapshot.supportsTransparency, capabilities.supportsTransparency)
        XCTAssertEqual(snapshot.supportsInfrared, capabilities.supportsInfrared)
        XCTAssertEqual(snapshot.supportsMultiExposure, capabilities.supportsMultiExposure)
        XCTAssertEqual(snapshot.supportsScanArea, capabilities.supportsScanArea)
        XCTAssertEqual(
            snapshot.supportsPositionedScanArea,
            capabilities.supportsPositionedScanArea == true
        )
        XCTAssertEqual(snapshot.supportsLampWarmupStatus, capabilities.supportsLampWarmupStatus)
        XCTAssertEqual(snapshot.brightnessRange, capabilities.brightnessRange)
        XCTAssertEqual(snapshot.contrastRange, capabilities.contrastRange)
        XCTAssertEqual(snapshot.hardwareExposureRange, capabilities.hardwareExposureRange)
        XCTAssertEqual(snapshot.scanOriginXRange, capabilities.scanOriginXRange)
        XCTAssertEqual(snapshot.scanOriginYRange, capabilities.scanOriginYRange)
        XCTAssertEqual(snapshot.scanWidthRange, capabilities.scanWidthRange)
        XCTAssertEqual(snapshot.scanHeightRange, capabilities.scanHeightRange)
        XCTAssertEqual(snapshot.disabledReasons, capabilities.disabledReasons)
        XCTAssertEqual(snapshot.minScanArea, capabilities.minScanArea)
        XCTAssertEqual(snapshot.maxScanArea, capabilities.maxScanArea)
        XCTAssertEqual(snapshot.scanAreaUnit, capabilities.scanAreaUnit.rawValue)
        XCTAssertEqual(snapshot.outputFormats, capabilities.outputFormats)
        XCTAssertEqual(snapshot.estimatedScanSpeeds.map(\.dpi), [900, 3600])
    }

    func testSuccessEnvelopeHasStableVersionAndRoundTrips() throws {
        let payload = ScannerCLICapabilitiesPayload(
            scannerID: "plugin:fixture:1",
            backend: .plugin,
            capabilities: Self.makeCapabilities()
        )
        let envelope = ScannerCLIEnvelope(command: "capabilities", payload: payload)
        let data = try JSONEncoder().encode(envelope)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(
            ScannerCLIEnvelope<ScannerCLICapabilitiesPayload>.self,
            from: data
        )

        XCTAssertEqual(decoded.schema, "negaflow.scanner-cli")
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.command, "capabilities")
        XCTAssertEqual(decoded.status, "ok")
        XCTAssertEqual(decoded.payload, payload)
        XCTAssertNil(decoded.error)
        XCTAssertTrue(object["error"] is NSNull)
    }

    func testErrorEnvelopeNeverContainsSuccessPayload() throws {
        let envelope = ScannerCLIEnvelope<ScannerCLIEmptyPayload>(
            command: "detect",
            error: ScannerCLIErrorPayload(code: "command_failed", message: "fixture")
        )
        let data = try JSONEncoder().encode(envelope)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(
            ScannerCLIEnvelope<ScannerCLIEmptyPayload>.self,
            from: data
        )

        XCTAssertEqual(decoded.status, "error")
        XCTAssertNil(decoded.payload)
        XCTAssertEqual(decoded.error?.code, "command_failed")
        XCTAssertTrue(object["payload"] is NSNull)
    }

    private static func makeCapabilities() -> ScannerCapabilities {
        ScannerCapabilities(
            supportedResolutions: [Resolution(900), Resolution(3600)],
            supportedModes: [.color, .gray],
            supportedBitDepths: [.eight, .sixteen],
            sourceModes: ["Transparency"],
            transparencyModes: ["Positive", "Negative"],
            supportsPreview: true,
            supportsTransparency: true,
            supportsInfrared: true,
            supportsMultiExposure: true,
            supportsScanArea: true,
            supportsLampWarmupStatus: true,
            brightnessRange: ScannerOptionRange(minimum: -100, maximum: 100, step: 1),
            contrastRange: ScannerOptionRange(minimum: -50, maximum: 50, step: 1),
            hardwareExposureRange: ScannerOptionRange(minimum: -2, maximum: 2, step: 0.1),
            disabledReasons: ["lineart": "not exposed"],
            maxScanArea: ScanArea(widthMM: 36, heightMM: 24),
            minScanArea: ScanArea(widthMM: 1, heightMM: 1),
            scanAreaUnit: .millimeter,
            outputFormats: ["tiff"],
            estimatedScanSpeeds: [3600: 120, 900: 10]
        )
    }
}
