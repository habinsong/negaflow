import Foundation
import ScannerKit

@MainActor
enum AppModelFactory {
    static func make(configuration: AppLaunchConfiguration? = .current) -> AppModel {
        guard let configuration else { return AppModel() }

        let root = configuration.uiTestRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        UITestDiskFixturePreparer.prepare(configuration)
        let defaults = isolatedDefaults(for: root)
        let diskStorage = DiskStorageStore(defaults: defaults)
        diskStorage.rootPath = root.appendingPathComponent("Storage", isDirectory: true).path
        diskStorage.exportPath = root.appendingPathComponent("Exports", isDirectory: true).path
        diskStorage.quickExportPath = root.appendingPathComponent("QuickExports", isDirectory: true).path
        diskStorage.scansPath = root.appendingPathComponent("Scans", isDirectory: true).path
        diskStorage.importedSourcesPath = root.appendingPathComponent("Imported Originals", isDirectory: true).path
        diskStorage.cleanedRawPath = root.appendingPathComponent("Caches/Cleaned Raw", isDirectory: true).path
        diskStorage.scanPreviewsPath = root.appendingPathComponent("Caches/Scan Previews", isDirectory: true).path

        let demoBackend = MockScannerBackend()
        demoBackend.sampleNegativesDir = demoSampleDirectory(
            for: configuration,
            root: root
        )
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            exportRecipeStore: ExportRecipeStore(
                url: root.appendingPathComponent("export-recipes.json")
            ),
            presentationPreferencesStore: PresentationPreferencesStore(defaults: defaults),
            workflowShortcutStore: WorkflowShortcutStore(defaults: defaults),
            diskStorageStore: diskStorage,
            backupDestinationStore: LibraryBackupDestinationStore(defaults: defaults),
            backupScheduleStore: LibraryBackupScheduleStore(defaults: defaults),
            scannerDemoBackend: demoBackend,
            scannerPluginTrustStore: nil,
            libraryCatalogURL: root.appendingPathComponent("Library/catalog.sqlite"),
            libraryDefectDirectoryURL: root.appendingPathComponent("Library/Defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("Library/Backups", isDirectory: true)
        )
        model.appLanguage = .english
        model.demoMode = configuration.enablesDemoScanner
        if configuration.enablesDemoScanner {
            model.selectedDeviceID = AppModel.mockDeviceID
            model.showScannerControls = true
        }
        return model
    }

    static func makeWorkspacePresentationStore(
        configuration: AppLaunchConfiguration? = .current
    ) -> WorkspacePresentationStore {
        guard let configuration else { return WorkspacePresentationStore() }
        return WorkspacePresentationStore(
            defaults: isolatedDefaults(for: configuration.uiTestRoot)
        )
    }

    private static func isolatedDefaults(for root: URL) -> UserDefaults {
        let identifier = root.path.data(using: .utf8)?.base64EncodedString() ?? UUID().uuidString
        let safeIdentifier = identifier
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "+", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return UserDefaults(suiteName: "com.negaflow.ui-tests.\(safeIdentifier)")!
    }

    private static func demoSampleDirectory(
        for configuration: AppLaunchConfiguration,
        root: URL
    ) -> URL? {
        guard configuration.enablesDemoScanner else { return nil }
        let directory = root.appendingPathComponent("Fixtures/Demo", isDirectory: true)
        let sample = directory.appendingPathComponent("raw_3600_16bit.tiff")
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try MockScannerBackend.writeSyntheticNegative(width: 640, height: 480, to: sample)
            return directory
        } catch {
            return nil
        }
    }
}
