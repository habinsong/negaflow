import ScannerKit

extension AppModel {
    var backend: ScannerBackend? {
        if demoMode { return mockBackend }
        guard let id = effectiveScannerID else { return nil }
        return pluginBackends.first(where: { $0.owns(scannerID: id) })
    }

    var scannerDevices: [ScannerDescriptor] {
        devices.filter { $0.backendType == .plugin }
    }

    var demoScannerDevices: [ScannerDescriptor] {
        MockScannerBackend.scannerDescriptors
    }

    var selectableScannerDevices: [ScannerDescriptor] {
        demoMode ? demoScannerDevices : scannerDevices
    }

    var hasScannerPlugin: Bool { !installedScannerPlugins.isEmpty }

    var approvedScannerPlugins: [InstalledScannerPlugin] {
        guard let scannerPluginTrustStore else { return [] }
        return scannerPluginTrustStore.approvedPlugins(from: installedScannerPlugins)
    }

    var scannerPluginsRequiringApproval: [InstalledScannerPlugin] {
        installedScannerPlugins.filter { scannerPluginApprovalState(for: $0) != .approved }
    }

    var hasApprovedScannerPlugin: Bool { !approvedScannerPlugins.isEmpty }
    var hasConnectedScanner: Bool { !scannerDevices.isEmpty }
    var hasScanner: Bool { backend != nil }

    var hasUsableScanCapabilities: Bool {
        guard let capabilities else { return false }
        return capabilities.supportedResolutions.contains(where: { $0.dpi > 0 })
            && capabilities.supportedModes.contains(where: { $0 == .color || $0 == .gray })
            && !capabilities.supportedBitDepths.isEmpty
    }

    var canScan: Bool {
        allowsLibraryMutation && hasScanner && hasUsableScanCapabilities && !isScanning
    }

    var canPreview: Bool { canScan && capabilities?.supportsPreview == true }

    var effectiveScannerID: String? {
        if demoMode {
            return demoScannerDevices.first(where: { $0.id == selectedDeviceID })?.id
                ?? Self.mockDeviceID
        }
        return scannerDevices.first(where: { $0.id == selectedDeviceID })?.id
            ?? scannerDevices.first?.id
    }

    var activeScannerDisplayName: String {
        return selectableScannerDevices.first(where: { $0.id == effectiveScannerID })?.displayName
            ?? selectableScannerDevices.first?.displayName
            ?? text(AppLocalizedPhrase.noScannerStatus)
    }
}
