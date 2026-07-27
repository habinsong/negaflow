import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {

    // MARK: detection
    func refreshDevicesOnStartup() async {
        guard !didRunStartupScannerCheck else { return }
        didRunStartupScannerCheck = true
        let plugins = await Self.discoverScannerPlugins()
        installedScannerPlugins = plugins
        guard !plugins.isEmpty else {
            statusMessage = text(AppLocalizedPhrase.scannerPluginMissingStartImportStatus)
            return
        }
        let approvedPlugins = approvedScannerPlugins
        pluginBackends = approvedPlugins.map { ExternalScannerBackend(plugin: $0) }
        if !scannerPluginsRequiringApproval.isEmpty {
            presentScannerSetup()
        }
        guard !approvedPlugins.isEmpty else {
            statusMessage = text(AppLocalizedPhrase.scannerPluginApprovalRequiredStatus)
            return
        }
        let conflicts = runningExternalScannerAppConflicts()
        guard conflicts.isEmpty else {
            warnScannerAppConflict(conflicts)
            return
        }
        await refreshDevices(discoveredPlugins: plugins)
    }

    func refreshDevices() async {
        await refreshDevices(discoveredPlugins: nil)
    }

    private func refreshDevices(
        discoveredPlugins: [InstalledScannerPlugin]?
    ) async {
        guard !isScanning, !isDetecting else { return }
        isDetecting = true
        defer { isDetecting = false }
        // 설치된 스캐너 플러그인을 발견하고, 각 플러그인에서 장치를 조회한다.
        // negaflow 자체엔 스캐너 코드가 없다 — 전부 외부 프로세스 플러그인이 담당한다.
        let plugins: [InstalledScannerPlugin]
        if let discoveredPlugins {
            plugins = discoveredPlugins
        } else {
            plugins = await Self.discoverScannerPlugins()
        }
        installedScannerPlugins = plugins
        let approvedPlugins = approvedScannerPlugins
        pluginBackends = approvedPlugins.map { ExternalScannerBackend(plugin: $0) }
        if !scannerPluginsRequiringApproval.isEmpty {
            presentScannerSetup()
        }
        if !approvedPlugins.isEmpty {
            let conflicts = runningExternalScannerAppConflicts()
            guard conflicts.isEmpty else {
                warnScannerAppConflict(conflicts)
                return
            }
        }
        let backends = pluginBackends
        let detected = await withTaskGroup(
            of: (Int, [ScannerDescriptor]).self,
            returning: [(Int, [ScannerDescriptor])].self
        ) { group in
            for (index, backend) in backends.enumerated() {
                group.addTask {
                    (index, (try? await backend.detectScanners()) ?? [])
                }
            }
            var results: [(Int, [ScannerDescriptor])] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }
        }
        devices = detected.flatMap(\.1)
        if hasConnectedScanner {
            presentScannerSetup()
        }
        if demoMode {
            if !demoScannerDevices.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = Self.mockDeviceID
            }
            await loadCapabilities()
        } else if !scannerDevices.isEmpty {
            if selectedDeviceID == nil || !scannerDevices.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = scannerDevices.first?.id
            }
            await loadCapabilities()
        } else {
            selectedDeviceID = nil
            capabilities = nil
            selectedHardwareScanArea = nil
        }
        if !isScanning {
            statusMessage = demoMode ? text(AppLocalizedPhrase.demoModeStatus)
                : (!scannerDevices.isEmpty ? text(AppLocalizedPhrase.scanProgressReady)
                   : (!scannerPluginsRequiringApproval.isEmpty
                        ? text(AppLocalizedPhrase.scannerPluginApprovalRequiredStatus)
                        : (hasApprovedScannerPlugin
                            ? text(AppLocalizedPhrase.scannerWaitingStatus)
                            : text(AppLocalizedPhrase.scannerPluginMissingStartImportStatus))))
        }
    }

    func scannerPluginApprovalState(
        for plugin: InstalledScannerPlugin
    ) -> ScannerPluginApprovalState {
        scannerPluginTrustStore?.approvalState(for: plugin) ?? .storeUnavailable
    }

    func approveScannerPlugin(_ plugin: InstalledScannerPlugin) async {
        guard !isScanning, let scannerPluginTrustStore else {
            statusMessage = text(AppLocalizedPhrase.scannerPluginTrustStoreUnavailableStatus)
            return
        }
        do {
            try scannerPluginTrustStore.approve(plugin)
            let plugins = await Self.discoverScannerPlugins()
            installedScannerPlugins = plugins
            pluginBackends = scannerPluginTrustStore
                .approvedPlugins(from: plugins)
                .map { ExternalScannerBackend(plugin: $0) }
            statusMessage = text(AppLocalizedPhrase.scannerPluginApprovedStatus)
            await refreshDevices(discoveredPlugins: plugins)
        } catch {
            statusMessage = text(AppLocalizedPhrase.scannerPluginApprovalFailedStatus)
        }
    }

    func revokeScannerPluginApproval(_ plugin: InstalledScannerPlugin) async {
        guard !isScanning, let scannerPluginTrustStore else {
            statusMessage = text(AppLocalizedPhrase.scannerPluginTrustStoreUnavailableStatus)
            return
        }
        do {
            try scannerPluginTrustStore.revoke(pluginID: plugin.id)
            let plugins = await Self.discoverScannerPlugins()
            installedScannerPlugins = plugins
            devices.removeAll { device in
                device.id.hasPrefix("plugin:\(plugin.id):")
            }
            pluginBackends.removeAll { $0.plugin.id == plugin.id }
            if selectedDeviceID?.hasPrefix("plugin:\(plugin.id):") == true {
                selectedDeviceID = nil
                capabilities = nil
                selectedHardwareScanArea = nil
            }
            statusMessage = text(AppLocalizedPhrase.scannerPluginApprovalRevokedStatus)
            await refreshDevices(discoveredPlugins: plugins)
        } catch {
            statusMessage = text(AppLocalizedPhrase.scannerPluginApprovalFailedStatus)
        }
    }

    static func scannerAppConflicts(in runningApplicationTokens: [String]) -> [String] {
        let tokens = runningApplicationTokens.map { $0.lowercased() }
        var conflicts: [String] = []
        if tokens.contains(where: { $0.contains("silverfast") }) {
            conflicts.append("SilverFast")
        }
        if tokens.contains(where: { $0.contains("vuescan") }) {
            conflicts.append("VueScan")
        }
        return conflicts
    }

    private func runningExternalScannerAppConflicts() -> [String] {
        let tokens = NSWorkspace.shared.runningApplications.flatMap { app in
            [app.localizedName, app.bundleIdentifier, app.executableURL?.lastPathComponent].compactMap { $0 }
        }
        return Self.scannerAppConflicts(in: tokens)
    }

    private func warnScannerAppConflict(_ conflicts: [String]) {
        devices = []
        selectedDeviceID = nil
        capabilities = nil
        scanPhase = .scannerBusy
        statusMessage = text(AppLocalizedPhrase.scannerAppConflictWarningFormat, conflicts.joined(separator: ", "))
    }

    private nonisolated static func discoverScannerPlugins() async -> [InstalledScannerPlugin] {
        await Task.detached(priority: .utility) {
            ScannerPluginHost.discover()
        }.value
    }

    func toggleDemo(_ on: Bool) {
        demoMode = on
        if on {
            presentScannerSetup()
            selectedDeviceID = Self.mockDeviceID
            statusMessage = text(AppLocalizedPhrase.demoModeStatus)
        } else {
            selectedDeviceID = scannerDevices.first?.id
            statusMessage = !scannerDevices.isEmpty ? text(AppLocalizedPhrase.scanProgressReady)
                : (!scannerPluginsRequiringApproval.isEmpty
                    ? text(AppLocalizedPhrase.scannerPluginApprovalRequiredStatus)
                    : (hasApprovedScannerPlugin
                        ? text(AppLocalizedPhrase.scannerWaitingStatus)
                        : text(AppLocalizedPhrase.scannerPluginMissingStatus)))
        }
        Task { await loadCapabilities() }
    }

    func setScannerSimulatorIncludesPerforation(_ includesPerforation: Bool) {
        guard demoMode, !isScanning, scanFrameFormat.is35mm else { return }
        let shouldRefreshPreview = actionableFrame?.isPreviewScan == true
        scannerSimulatorIncludesPerforation = includesPerforation
        (mockBackend as? MockScannerBackend)?
            .setSimulatorIncludesPerforation(includesPerforation)
        resetFlatbedPreviewState()
        if shouldRefreshPreview {
            Task { await runScan(preview: true) }
        }
    }

    func setScannerSimulatorFrameOrientation(_ orientation: FilmFrameOrientation) {
        guard demoMode, !isScanning, usesFlatbedRegionWorkflow else { return }
        let shouldRefreshPreview = actionableFrame?.isPreviewScan == true
        scannerSimulatorFrameOrientation = orientation
        (mockBackend as? MockScannerBackend)?.setSimulatorFrameOrientation(orientation)
        resetFlatbedPreviewState()
        if shouldRefreshPreview {
            Task { await runScan(preview: true) }
        }
    }

    func setScannerSimulatorFrameCount(_ count: Int) {
        guard demoMode, !isScanning, usesFlatbedRegionWorkflow else { return }
        let shouldRefreshPreview = actionableFrame?.isPreviewScan == true
        scannerSimulatorFrameCount = min(max(count, 1), 48)
        (mockBackend as? MockScannerBackend)?.setSimulatorFrameCount(
            scannerSimulatorFrameCount
        )
        resetFlatbedPreviewState()
        if shouldRefreshPreview {
            Task { await runScan(preview: true) }
        }
    }

    func presentScannerSetup() {
        showScannerControls = true
    }


}
