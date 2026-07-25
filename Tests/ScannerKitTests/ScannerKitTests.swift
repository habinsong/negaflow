import XCTest
import Foundation
import CoreGraphics
import ImageIO
@testable import ScannerKit

// ScannerKit의 license-neutral core와 외부 프로세스 플러그인 계약만 검증한다.
final class ScannerKitTests: XCTestCase {
    func testLegacyScannerConnectionTypesRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for connectionType in [ConnectionType.scsi, .fireWire] {
            let data = try encoder.encode(connectionType)
            XCTAssertEqual(try decoder.decode(ConnectionType.self, from: data), connectionType)
        }
    }

    func testScanOptionsStrongDefault() {
        let o = ScanOptions.strongDefault(scannerID: "plugin:fixture:test")
        XCTAssertEqual(o.resolution, .r3600)
        XCTAssertEqual(o.bitDepth, .sixteen)
        XCTAssertEqual(o.colorMode, .color)
        XCTAssertEqual(o.filmType, .colorNegative)
        XCTAssertFalse(o.infraredEnabled)   // plan §4.2 IR off 기본
    }

    func testCapabilitiesGate() {
        let cap = ScannerCapabilities()
        XCTAssertTrue(cap.supportedResolutions.isEmpty)
        XCTAssertTrue(cap.supportedModes.isEmpty)
        XCTAssertTrue(cap.supportedBitDepths.isEmpty)
        XCTAssertFalse(cap.supports(resolution: .r7200))
        XCTAssertFalse(cap.supports(resolution: Resolution(4800)))
        XCTAssertFalse(cap.supports(depth: .sixteen))
        XCTAssertFalse(cap.supports(mode: .color))
        XCTAssertFalse(cap.supportsPreview)
        XCTAssertFalse(cap.supportsTransparency)
        XCTAssertFalse(cap.supportsInfrared)
        XCTAssertFalse(cap.supportsMultiExposure)
        XCTAssertFalse(cap.supportsScanArea)
        XCTAssertFalse(cap.supportsLampWarmupStatus)
        XCTAssertEqual(cap.maxScanArea, ScanArea(widthMM: 0, heightMM: 0))
        XCTAssertEqual(cap.minScanArea, ScanArea(widthMM: 0, heightMM: 0))
        XCTAssertTrue(cap.outputFormats.isEmpty)
        XCTAssertTrue(cap.estimatedScanSpeeds.isEmpty)
    }

    func testMockDetectsFilmAndFlatbedScanners() async throws {
        let devices = try await MockScannerBackend().detectScanners()

        XCTAssertEqual(devices.map(\.id), [
            MockScannerBackend.filmScannerID,
            MockScannerBackend.flatbedScannerID,
        ])
        XCTAssertEqual(devices.map(\.displayName), [
            "Negaflow Scanner",
            "Negaflow Flatbed Scanner",
        ])
    }

    func testMockFilmScannerCapabilitiesRemainExplicit() async throws {
        let cap = try await MockScannerBackend().getCapabilities(
            scannerID: MockScannerBackend.filmScannerID
        )
        XCTAssertEqual(cap.supportedResolutions, [.r900, .r1800, .r3600, .r7200])
        XCTAssertEqual(cap.supportedModes, [.color, .gray])
        XCTAssertEqual(cap.supportedBitDepths, [.eight, .sixteen])
        XCTAssertEqual(cap.sourceModes, ["Transparency Adapter"])
        XCTAssertTrue(cap.supportsPreview)
        XCTAssertTrue(cap.supportsTransparency)
        XCTAssertTrue(cap.supportsScanArea)
        XCTAssertEqual(cap.supportsPositionedScanArea, false)
        XCTAssertEqual(cap.maxScanArea, .fullFrame35mm)
        XCTAssertEqual(cap.minScanArea, ScanArea(widthMM: 4, heightMM: 4))
        XCTAssertNil(cap.scanOriginXRange)
        XCTAssertNil(cap.scanOriginYRange)
        XCTAssertEqual(cap.outputFormats, ["tiff"])
    }

    func testMockFlatbedCapabilitiesRemainExplicit() async throws {
        let cap = try await MockScannerBackend().getCapabilities(
            scannerID: MockScannerBackend.flatbedScannerID
        )
        XCTAssertEqual(cap.supportedResolutions, [.r900, .r1800, .r3600])
        XCTAssertEqual(cap.sourceModes, ["Flatbed", "Transparency Unit"])
        XCTAssertTrue(cap.supportsPreview)
        XCTAssertEqual(cap.supportsPositionedScanArea, true)
        XCTAssertEqual(cap.maxScanArea, ScanArea(widthMM: 210, heightMM: 297))
        XCTAssertEqual(cap.minScanArea, ScanArea(widthMM: 5, heightMM: 5))
        XCTAssertNotNil(cap.scanOriginXRange)
        XCTAssertNotNil(cap.scanOriginYRange)
        XCTAssertEqual(cap.outputFormats, ["tiff"])
    }

    func testPhysicalScanAreaBoundsClampAndConvertUnits() throws {
        let capabilities = ScannerCapabilities(
            supportsScanArea: true,
            maxScanArea: ScanArea(widthMM: 36, heightMM: 24),
            minScanArea: ScanArea(widthMM: 4, heightMM: 3),
            scanAreaUnit: .millimeter
        )

        let bounds = try XCTUnwrap(capabilities.physicalScanAreaBounds)
        XCTAssertEqual(bounds.minimum, ScanArea(widthMM: 4, heightMM: 3))
        XCTAssertEqual(bounds.maximum, ScanArea(widthMM: 36, heightMM: 24))
        XCTAssertEqual(
            capabilities.clampedPhysicalScanArea(ScanArea(widthMM: 100, heightMM: 1)),
            ScanArea(widthMM: 36, heightMM: 3)
        )
        XCTAssertNil(capabilities.clampedPhysicalScanArea(
            ScanArea(widthMM: .nan, heightMM: 10)
        ))

        XCTAssertEqual(ScanAreaUnit.millimeter.displayValue(fromMillimeters: 25.4), 25.4)
        XCTAssertEqual(
            try XCTUnwrap(ScanAreaUnit.inch.displayValue(fromMillimeters: 25.4)),
            1,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try XCTUnwrap(ScanAreaUnit.inch.millimeters(fromDisplayValue: 2)),
            50.8,
            accuracy: 1e-12
        )
        XCTAssertNil(ScanAreaUnit.pixel.displayValue(fromMillimeters: 25.4))
        XCTAssertNil(ScanAreaUnit.pixel.millimeters(fromDisplayValue: 100))
    }

    func testPositionedPhysicalScanAreaClampsOriginInsideSurface() throws {
        let capabilities = ScannerCapabilities(
            supportsScanArea: true,
            supportsPositionedScanArea: true,
            maxScanArea: ScanArea(originXMM: 1, originYMM: 2, widthMM: 200, heightMM: 100),
            minScanArea: ScanArea(originXMM: 1, originYMM: 2, widthMM: 1, heightMM: 1)
        )

        XCTAssertEqual(
            capabilities.clampedPhysicalScanArea(ScanArea(
                originXMM: 190,
                originYMM: -5,
                widthMM: 40,
                heightMM: 30
            )),
            ScanArea(originXMM: 161, originYMM: 2, widthMM: 40, heightMM: 30)
        )
    }

    func testPositionedPhysicalScanAreaQuantizesToReportedHardwareSteps() throws {
        let capabilities = ScannerCapabilities(
            supportsScanArea: true,
            supportsPositionedScanArea: true,
            scanOriginXRange: ScannerOptionRange(minimum: 0, maximum: 200, step: 0.1),
            scanOriginYRange: ScannerOptionRange(minimum: 0, maximum: 100, step: 0.1),
            scanWidthRange: ScannerOptionRange(minimum: 1, maximum: 200, step: 0.1),
            scanHeightRange: ScannerOptionRange(minimum: 1, maximum: 100, step: 0.1),
            maxScanArea: ScanArea(widthMM: 200, heightMM: 100),
            minScanArea: ScanArea(widthMM: 1, heightMM: 1)
        )

        let area = try XCTUnwrap(capabilities.clampedPhysicalScanArea(ScanArea(
            originXMM: 12.36,
            originYMM: 20.04,
            widthMM: 36.06,
            heightMM: 24.08
        )))
        XCTAssertEqual(area.originXMM, 12.3, accuracy: 1e-12)
        XCTAssertEqual(area.originYMM, 20, accuracy: 1e-12)
        XCTAssertEqual(area.widthMM, 36.2, accuracy: 1e-12)
        XCTAssertEqual(area.heightMM, 24.2, accuracy: 1e-12)
        XCTAssertLessThanOrEqual(area.originXMM, 12.36)
        XCTAssertGreaterThanOrEqual(area.originXMM + area.widthMM, 12.36 + 36.06)
        XCTAssertLessThanOrEqual(area.originYMM, 20.04)
        XCTAssertGreaterThanOrEqual(area.originYMM + area.heightMM, 20.04 + 24.08)
    }

    func testLegacyScanAreaJSONDefaultsOriginToZero() throws {
        let area = try JSONDecoder().decode(
            ScanArea.self,
            from: Data(#"{"widthMM":36,"heightMM":24}"#.utf8)
        )
        XCTAssertEqual(area, .fullFrame35mm)
    }

    func testPhysicalScanAreaBoundsFailClosedWhenUnsupportedOrInvalid() {
        XCTAssertNil(ScannerCapabilities(
            supportsScanArea: false,
            maxScanArea: ScanArea(widthMM: 36, heightMM: 24),
            minScanArea: ScanArea(widthMM: 4, heightMM: 4)
        ).physicalScanAreaBounds)
        XCTAssertNil(ScannerCapabilities(
            supportsScanArea: true,
            maxScanArea: ScanArea(widthMM: 36, heightMM: 24),
            minScanArea: ScanArea(widthMM: 0, heightMM: 4)
        ).physicalScanAreaBounds)
        XCTAssertNil(ScannerCapabilities(
            supportsScanArea: true,
            maxScanArea: ScanArea(widthMM: 36, heightMM: 24),
            minScanArea: ScanArea(widthMM: 40, heightMM: 4)
        ).physicalScanAreaBounds)
        XCTAssertNil(ScannerCapabilities(
            supportsScanArea: true,
            maxScanArea: ScanArea(widthMM: 3_600, heightMM: 2_400),
            minScanArea: ScanArea(widthMM: 100, heightMM: 100),
            scanAreaUnit: .pixel
        ).physicalScanAreaBounds)
    }

    func testBackendTypeFromScannerID() {
        XCTAssertEqual(BackendType(fromScannerID: "plugin:fixture:device:001"), .plugin)
        XCTAssertNil(BackendType(fromScannerID: "legacy-device:001"))
        XCTAssertEqual(BackendType(fromScannerID: "ica-xyz"), .imageCaptureCore)
        XCTAssertEqual(BackendType(fromScannerID: "mock-1"), .mock)
    }

    func testDefaultRegistryRequiresExplicitDemoOptIn() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-empty-plugins-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        setenv("NEGAFLOW_PLUGINS_DIR", root.path, 1)
        defer { unsetenv("NEGAFLOW_PLUGINS_DIR") }

        XCTAssertFalse(ScannerRegistry.default().backends.contains { $0.backendType == .mock })
        XCTAssertTrue(ScannerRegistry.default(includeDemo: true).backends.contains { $0.backendType == .mock })
    }

    func testScannerReportSerialization() throws {
        let d = ScannerDescriptor(id: "plugin:fixture:x", displayName: "Plustek OpticFilm 8200i",
                                  vendor: "Plustek", model: "OpticFilm 8200i",
                                  backendType: .plugin, verifiedStatus: .verified)
        let r = ScannerReport(descriptor: d, backend: .plugin,
                              backendAvailable: true, capabilities: ScannerCapabilities())
        let data = try JSONEncoder().encode(r)
        XCTAssertGreaterThan(data.count, 50)
    }

    func testPluginScanOptionsNewWireFieldsRemainOptionalForLegacyPayloads() throws {
        let data = Data("""
        {
          "deviceID":"dev0",
          "resolutionDPI":3600,
          "bitDepth":16,
          "colorMode":"color",
          "filmType":"colorNegative",
          "preview":false,
          "multiExposure":false,
          "infrared":false,
          "outputPath":"/tmp/out.tiff"
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(PluginScanOptions.self, from: data)
        XCTAssertNil(decoded.scanArea)
        XCTAssertNil(decoded.hardwareExposureTime)
        XCTAssertNil(decoded.outputRawTIFF)
        XCTAssertNil(decoded.capabilityToken)
    }

    func testAppliedScanOptionsEvidenceStableCodableRoundTrip() throws {
        let outputURL = URL(fileURLWithPath: "/tmp/negaflow-applied-options.tiff")
        let requestID = UUID(uuidString: "6F959CD1-87A2-4DDA-9C5F-A3C12E36AB55")!
        let options = ScanOptions(
            requestID: requestID,
            scannerID: "plugin:test:dev0",
            resolution: .r7200,
            bitDepth: .sixteen,
            colorMode: .gray,
            filmType: .bwNegative,
            scanArea: ScanArea(widthMM: 24, heightMM: 18),
            infraredEnabled: true,
            multiExposureEnabled: true,
            hardwareExposureTime: 250,
            brightnessAdjustment: -1.5,
            contrastAdjustment: 2.25,
            outputRawTIFF: true,
            temporaryOutputURL: outputURL
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()

        for evidence in [
            AppliedScanOptionsEvidence.verified(options),
            .unknownLegacy(protocolVersion: 1)
        ] {
            let data = try encoder.encode(evidence)
            XCTAssertEqual(try decoder.decode(AppliedScanOptionsEvidence.self, from: data), evidence)
        }

        XCTAssertThrowsError(try encoder.encode(AppliedScanOptionsEvidence.unknownLegacy(protocolVersion: 2)))
        XCTAssertThrowsError(try decoder.decode(
            AppliedScanOptionsEvidence.self,
            from: Data(#"{"kind":"unknownLegacy","protocolVersion":2}"#.utf8)
        ))
    }

    func testPluginAppliedOptionsEncodeExplicitNullForRequiredOptionalKeys() throws {
        let applied = PluginAppliedScanOptions(
            deviceID: "dev0",
            resolutionDPI: 3600,
            bitDepth: 16,
            colorMode: "color",
            filmType: "colorNegative",
            scanArea: .fullFrame35mm,
            infrared: false,
            multiExposure: false,
            outputRawTIFF: true
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(applied)) as? [String: Any]
        )

        XCTAssertTrue(object.keys.contains("hardwareExposureTime"))
        XCTAssertTrue(object.keys.contains("brightnessAdjustment"))
        XCTAssertTrue(object.keys.contains("contrastAdjustment"))
        XCTAssertTrue(object["hardwareExposureTime"] is NSNull)
        XCTAssertTrue(object["brightnessAdjustment"] is NSNull)
        XCTAssertTrue(object["contrastAdjustment"] is NSNull)
    }

    func testMockPreviewReportsForcedAppliedOptions() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-mock-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("preview.tiff")
        let backend = MockScannerBackend()
        backend.sampleNegativesDir = nil
        var requested = ScanOptions.strongDefault(scannerID: MockScannerBackend.filmScannerID)
        requested.requestID = UUID()
        requested.resolution = .r7200
        requested.bitDepth = .sixteen
        requested.temporaryOutputURL = output

        let result = try await backend.startPreviewScan(requested) { _ in }

        XCTAssertEqual(result.resolution, .preview)
        XCTAssertEqual(result.bitDepth, .eight)
        XCTAssertEqual(result.reportedResolution, .preview)
        XCTAssertEqual(result.reportedBitDepth, .eight)
        var expected = requested
        expected.resolution = .preview
        expected.bitDepth = .eight
        XCTAssertEqual(result.appliedOptionsEvidence, .verified(expected))
    }

    func testMockSampleCopiesToRequestedOutputAndReportsItAsApplied() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-mock-sample-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sample = directory.appendingPathComponent("raw_3600_16bit.tiff")
        let output = directory.appendingPathComponent("published.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: sample)
        let backend = MockScannerBackend()
        backend.sampleNegativesDir = directory
        var options = ScanOptions.strongDefault(scannerID: MockScannerBackend.filmScannerID)
        options.temporaryOutputURL = output

        let result = try await backend.startFullScan(options) { _ in }

        XCTAssertEqual(result.rawFileURL, output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sample.path))
        XCTAssertEqual(try Data(contentsOf: output), try Data(contentsOf: sample))
        XCTAssertEqual(result.reportedResolution, options.resolution)
        XCTAssertEqual(result.reportedBitDepth, options.bitDepth)
        XCTAssertEqual(result.appliedOptionsEvidence, .verified(options))
    }

    func testMockPositionedScanPreservesSelectedPreviewPixelAspectRatio() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-mock-flatbed-region-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("region.tiff")
        let backend = MockScannerBackend()
        backend.sampleNegativesDir = nil
        var options = ScanOptions.strongDefault(scannerID: MockScannerBackend.flatbedScannerID)
        options.scanArea = ScanArea(originXMM: 20, originYMM: 30, widthMM: 60, heightMM: 30)
        options.temporaryOutputURL = output

        let result = try await backend.startFullScan(options) { _ in }

        let cropRect = try XCTUnwrap(MockScannerBackend.flatbedPreviewCropRect(
            for: options.scanArea,
            imageSize: CGSize(width: 3_701, height: 401)
        ))
        let outputRatio = Double(result.width) / Double(result.height)
        let selectedPreviewRatio = Double(cropRect.width / cropRect.height)
        XCTAssertEqual(result.width, 1_600)
        XCTAssertEqual(outputRatio / selectedPreviewRatio, 1, accuracy: 0.01)
        XCTAssertEqual(result.appliedOptionsEvidence, .verified(options))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    func testMockSimulatorPerforationSwitchesFrameAndRollSamples() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-mock-perforation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = MockScannerBackend()

        var frameOptions = ScanOptions.strongDefault(scannerID: MockScannerBackend.filmScannerID)
        frameOptions.temporaryOutputURL = directory.appendingPathComponent("frame.tiff")
        let frame = try await backend.startFullScan(frameOptions) { _ in }
        XCTAssertEqual(frame.width, 631)
        XCTAssertEqual(frame.height, 403)

        backend.setSimulatorIncludesPerforation(true)
        frameOptions.temporaryOutputURL = directory.appendingPathComponent("frame-perforation.tiff")
        let perforatedFrame = try await backend.startFullScan(frameOptions) { _ in }
        XCTAssertEqual(perforatedFrame.width, 631)
        XCTAssertEqual(perforatedFrame.height, 544)

        var rollOptions = ScanOptions.preview(scannerID: MockScannerBackend.flatbedScannerID)
        rollOptions.temporaryOutputURL = directory.appendingPathComponent("roll-perforation.tiff")
        let perforatedRoll = try await backend.startPreviewScan(rollOptions) { _ in }
        XCTAssertEqual(perforatedRoll.width, 3_735)
        XCTAssertEqual(perforatedRoll.height, 1_898)
    }

    func testMockFlatbedRegionMapsPhysicalAreaIntoPreviewPixels() throws {
        XCTAssertEqual(
            MockScannerBackend.flatbedPreviewCropRect(
                for: ScanArea(originXMM: 21, originYMM: 29.7, widthMM: 42, heightMM: 59.4),
                imageSize: CGSize(width: 1_000, height: 1_400)
            ),
            CGRect(x: 100, y: 979, width: 200, height: 281)
        )
        XCTAssertNil(MockScannerBackend.flatbedPreviewCropRect(
            for: ScanArea(originXMM: 220, originYMM: 310, widthMM: 10, heightMM: 10),
            imageSize: CGSize(width: 1_000, height: 1_400)
        ))
    }

    func testScanResultReportedProvenanceCodableFailsClosed() throws {
        let outputURL = URL(fileURLWithPath: "/tmp/scan-result-provenance.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:test:dev0")
        options.requestID = UUID()
        options.temporaryOutputURL = outputURL
        let verified = ScanResult(
            rawFileURL: outputURL,
            width: 10,
            height: 8,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            backendUsed: .plugin,
            appliedOptionsEvidence: .verified(options)
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let verifiedData = try encoder.encode(verified)
        XCTAssertEqual(try decoder.decode(ScanResult.self, from: verifiedData), verified)

        var verifiedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: verifiedData) as? [String: Any]
        )
        verifiedObject.removeValue(forKey: "reportedResolution")
        XCTAssertThrowsError(try decoder.decode(
            ScanResult.self,
            from: JSONSerialization.data(withJSONObject: verifiedObject)
        ))

        verifiedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: verifiedData) as? [String: Any]
        )
        verifiedObject["reportedBitDepth"] = NSNull()
        XCTAssertThrowsError(try decoder.decode(
            ScanResult.self,
            from: JSONSerialization.data(withJSONObject: verifiedObject)
        ))

        let legacy = ScanResult(
            rawFileURL: outputURL,
            width: 10,
            height: 8,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            backendUsed: .plugin,
            appliedOptionsEvidence: .unknownLegacy(protocolVersion: 1)
        )
        let legacyData = try encoder.encode(legacy)
        let legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: legacyData) as? [String: Any]
        )
        XCTAssertTrue(legacyObject["reportedResolution"] is NSNull)
        XCTAssertTrue(legacyObject["reportedBitDepth"] is NSNull)
        XCTAssertEqual(try decoder.decode(ScanResult.self, from: legacyData), legacy)
    }

    // MARK: - 외부 플러그인 발견 + 프로토콜 매핑
    //
    // 가짜 플러그인(고정 JSON을 반환하는 셸 스크립트)을 임시 플러그인 디렉토리에 설치해,
    // ScannerPluginHost.discover() 와 ExternalScannerBackend 의 detect/capabilities/scan
    // JSON 매핑을 검증한다. 실제 스캐너/실제 이미지는 사용하지 않는다.

    func testDiscoverAndExternalBackendProtocol() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-plugins-\(UUID().uuidString)", isDirectory: true)
        let pluginDir = dir.appendingPathComponent("fake", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let execURL = pluginDir.appendingPathComponent("fake-scanner")
        try Self.fakePluginScript.write(to: execURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execURL.path)
        try Self.writeValidTIFF(to: pluginDir.appendingPathComponent("valid-scan.tiff"))

        let manifest = ScannerPluginManifest(
            schemaVersion: 1, id: "fake", name: "Fake Scanner Plugin",
            executable: "fake-scanner", kind: "scanner", license: "MIT"
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: pluginDir.appendingPathComponent("manifest.json"))

        setenv("NEGAFLOW_PLUGINS_DIR", dir.path, 1)
        defer { unsetenv("NEGAFLOW_PLUGINS_DIR") }

        let plugins = ScannerPluginHost.discover()
        XCTAssertEqual(plugins.count, 1)
        let plugin = try XCTUnwrap(plugins.first)
        XCTAssertEqual(plugin.id, "fake")

        let backend = ExternalScannerBackend(plugin: plugin)

        // detect → 외부 id 는 plugin:<id>:<내부id> 로 감싸진다.
        let devices = try await backend.detectScanners()
        XCTAssertEqual(devices.count, 1)
        let device = try XCTUnwrap(devices.first)
        XCTAssertEqual(device.id, "plugin:fake:dev0")
        XCTAssertEqual(device.backendType, .plugin)
        XCTAssertTrue(backend.owns(scannerID: device.id))

        // capabilities → wire JSON 이 ScannerCapabilities 로 매핑된다.
        let caps = try await backend.getCapabilities(scannerID: device.id)
        XCTAssertTrue(caps.supportedResolutions.contains(.r3600))
        XCTAssertTrue(caps.supportedResolutions.contains(.r7200))
        XCTAssertTrue(caps.supportedModes.contains(.color))
        XCTAssertTrue(caps.supportedBitDepths.contains(.sixteen))
        XCTAssertEqual(caps.sourceModes, ["Flatbed", "Transparency Adapter"])
        XCTAssertEqual(caps.transparencyModes, ["Transparency Adapter"])
        XCTAssertEqual(caps.brightnessRange, ScannerOptionRange(minimum: -10, maximum: 10, step: 1))
        XCTAssertEqual(caps.contrastRange, ScannerOptionRange(minimum: -20, maximum: 20, step: 2))
        XCTAssertEqual(caps.scanOriginXRange, ScannerOptionRange(minimum: 1, maximum: 36.33, step: 0.01))
        XCTAssertEqual(caps.scanWidthRange, ScannerOptionRange(minimum: 1, maximum: 36.33, step: 0.01))
        XCTAssertEqual(caps.disabledReason(for: "infrared"), "no infrared source")
        XCTAssertFalse(caps.supportsPreview)
        XCTAssertTrue(caps.supportsScanArea)
        XCTAssertTrue(caps.supportsPositionedScanArea == true)
        XCTAssertEqual(
            caps.minScanArea,
            ScanArea(originXMM: 1, originYMM: 2, widthMM: 1, heightMM: 1)
        )
        XCTAssertEqual(
            caps.maxScanArea,
            ScanArea(originXMM: 1, originYMM: 2, widthMM: 36.33, heightMM: 25)
        )
        XCTAssertEqual(caps.scanAreaUnit, .millimeter)
        XCTAssertNotNil(caps.physicalScanAreaBounds)
        XCTAssertTrue(caps.outputFormats.isEmpty)

        // scan → NDJSON 진행률 이벤트가 전달되고, result 가 ScanResult 로 매핑된다.
        let output = ScanTempFile.makeURL(prefix: "fake_scan", suffix: ".tiff")
        let infraredScanOutput = ScanTempFile.makeURL(prefix: "fake_scan_ir", suffix: ".tiff")
        let infraredOutput = URL(fileURLWithPath: infraredScanOutput.path + ".ir.tiff")
        defer {
            if FileManager.default.fileExists(atPath: output.path) {
                try? FileManager.default.removeItem(at: output)
            }
            if FileManager.default.fileExists(atPath: infraredScanOutput.path) {
                try? FileManager.default.removeItem(at: infraredScanOutput)
            }
            if FileManager.default.fileExists(atPath: infraredOutput.path) {
                try? FileManager.default.removeItem(at: infraredOutput)
            }
        }
        var opts = ScanOptions.strongDefault(scannerID: device.id)
        opts.temporaryOutputURL = output
        opts.scanArea = ScanArea(widthMM: 12.5, heightMM: 8.25)
        opts.hardwareExposureTime = 123
        opts.outputRawTIFF = false
        let progressPhases = ProgressCollector()
        let result = try await backend.startFullScan(opts) { p in progressPhases.add(p.phase) }
        XCTAssertEqual(result.rawFileURL.path, output.path)
        XCTAssertEqual(result.width, 10)
        XCTAssertEqual(result.height, 8)
        XCTAssertEqual(result.backendUsed, .plugin)
        XCTAssertTrue(progressPhases.phases.contains(.scanningRGB))
        XCTAssertFalse(result.hasInfraredChannel)
        XCTAssertNil(result.infraredFileURL)
        XCTAssertEqual(result.warnings, ["fake warning"])

        opts.infraredEnabled = true
        opts.temporaryOutputURL = infraredScanOutput
        let infraredResult = try await backend.startFullScan(opts) { _ in }
        XCTAssertEqual(infraredResult.rawFileURL, infraredScanOutput)
        XCTAssertTrue(infraredResult.hasInfraredChannel)
        XCTAssertEqual(infraredResult.infraredFileURL, infraredOutput)
        XCTAssertTrue(FileManager.default.fileExists(atPath: infraredOutput.path))
    }

    func testPluginDiscoveryRejectsExecutableEscapeAndPublishesStableTrustIdentity() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            "negaflow-plugin-trust-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside-tool")
        try "#!/bin/sh\nexit 0\n".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: outside.path
        )

        try writeDiscoveryFixture(
            id: "absolute",
            executable: outside.path,
            root: root,
            createExecutable: false
        )
        try writeDiscoveryFixture(
            id: "traversal",
            executable: "../outside-tool",
            root: root,
            createExecutable: false
        )
        let symlinkDirectory = try writeDiscoveryFixture(
            id: "symlink",
            executable: "linked-tool",
            root: root,
            createExecutable: false
        )
        try FileManager.default.createSymbolicLink(
            at: symlinkDirectory.appendingPathComponent("linked-tool"),
            withDestinationURL: outside
        )
        let trustedDirectory = try writeDiscoveryFixture(
            id: "trusted",
            executable: "plugin-tool",
            root: root
        )

        setenv("NEGAFLOW_PLUGINS_DIR", root.path, 1)
        defer { unsetenv("NEGAFLOW_PLUGINS_DIR") }
        let first = ScannerPluginHost.discover()

        XCTAssertEqual(first.map(\.id), ["trusted"])
        let firstIdentity = try XCTUnwrap(first.first?.trustIdentity)
        XCTAssertEqual(firstIdentity.pluginID, "trusted")
        XCTAssertEqual(firstIdentity.manifestSHA256.count, 64)
        XCTAssertEqual(firstIdentity.executableSHA256.count, 64)

        try "#!/bin/sh\nprintf changed\n".write(
            to: trustedDirectory.appendingPathComponent("plugin-tool"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: trustedDirectory.appendingPathComponent("plugin-tool").path
        )
        let secondIdentity = try XCTUnwrap(ScannerPluginHost.discover().first?.trustIdentity)
        XCTAssertNotEqual(secondIdentity.executableSHA256, firstIdentity.executableSHA256)
    }

    func testPluginDiscoveryRejectsGroupOrWorldWritableInstallation() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            "negaflow-plugin-permissions-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try writeDiscoveryFixture(
            id: "writable",
            executable: "plugin-tool",
            root: root
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o775],
            ofItemAtPath: directory.appendingPathComponent("plugin-tool").path
        )
        setenv("NEGAFLOW_PLUGINS_DIR", root.path, 1)
        defer { unsetenv("NEGAFLOW_PLUGINS_DIR") }

        XCTAssertTrue(ScannerPluginHost.discover().isEmpty)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: directory.appendingPathComponent("plugin-tool").path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o775],
            ofItemAtPath: root.path
        )
        XCTAssertTrue(ScannerPluginHost.discover().isEmpty)
    }

    func testPluginTrustStoreRequiresApprovalAndInvalidatesChangedExecutable() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            "negaflow-plugin-approval-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginDirectory = try writeDiscoveryFixture(
            id: "approval",
            executable: "plugin-tool",
            root: root
        )
        setenv("NEGAFLOW_PLUGINS_DIR", root.path, 1)
        defer { unsetenv("NEGAFLOW_PLUGINS_DIR") }
        let plugin = try XCTUnwrap(ScannerPluginHost.discover().first)
        let identity = try XCTUnwrap(plugin.trustIdentity)
        let store = ScannerPluginTrustStore(
            fileURL: root.appendingPathComponent("trust.json")
        )

        XCTAssertEqual(store.approvalState(for: plugin), .approvalRequired)
        try store.approve(
            plugin,
            approvedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(store.approvalState(for: plugin), .approved)
        XCTAssertEqual(store.approvedPlugins(from: [plugin]).map(\.id), [plugin.id])
        XCTAssertEqual(try store.records().map(\.identity), [identity])

        let executableURL = pluginDirectory.appendingPathComponent("plugin-tool")
        try "#!/bin/sh\nexit 2\n".write(
            to: executableURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        XCTAssertEqual(store.approvalState(for: plugin), .invalidIdentity)

        let changedPlugin = try XCTUnwrap(ScannerPluginHost.discover().first)
        XCTAssertEqual(store.approvalState(for: changedPlugin), .identityChanged)
        try store.approve(changedPlugin)
        XCTAssertEqual(store.approvalState(for: changedPlugin), .approved)
        try store.revoke(pluginID: changedPlugin.id)
        XCTAssertEqual(store.approvalState(for: changedPlugin), .approvalRequired)
    }

    func testCorruptPluginTrustStoreFailsClosed() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            "negaflow-plugin-approval-corrupt-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try writeDiscoveryFixture(
            id: "corrupt-store",
            executable: "plugin-tool",
            root: root
        )
        setenv("NEGAFLOW_PLUGINS_DIR", root.path, 1)
        defer { unsetenv("NEGAFLOW_PLUGINS_DIR") }
        let plugin = try XCTUnwrap(ScannerPluginHost.discover().first)
        let storeURL = root.appendingPathComponent("trust.json")
        try Data("{}".utf8).write(to: storeURL)
        let store = ScannerPluginTrustStore(fileURL: storeURL)

        XCTAssertEqual(store.approvalState(for: plugin), .storeUnavailable)
        XCTAssertTrue(store.approvedPlugins(from: [plugin]).isEmpty)
        XCTAssertThrowsError(try store.approve(plugin)) { error in
            XCTAssertEqual(error as? ScannerPluginTrustStoreError, .invalidStore)
        }
    }

    func testExternalBackendRejectsPluginChangedAfterDiscoveryBeforeLaunch() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            "negaflow-plugin-launch-identity-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginDirectory = try writeDiscoveryFixture(
            id: "launch-identity",
            executable: "plugin-tool",
            root: root
        )
        setenv("NEGAFLOW_PLUGINS_DIR", root.path, 1)
        defer { unsetenv("NEGAFLOW_PLUGINS_DIR") }
        let plugin = try XCTUnwrap(ScannerPluginHost.discover().first)
        let marker = root.appendingPathComponent("launched")
        let executableURL = pluginDirectory.appendingPathComponent("plugin-tool")
        try "#!/bin/sh\ntouch '\(marker.path)'\nexit 0\n".write(
            to: executableURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        do {
            _ = try await ExternalScannerBackend(plugin: plugin).detectScanners()
            XCTFail("발견 후 변경된 plugin 실행을 허용했습니다")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .ioFailure)
            XCTAssertTrue(error.message.contains("발견 이후 변경"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testExternalBackendRejectsUnrequestedInfraredResult() async throws {
        let fixture = try Self.makeBackendFixture(id: "unsolicited-ir", script: Self.unsolicitedIRPluginScript)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("scan.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:unsolicited-ir:dev0")
        options.temporaryOutputURL = output

        do {
            _ = try await fixture.backend.startFullScan(options) { _ in }
            XCTFail("요청하지 않은 IR 결과를 수용했습니다")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .ioFailure)
            XCTAssertTrue(error.message.contains("요청하지 않은 IR"))
        }
    }

    func testExternalBackendRejectsMissingRequestedInfraredFile() async throws {
        let fixture = try Self.makeBackendFixture(id: "missing-ir", script: Self.missingIRPluginScript)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("scan.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:missing-ir:dev0")
        options.infraredEnabled = true
        options.temporaryOutputURL = output

        do {
            _ = try await fixture.backend.startFullScan(options) { _ in }
            XCTFail("존재하지 않는 IR 결과 파일을 수용했습니다")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .ioFailure)
            XCTAssertTrue(error.message.contains("IR 결과 파일 없음"))
        }
    }

    func testExternalBackendRejectsRequestedInfraredFlagMismatch() async throws {
        let fixture = try Self.makeBackendFixture(id: "inconsistent-ir", script: Self.inconsistentIRPluginScript)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("scan.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:inconsistent-ir:dev0")
        options.infraredEnabled = true
        options.temporaryOutputURL = output

        do {
            _ = try await fixture.backend.startFullScan(options) { _ in }
            XCTFail("서로 불일치하는 IR 경로와 플래그를 수용했습니다")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .ioFailure)
            XCTAssertTrue(error.message.contains("경로와 플래그 불일치"))
        }
    }

    func testExternalBackendRejectsZeroByteInfraredArtifact() async throws {
        try await assertInfraredArtifactRejected(
            id: "zero-byte-ir",
            script: Self.zeroByteIRPluginScript,
            expectedMessage: "IR 결과 파일이 비어 있음"
        )
    }

    func testExternalBackendRejectsMismatchedInfraredDimensions() async throws {
        try await assertInfraredArtifactRejected(
            id: "mismatched-ir",
            script: Self.mismatchedIRPluginScript,
            expectedMessage: "RGB/IR 픽셀 크기 불일치"
        )
    }

    func testExternalBackendKeepsFastTerminalResultAcrossConcurrentProcesses() async throws {
        let fixtures = try (0..<8).map { index in
            try Self.makeBackendFixture(id: "fast-result-\(index)", script: Self.fastResultPluginScript)
        }
        defer {
            for fixture in fixtures { try? FileManager.default.removeItem(at: fixture.root) }
        }

        try await withThrowingTaskGroup(of: URL.self) { group in
            for (index, fixture) in fixtures.enumerated() {
                group.addTask {
                    let output = fixture.root.appendingPathComponent("scan-\(index).tiff")
                    var options = ScanOptions.strongDefault(scannerID: "plugin:fast-result-\(index):dev0")
                    options.temporaryOutputURL = output
                    let result = try await fixture.backend.startFullScan(options) { _ in }
                    return result.rawFileURL
                }
            }
            var completed = 0
            for try await output in group {
                XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
                completed += 1
            }
            XCTAssertEqual(completed, fixtures.count)
        }
    }

    func testExternalBackendRejectsMissingRawArtifact() async throws {
        try await assertRawArtifactRejected(
            id: "missing-raw",
            script: Self.missingRawPluginScript,
            expectedMessage: "파일 없음"
        )
    }

    func testExternalBackendRejectsZeroByteRawArtifact() async throws {
        try await assertRawArtifactRejected(
            id: "empty-raw",
            script: Self.zeroByteRawPluginScript,
            expectedMessage: "비어 있음"
        )
    }

    func testExternalBackendRejectsNonRegularRawArtifact() async throws {
        try await assertRawArtifactRejected(
            id: "directory-raw",
            script: Self.directoryRawPluginScript,
            expectedMessage: "regular file이 아님"
        )
    }

    func testExternalBackendRejectsUndecodableRawArtifact() async throws {
        try await assertRawArtifactRejected(
            id: "invalid-raw",
            script: Self.invalidRawPluginScript,
            expectedMessage: "이미지 메타데이터 해석 실패"
        )
    }

    func testExternalBackendRejectsRawArtifactAtUnexpectedPath() async throws {
        try await assertRawArtifactRejected(
            id: "wrong-path-raw",
            script: Self.wrongPathRawPluginScript,
            expectedMessage: "경로 불일치"
        )
    }

    func testExternalBackendCancelRemovesStagedRawArtifact() async throws {
        let fixture = try Self.makeBackendFixture(id: "cancel-staging", script: Self.stagedRawThenWaitPluginScript)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("scan.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:cancel-staging:dev0")
        options.temporaryOutputURL = output
        let task = Task { try await fixture.backend.startFullScan(options) { _ in } }
        defer { task.cancel() }

        try await Self.waitForStagedRaw(in: fixture.root)
        await fixture.backend.cancelScan()
        do {
            _ = try await task.value
            XCTFail("취소된 스캔이 성공했습니다")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .cancelled)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: fixture.root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".negaflow-scan-") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testExternalBackendDrainsVerbosePluginStderrDuringDetect() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-plugins-\(UUID().uuidString)", isDirectory: true)
        let pluginDir = dir.appendingPathComponent("fake-verbose", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let execURL = pluginDir.appendingPathComponent("fake-verbose-scanner")
        try Self.verboseStderrPluginScript.write(to: execURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execURL.path)

        let manifest = ScannerPluginManifest(
            schemaVersion: 1, id: "fake-verbose", name: "Verbose Fake Scanner Plugin",
            executable: "fake-verbose-scanner", kind: "scanner", license: "MIT"
        )
        try JSONEncoder().encode(manifest).write(to: pluginDir.appendingPathComponent("manifest.json"))

        setenv("NEGAFLOW_PLUGINS_DIR", dir.path, 1)
        defer { unsetenv("NEGAFLOW_PLUGINS_DIR") }

        let plugin = try XCTUnwrap(ScannerPluginHost.discover().first)
        let backend = ExternalScannerBackend(plugin: plugin)
        let devices = try await backend.detectScanners()
        XCTAssertEqual(devices.first?.id, "plugin:fake-verbose:dev0")
    }

    /// detect/capabilities/scan 서브커맨드에 고정 JSON을 반환하는 가짜 플러그인 셸.
    static let fakePluginScript = """
    #!/bin/bash
    case "$1" in
      detect)
        echo '{"devices":[{"id":"dev0","displayName":"Fake Scanner","vendor":"Test","model":"T1","connectionType":"usb","verifiedStatus":"experimental"},{"id":"dev0","displayName":"Duplicate Scanner","vendor":"Other","model":"T2","connectionType":"usb","verifiedStatus":"experimental"}]}'
        ;;
      capabilities)
        identity=$(cat)
        printf '%s' "$identity" | grep -q '"deviceID":"dev0"' || exit 21
        printf '%s' "$identity" | grep -q '"vendor":"Test"' || exit 22
        printf '%s' "$identity" | grep -q '"model":"T1"' || exit 23
        echo '{"resolutionsDPI":[3600,7200],"modes":["color","gray"],"bitDepths":[8,16],"sourceModes":["Flatbed","Transparency Adapter"],"transparencyModes":["Transparency Adapter"],"supportsTransparency":true,"supportsInfrared":false,"supportsScanArea":true,"supportsPositionedScanArea":true,"minScanAreaOriginXMM":1,"minScanAreaOriginYMM":2,"minScanAreaWidthMM":1,"minScanAreaHeightMM":1,"maxScanAreaOriginXMM":1,"maxScanAreaOriginYMM":2,"maxScanAreaWidthMM":36.33,"maxScanAreaHeightMM":25,"scanAreaUnit":"millimeter","scanOriginXRange":{"minimum":1,"maximum":36.33,"step":0.01},"scanOriginYRange":{"minimum":2,"maximum":25,"step":0.01},"scanWidthRange":{"minimum":1,"maximum":36.33,"step":0.01},"scanHeightRange":{"minimum":1,"maximum":25,"step":0.01},"brightnessRange":{"minimum":-10,"maximum":10,"step":1},"contrastRange":{"minimum":-20,"maximum":20,"step":2},"disabledReasons":{"infrared":"no infrared source"}}'
        ;;
      scan)
        payload=$(cat)
        printf '%s' "$payload" | grep -q '"scanArea"' || exit 31
        printf '%s' "$payload" | grep -q '"widthMM":12.5' || exit 32
        printf '%s' "$payload" | grep -q '"heightMM":8.25' || exit 33
        printf '%s' "$payload" | grep -q '"hardwareExposureTime":123' || exit 34
        printf '%s' "$payload" | grep -q '"outputRawTIFF":false' || exit 35
        out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
        cp "$(dirname "$0")/valid-scan.tiff" "$out"
        echo '{"type":"progress","phase":"scanningRGB","fraction":0.5,"message":"scanning"}'
        if printf '%s' "$payload" | grep -q '"infrared":true'; then
          cp "$(dirname "$0")/valid-scan.tiff" "$out.ir.tiff"
          printf '{"type":"result","width":10,"height":8,"path":"%s","resolutionDPI":3600,"bitDepth":16,"irPath":"%s.ir.tiff","hasInfrared":true,"warnings":["fake warning"]}\\n' "$out" "$out"
        else
          printf '{"type":"result","width":10,"height":8,"path":"%s","resolutionDPI":3600,"bitDepth":16,"hasInfrared":false,"warnings":["fake warning"]}\\n' "$out"
        fi
        ;;
    esac
    """

    static let verboseStderrPluginScript = """
    #!/bin/bash
    case "$1" in
      detect)
        perl -e 'print STDERR "diagnostic line\\n" x 20000'
        echo '{"devices":[{"id":"dev0","displayName":"Verbose Fake Scanner","vendor":"Test","model":"T2","connectionType":"usb","verifiedStatus":"experimental"}]}'
        ;;
    esac
    """

    static let unsolicitedIRPluginScript = """
    #!/bin/bash
    payload=$(cat)
    out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
    cp "$(dirname "$0")/valid-scan.tiff" "$out"
    : > "$out.ir.tiff"
    printf '{"type":"result","width":10,"height":8,"path":"%s","irPath":"%s.ir.tiff","hasInfrared":true}\\n' "$out" "$out"
    """

    static let missingIRPluginScript = """
    #!/bin/bash
    payload=$(cat)
    out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
    cp "$(dirname "$0")/valid-scan.tiff" "$out"
    printf '{"type":"result","width":10,"height":8,"path":"%s","irPath":"%s.missing-ir.tiff","hasInfrared":true}\\n' "$out" "$out"
    """

    static let inconsistentIRPluginScript = """
    #!/bin/bash
    payload=$(cat)
    out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
    cp "$(dirname "$0")/valid-scan.tiff" "$out"
    : > "$out.ir.tiff"
    printf '{"type":"result","width":10,"height":8,"path":"%s","irPath":"%s.ir.tiff","hasInfrared":false}\\n' "$out" "$out"
    """

    static let zeroByteIRPluginScript = """
    #!/bin/bash
    payload=$(cat)
    out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
    cp "$(dirname "$0")/valid-scan.tiff" "$out"
    : > "$out.ir.tiff"
    printf '{"type":"result","width":10,"height":8,"path":"%s","irPath":"%s.ir.tiff","hasInfrared":true}\n' "$out" "$out"
    """

    static let mismatchedIRPluginScript = """
    #!/bin/bash
    payload=$(cat)
    out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
    cp "$(dirname "$0")/valid-scan.tiff" "$out"
    cp "$(dirname "$0")/mismatched-scan.tiff" "$out.ir.tiff"
    printf '{"type":"result","width":10,"height":8,"path":"%s","irPath":"%s.ir.tiff","hasInfrared":true}\n' "$out" "$out"
    """

    static let fastResultPluginScript = """
    #!/bin/bash
    payload=$(cat)
    out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
    cp "$(dirname "$0")/valid-scan.tiff" "$out"
    printf '{"type":"result","width":10,"height":8,"path":"%s","hasInfrared":false}\n' "$out"
    """

    static let missingRawPluginScript = """
    #!/bin/bash
    payload=$(cat)
    out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
    printf '{"type":"result","width":10,"height":8,"path":"%s"}\\n' "$out"
    """

    static let zeroByteRawPluginScript = """
    #!/bin/bash
    payload=$(cat)
    out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
    : > "$out"
    printf '{"type":"result","width":10,"height":8,"path":"%s"}\\n' "$out"
    """

    static let invalidRawPluginScript = """
    #!/bin/bash
    payload=$(cat)
    out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
    printf 'not-an-image' > "$out"
    printf '{"type":"result","width":10,"height":8,"path":"%s"}\\n' "$out"
    """

    static let directoryRawPluginScript = """
    #!/bin/bash
    payload=$(cat)
    out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
    mkdir "$out"
    printf '{"type":"result","width":10,"height":8,"path":"%s"}\\n' "$out"
    """

    static let wrongPathRawPluginScript = """
    #!/bin/bash
    payload=$(cat)
    out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
    wrong="$out.wrong"
    cp "$(dirname "$0")/valid-scan.tiff" "$wrong"
    printf '{"type":"result","width":10,"height":8,"path":"%s"}\\n' "$wrong"
    """

    static let stagedRawThenWaitPluginScript = """
    #!/bin/bash
    payload=$(cat)
    out=$(printf '%s' "$payload" | /usr/bin/plutil -extract outputPath raw -o - -)
    cp "$(dirname "$0")/valid-scan.tiff" "$out"
    while :; do sleep 0.05; done
    """

    private func assertRawArtifactRejected(
        id: String,
        script: String,
        expectedMessage: String
    ) async throws {
        let fixture = try Self.makeBackendFixture(id: id, script: script)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("scan.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:\(id):dev0")
        options.temporaryOutputURL = output

        do {
            _ = try await fixture.backend.startFullScan(options) { _ in }
            XCTFail("유효하지 않은 raw 결과를 수용했습니다: \(id)")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .ioFailure)
            XCTAssertTrue(error.message.contains(expectedMessage), error.message)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            at: fixture.root,
            includingPropertiesForKeys: nil
        ))?.filter { $0.lastPathComponent.hasPrefix(".negaflow-scan-") } ?? []
        XCTAssertTrue(leftovers.isEmpty)
    }

    private func assertInfraredArtifactRejected(
        id: String,
        script: String,
        expectedMessage: String
    ) async throws {
        let fixture = try Self.makeBackendFixture(id: id, script: script)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = fixture.root.appendingPathComponent("scan.tiff")
        var options = ScanOptions.strongDefault(scannerID: "plugin:\(id):dev0")
        options.infraredEnabled = true
        options.temporaryOutputURL = output

        do {
            _ = try await fixture.backend.startFullScan(options) { _ in }
            XCTFail("유효하지 않은 IR 결과를 수용했습니다: \(id)")
        } catch let error as ScannerError {
            XCTAssertEqual(error.code, .ioFailure)
            XCTAssertTrue(error.message.contains(expectedMessage), error.message)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path + ".ir.tiff"))
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            at: fixture.root,
            includingPropertiesForKeys: nil
        ))?.filter { $0.lastPathComponent.hasPrefix(".negaflow-scan-") } ?? []
        XCTAssertTrue(leftovers.isEmpty)
    }

    private static func makeBackendFixture(
        id: String,
        script: String
    ) throws -> (backend: ExternalScannerBackend, root: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-plugin-\(id)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executableURL = root.appendingPathComponent("fake-scanner")
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        try writeValidTIFF(to: root.appendingPathComponent("valid-scan.tiff"))
        try writeValidTIFF(
            to: root.appendingPathComponent("mismatched-scan.tiff"),
            width: 5,
            height: 4
        )
        let manifest = ScannerPluginManifest(
            schemaVersion: 1, id: id, name: "Fake \(id)", executable: "fake-scanner"
        )
        let manifestURL = root.appendingPathComponent("manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let plugin = InstalledScannerPlugin(
            manifest: manifest,
            manifestURL: manifestURL,
            executableURL: executableURL
        )
        return (ExternalScannerBackend(plugin: plugin), root)
    }

    @discardableResult
    private func writeDiscoveryFixture(
        id: String,
        executable: String,
        root: URL,
        createExecutable: Bool = true
    ) throws -> URL {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if createExecutable {
            let executableURL = directory.appendingPathComponent(executable)
            try "#!/bin/sh\nexit 0\n".write(
                to: executableURL,
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executableURL.path
            )
        }
        let manifest = ScannerPluginManifest(
            schemaVersion: 1,
            protocolVersion: 2,
            id: id,
            name: "Plugin \(id)",
            executable: executable,
            pluginVersion: "1.0"
        )
        try JSONEncoder().encode(manifest).write(
            to: directory.appendingPathComponent("manifest.json")
        )
        return directory
    }

    private static func writeValidTIFF(to url: URL, width: Int = 10, height: Int = 8) throws {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScannerError(.ioFailure, "테스트 TIFF context 생성 실패")
        }
        context.setFillColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                "public.tiff" as CFString,
                1,
                nil
              ) else {
            throw ScannerError(.ioFailure, "테스트 TIFF destination 생성 실패")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScannerError(.ioFailure, "테스트 TIFF 기록 실패")
        }
    }

    private static func waitForStagedRaw(in root: URL) async throws {
        for _ in 0..<200 {
            let entries = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
            let stagingDirectories = entries.filter { $0.lastPathComponent.hasPrefix(".negaflow-scan-") }
            for directory in stagingDirectories {
                let files = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.fileSizeKey]
                )
                if files.contains(where: { file in
                    let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
                    return (size ?? 0) > 0
                }) {
                    return
                }
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw ScannerError(.timeout, "staged raw가 생성되지 않음")
    }
}

/// scan 진행률 콜백에서 phase를 안전하게 모은다.
private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _phases: [ScanPhase] = []
    func add(_ p: ScanPhase) { lock.lock(); _phases.append(p); lock.unlock() }
    var phases: [ScanPhase] { lock.lock(); defer { lock.unlock() }; return _phases }
}
