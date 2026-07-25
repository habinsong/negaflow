import XCTest
import ScannerKit
@testable import negaflowApp

final class ScannerPluginTrustWorkflowTests: XCTestCase {
    @MainActor
    func testUnapprovedAndChangedPluginsNeverLaunchUntilExplicitApproval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-app-plugin-trust-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstMarker = root.appendingPathComponent("first-launched")
        let changedMarker = root.appendingPathComponent("changed-launched")
        let pluginDirectory = try writePlugin(
            root: root,
            marker: firstMarker,
            version: "1.0"
        )
        let previousOverride = ProcessInfo.processInfo.environment["NEGAFLOW_PLUGINS_DIR"]
        setenv("NEGAFLOW_PLUGINS_DIR", root.path, 1)
        defer {
            if let previousOverride {
                setenv("NEGAFLOW_PLUGINS_DIR", previousOverride, 1)
            } else {
                unsetenv("NEGAFLOW_PLUGINS_DIR")
            }
        }
        let trustStore = ScannerPluginTrustStore(
            fileURL: root.appendingPathComponent("trust.json")
        )
        let model = AppModel(scannerPluginTrustStore: trustStore)

        await model.refreshDevices()

        let firstPlugin = try XCTUnwrap(model.installedScannerPlugins.first)
        XCTAssertEqual(model.scannerPluginApprovalState(for: firstPlugin), .approvalRequired)
        XCTAssertTrue(model.pluginBackends.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstMarker.path))
        XCTAssertEqual(
            model.statusMessage,
            model.text(AppLocalizedPhrase.scannerPluginApprovalRequiredStatus)
        )

        await model.approveScannerPlugin(firstPlugin)

        XCTAssertEqual(model.scannerPluginApprovalState(for: firstPlugin), .approved)
        let approvedRediscovery = try XCTUnwrap(model.installedScannerPlugins.first)
        XCTAssertEqual(model.scannerPluginApprovalState(for: approvedRediscovery), .approved)
        XCTAssertEqual(model.pluginBackends.map { $0.plugin.id }, [firstPlugin.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstMarker.path))

        try pluginScript(marker: changedMarker).write(
            to: pluginDirectory.appendingPathComponent("plugin-tool"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: pluginDirectory.appendingPathComponent("plugin-tool").path
        )
        await model.refreshDevices()

        let changedPlugin = try XCTUnwrap(model.installedScannerPlugins.first)
        XCTAssertEqual(model.scannerPluginApprovalState(for: changedPlugin), .identityChanged)
        XCTAssertTrue(model.pluginBackends.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: changedMarker.path))
    }

    private func writePlugin(root: URL, marker: URL, version: String) throws -> URL {
        let directory = root.appendingPathComponent("test-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("plugin-tool")
        try pluginScript(marker: marker).write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let manifest = ScannerPluginManifest(
            schemaVersion: 1,
            protocolVersion: 2,
            id: "test-plugin",
            name: "Test Scanner Plug-in",
            executable: "plugin-tool",
            license: "MIT",
            pluginVersion: version
        )
        try JSONEncoder().encode(manifest).write(
            to: directory.appendingPathComponent("manifest.json")
        )
        return directory
    }

    private func pluginScript(marker: URL) -> String {
        """
        #!/bin/sh
        touch '\(marker.path)'
        if [ "$1" = "detect" ]; then
          printf '{"devices":[]}'
          exit 0
        fi
        exit 2
        """
    }
}
