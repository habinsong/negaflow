import Chromabase
import Foundation

extension AppModel {
    func makeSupportBundleDocument() async -> SupportBundleDocument {
        let hasher = SupportBundlePrivacyHasher()
        let catalog = currentLibraryCatalogSnapshot()
        let lifecycle = libraryLifecycleState.diagnosticCode
        let blockReason = libraryCatalogBlockReason?.diagnosticCode
        let fallbackFrameCount = frames.lazy.filter { !$0.isPreviewScan }.count
        let fallbackRollCount = rolls.count
        let defectDirectory = libraryDefectDirectoryURL
        let backupDirectory = libraryBackupDirectoryURL
        let scanURL = diskStorage.scansURL
        let thumbnailURL = diskStorage.thumbnailsURL
        let cleanedRawURL = diskStorage.cleanedRawURL
        let catalogURL = libraryCatalogURL
        let plugins = supportBundlePluginSummaries(hasher: hasher)
        let scanner = supportBundleScannerSummary()
        let thumbnailBytes = await thumbnailCacheSizeBytes()
        let cacheCounts = (
            residentCleanedRawIDs.count,
            residentDevelopedIDs.count,
            maxResidentCleanedRaw,
            maxResidentDeveloped
        )
        let backup = SupportBundleBackupSummary(
            schedule: backupScheduleStore.schedule.rawValue,
            externalDestinationConfigured: backupDestinationStore.isConfigured,
            lastAttemptAt: backupScheduleStore.lastAttemptAt,
            lastSuccessAt: backupScheduleStore.lastSuccessAt,
            lastRestoreDrillSucceeded: backupScheduleStore.lastRestoreDrill?.succeeded,
            generations: []
        )
        let recentErrors = Array(
            AppDiagnostics.recentEvents.lazy.filter { $0.phase == .error }.suffix(100)
        )

        let io = await Task.detached(priority: .utility) {
            let catalogSummary = SupportBundleSummaries.catalog(
                lifecycle: lifecycle,
                blockReason: blockReason,
                catalog: catalog,
                fallbackFrameCount: fallbackFrameCount,
                fallbackRollCount: fallbackRollCount,
                defectDirectory: defectDirectory
            )
            let generations = SupportBundleSummaries.generations(in: backupDirectory)
            let cleanedRawBytes = DiskStorageStore.directorySize(
                at: cleanedRawURL
            )
            let scanKind = ScanStorageLocationInspector.inspect(scanURL).kind
            return (catalogSummary, generations, cleanedRawBytes, scanKind)
        }.value

        return SupportBundleDocument(
            schemaVersion: SupportBundleDocument.currentSchemaVersion,
            generatedAt: Date(),
            redactionPolicy: "omit_paths_names_metadata; salted_sha256_identifiers",
            app: SupportBundleAppSummary(
                version: NegaflowProductVersion.applicationVersion(),
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                architecture: Self.supportBundleArchitecture,
                activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
            ),
            locations: SupportBundleLocationSummary(
                catalogHash: hasher.hash(catalogURL.standardizedFileURL.path),
                scanOriginalsHash: hasher.hash(scanURL.standardizedFileURL.path),
                thumbnailCacheHash: hasher.hash(thumbnailURL.standardizedFileURL.path),
                scanStorageKind: io.3 == .cloudManaged ? "cloudManaged" : "local"
            ),
            catalog: io.0,
            backup: SupportBundleBackupSummary(
                schedule: backup.schedule,
                externalDestinationConfigured: backup.externalDestinationConfigured,
                lastAttemptAt: backup.lastAttemptAt,
                lastSuccessAt: backup.lastSuccessAt,
                lastRestoreDrillSucceeded: backup.lastRestoreDrillSucceeded,
                generations: io.1
            ),
            cache: SupportBundleCacheSummary(
                thumbnailBytes: thumbnailBytes,
                cleanedRawBytes: io.2,
                residentCleanedRawCount: cacheCounts.0,
                residentDevelopedCount: cacheCounts.1,
                maxResidentCleanedRaw: cacheCounts.2,
                maxResidentDeveloped: cacheCounts.3
            ),
            plugins: plugins,
            scanner: scanner,
            recentErrors: recentErrors
        )
    }

    func exportSupportBundle(to destination: URL) async throws {
        let document = await makeSupportBundleDocument()
        try await Task.detached(priority: .utility) {
            try SupportBundleArchiveWriter.write(document, to: destination)
        }.value
    }

    private func supportBundlePluginSummaries(
        hasher: SupportBundlePrivacyHasher
    ) -> [SupportBundlePluginSummary] {
        installedScannerPlugins.map { plugin in
            SupportBundlePluginSummary(
                pluginIDHash: hasher.hash(plugin.manifest.id),
                pluginVersion: plugin.manifest.pluginVersion,
                schemaVersion: plugin.manifest.schemaVersion,
                protocolVersion: plugin.manifest.resolvedProtocolVersion,
                supportedByHost: plugin.manifest.isSupportedByHost,
                approvalState: scannerPluginApprovalState(for: plugin).supportBundleCode,
                manifestSHA256: plugin.trustIdentity?.manifestSHA256,
                executableSHA256: plugin.trustIdentity?.executableSHA256
            )
        }
    }

    private func supportBundleScannerSummary() -> SupportBundleScannerSummary? {
        capabilities.map {
            SupportBundleScannerSummary(
                resolutionsDPI: $0.supportedResolutions.map(\.dpi).sorted(),
                modes: $0.supportedModes.map(\.rawValue).sorted(),
                bitDepths: $0.supportedBitDepths.map(\.rawValue).sorted(),
                supportsPreview: $0.supportsPreview,
                supportsTransparency: $0.supportsTransparency,
                supportsInfrared: $0.supportsInfrared,
                supportsMultiExposure: $0.supportsMultiExposure,
                supportsScanArea: $0.supportsScanArea
            )
        }
    }

    private static var supportBundleArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}
