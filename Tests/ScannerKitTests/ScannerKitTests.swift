import XCTest
import Foundation
@testable import ScannerKit

// negaflow(Apache-2.0)의 ScannerKit 테스트. SANE 관련 테스트는 GPL 분리로 인해 외부
// 플러그인 패키지(negaflow-scanner-sane)로 이관되었다. 여기서는 라이센스-중립 코어와
// 외부 프로세스 플러그인 계약(발견 + JSON/CLI 매핑)만 검증한다.
final class ScannerKitTests: XCTestCase {
    func testScanOptionsStrongDefault() {
        let o = ScanOptions.strongDefault(scannerID: "plugin:sane:test")
        XCTAssertEqual(o.resolution, .r3600)
        XCTAssertEqual(o.bitDepth, .sixteen)
        XCTAssertEqual(o.colorMode, .color)
        XCTAssertEqual(o.filmType, .colorNegative)
        XCTAssertFalse(o.infraredEnabled)   // plan §4.2 IR off 기본
    }

    func testCapabilitiesGate() {
        let cap = ScannerCapabilities()
        XCTAssertTrue(cap.supports(resolution: .r7200))
        XCTAssertFalse(cap.supports(resolution: Resolution(4800)))
        XCTAssertTrue(cap.supports(depth: .sixteen))
        XCTAssertTrue(cap.supports(mode: .color))
    }

    func testBackendTypeFromScannerID() {
        XCTAssertEqual(BackendType(fromScannerID: "plugin:sane:genesys:libusb:000:010"), .plugin)
        XCTAssertEqual(BackendType(fromScannerID: "sane-genesys:libusb:000:010"), .sane)
        XCTAssertEqual(BackendType(fromScannerID: "ica-xyz"), .imageCaptureCore)
        XCTAssertEqual(BackendType(fromScannerID: "mock-1"), .mock)
    }

    func testScannerReportSerialization() throws {
        let d = ScannerDescriptor(id: "plugin:sane:x", displayName: "Plustek OpticFilm 8200i",
                                  vendor: "Plustek", model: "OpticFilm 8200i",
                                  backendType: .plugin, verifiedStatus: .verified)
        let r = ScannerReport(descriptor: d, backend: .plugin,
                              backendAvailable: true, capabilities: ScannerCapabilities())
        let data = try JSONEncoder().encode(r)
        XCTAssertGreaterThan(data.count, 50)
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

        // scan → NDJSON 진행률 이벤트가 전달되고, result 가 ScanResult 로 매핑된다.
        let output = ScanTempFile.makeURL(prefix: "fake_scan", suffix: ".tiff")
        defer { try? FileManager.default.removeItem(at: output) }
        var opts = ScanOptions.strongDefault(scannerID: device.id)
        opts.temporaryOutputURL = output
        let progressPhases = ProgressCollector()
        let result = try await backend.startFullScan(opts) { p in progressPhases.add(p.phase) }
        XCTAssertEqual(result.rawFileURL.path, output.path)
        XCTAssertEqual(result.width, 10)
        XCTAssertEqual(result.height, 8)
        XCTAssertEqual(result.backendUsed, .plugin)
        XCTAssertTrue(progressPhases.phases.contains(.scanningRGB))
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
        echo '{"devices":[{"id":"dev0","displayName":"Fake Scanner","vendor":"Test","model":"T1","connectionType":"usb","verifiedStatus":"experimental"}]}'
        ;;
      capabilities)
        echo '{"resolutionsDPI":[3600,7200],"modes":["color","gray"],"bitDepths":[8,16],"supportsInfrared":false}'
        ;;
      scan)
        payload=$(cat)
        out=$(printf '%s' "$payload" | sed -n 's/.*"outputPath":"\\([^"]*\\)".*/\\1/p')
        : > "$out"
        echo '{"type":"progress","phase":"scanningRGB","fraction":0.5,"message":"scanning"}'
        printf '{"type":"result","width":10,"height":8,"path":"%s","resolutionDPI":3600,"bitDepth":16}\\n' "$out"
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
}

/// scan 진행률 콜백에서 phase를 안전하게 모은다.
private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _phases: [ScanPhase] = []
    func add(_ p: ScanPhase) { lock.lock(); _phases.append(p); lock.unlock() }
    var phases: [ScanPhase] { lock.lock(); defer { lock.unlock() }; return _phases }
}
