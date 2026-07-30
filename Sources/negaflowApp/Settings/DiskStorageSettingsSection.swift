import AppKit
import SwiftUI

struct DiskStorageSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var cacheSizeBytes: Int64?
    @State private var isClearingCache = false
    @State private var isBackingUpLibrary = false
    @State private var showRestoreBrowser = false

    var body: some View {
        AppSettingsSection(
            title: model.text(AppLocalizedPhrase.settingsDiskTab)
        ) {
            storageLocationPicker

            pathRow(
                model.text(AppLocalizedPhrase.diskRootFolderLabel),
                url: model.diskStorage.rootURL
            ) {
                model.diskStorage.rootPath = $0
            }
            pathRow(
                model.text(AppLocalizedPhrase.diskThumbnailsFolderLabel),
                url: model.diskStorage.thumbnailsURL
            ) {
                model.diskStorage.thumbnailsPath = $0
            }
            pathRow(
                model.text(.diskImportedSourcesFolderLabel),
                url: model.diskStorage.importedSourcesURL
            ) {
                model.diskStorage.importedSourcesPath = $0
            }
            pathRow(
                model.text(.diskCleanedRawFolderLabel),
                url: model.diskStorage.cleanedRawURL
            ) {
                model.diskStorage.cleanedRawPath = $0
            }
            pathRow(
                model.text(.diskScanPreviewFolderLabel),
                url: model.diskStorage.scanPreviewsURL
            ) {
                model.diskStorage.scanPreviewsPath = $0
            }
            pathRow(
                model.text(AppLocalizedPhrase.diskExportFolderLabel),
                url: model.diskStorage.exportURL
            ) {
                model.exportFolderPath = $0
            }
            pathRow(
                model.text(.settingsQuickExportFolder),
                url: model.diskStorage.quickExportURL
            ) {
                model.quickExportFolderPath = $0
            }

            ScanStorageLocationView(store: model.diskStorage)

            if model.diskStorage.locationMode == .custom {
                Button {
                    model.diskStorage.resetToDefaults()
                    refreshCacheSize()
                } label: {
                    Label(
                        model.text(AppLocalizedPhrase.diskResetPathsButton),
                        systemImage: "arrow.counterclockwise"
                    )
                }
                .buttonStyle(.bordered)
            }
        }

        Section {
            AppSettingsRow(model.text(AppLocalizedPhrase.diskThumbnailCacheLabel)) {
                HStack(spacing: 8) {
                    Text(cacheSizeText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button(
                        model.text(AppLocalizedPhrase.diskClearThumbnailCache),
                        role: .destructive
                    ) {
                        clearCache()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isClearingCache)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .task { refreshCacheSize() }
        .onChange(of: model.diskStorage.thumbnailsPath) { _, _ in
            refreshCacheSize()
        }

        AppSettingsSection(
            title: model.text(AppLocalizedPhrase.diskLibraryBackupLabel)
        ) {
            AppSettingsValueRow(
                label: model.text(AppLocalizedPhrase.diskLibraryBackupLabel),
                value: (model.libraryBackupDirectoryURL.path as NSString)
                    .abbreviatingWithTildeInPath
            )

            ExternalBackupDestinationView(store: model.backupDestinationStore)
            LibraryBackupScheduleView(store: model.backupScheduleStore)

            backupActions
        }
    }

    private var backupActions: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    isBackingUpLibrary = true
                    defer { isBackingUpLibrary = false }
                    _ = await model.createLibraryBackupNow()
                }
            } label: {
                Text(model.text(AppLocalizedPhrase.diskLibraryBackupNow))
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(
                isBackingUpLibrary
                    || model.isLibraryMaintenanceInProgress
                    || (
                        model.backupDestinationStore.isConfigured
                            && model.backupDestinationStore.status.readyInfo == nil
                    )
            )

            Divider()
                .frame(height: 30)

            Button {
                showRestoreBrowser = true
            } label: {
                Text(model.text(AppLocalizedPhrase.diskLibraryBackupBrowse))
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(isBackingUpLibrary || model.isLibraryMaintenanceInProgress)
            .sheet(isPresented: $showRestoreBrowser) {
                LibraryRestoreBrowser()
                    .environmentObject(model)
            }

            Divider()
                .frame(height: 30)

            LibraryArchiveButton()
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var storageLocationPicker: some View {
        Picker(String(), selection: locationModeBinding) {
            ForEach(DiskStorageLocationMode.allCases, id: \.self) { mode in
                Text(locationLabel(mode)).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(model.text(AppLocalizedPhrase.settingsDiskTab))
    }

    private var locationModeBinding: Binding<DiskStorageLocationMode> {
        Binding(
            get: { model.diskStorage.locationMode },
            set: { mode in selectLocationMode(mode) }
        )
    }

    private func locationLabel(_ mode: DiskStorageLocationMode) -> String {
        switch mode {
        case .iCloud:
            model.text(.diskLocationICloud)
        case .desktop:
            model.text(.diskLocationDesktop)
        case .specificFolder:
            model.text(.diskLocationSpecificFolder)
        case .custom:
            model.text(.diskLocationCustom)
        }
    }

    private func selectLocationMode(_ mode: DiskStorageLocationMode) {
        if mode == .specificFolder {
            chooseSpecificFolder()
        } else {
            model.diskStorage.selectLocationMode(mode)
            refreshCacheSize()
        }
    }

    private func chooseSpecificFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = model.text(.choose)
        if let path = model.diskStorage.specificFolderPath, !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            panel.directoryURL = model.diskStorage.rootURL.deletingLastPathComponent()
        }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let chosen = panel.url else { return }
            Task { @MainActor in
                model.diskStorage.selectSpecificFolder(chosen)
                refreshCacheSize()
            }
        }
    }

    private var cacheSizeText: String {
        guard let cacheSizeBytes else {
            return model.text(AppLocalizedPhrase.diskCacheSizeCalculating)
        }
        return ByteCountFormatter.string(
            fromByteCount: cacheSizeBytes,
            countStyle: .file
        )
    }

    private func pathRow(
        _ title: String,
        url: URL,
        onChange: @escaping (String) -> Void
    ) -> some View {
        AppSettingsRow(title) {
            HStack(spacing: 6) {
                AppSettingsPathText(
                    text: (url.path as NSString).abbreviatingWithTildeInPath
                )

                if model.diskStorage.locationMode == .custom {
                    Button {
                        chooseFolder(startingAt: url, onChange: onChange)
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                    }
                    .buttonStyle(.bordered)
                    .help(model.text(.exportChangeFolder))
                    .accessibilityLabel(model.text(.exportChangeFolder))
                }

                Button {
                    revealInFinder(url)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .help(model.text(AppLocalizedPhrase.showInFinder))
                .accessibilityLabel(model.text(AppLocalizedPhrase.showInFinder))
            }
        }
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.open(DiskStorageStore.ensureDirectory(url))
    }

    private func chooseFolder(
        startingAt url: URL,
        onChange: @escaping (String) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = model.text(AppLocalizedPhrase.choose)
        panel.directoryURL = url
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let chosen = panel.url else { return }
            Task { @MainActor in
                onChange(chosen.path)
                refreshCacheSize()
            }
        }
    }

    private func refreshCacheSize() {
        cacheSizeBytes = nil
        Task {
            cacheSizeBytes = await model.thumbnailCacheSizeBytes()
        }
    }

    private func clearCache() {
        isClearingCache = true
        Task {
            await model.clearThumbnailCache()
            cacheSizeBytes = await model.thumbnailCacheSizeBytes()
            isClearingCache = false
        }
    }
}
