import SwiftUI
import AppKit

// MARK: - 설정 > 디스크 탭
//
// 썸네일/내보내기/빠른 내보내기 저장 경로 관리 + 썸네일 캐시 크기 확인/지우기.
// 루트를 바꾸면 개별 경로를 지정하지 않은 폴더들이 함께 따라간다(nil = 루트에서 파생).
struct DiskStorageSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var cacheSizeBytes: Int64?
    @State private var isClearingCache = false
    @State private var isBackingUpLibrary = false
    @State private var showRestoreBrowser = false

    var body: some View {
        Section {
            storageLocationPicker
            pathRow(model.text(AppLocalizedPhrase.diskRootFolderLabel), url: model.diskStorage.rootURL) {
                model.diskStorage.rootPath = $0
            }
            pathRow(model.text(AppLocalizedPhrase.diskThumbnailsFolderLabel), url: model.diskStorage.thumbnailsURL) {
                model.diskStorage.thumbnailsPath = $0
            }
            pathRow(model.text(.diskImportedSourcesFolderLabel), url: model.diskStorage.importedSourcesURL) {
                model.diskStorage.importedSourcesPath = $0
            }
            pathRow(model.text(.diskCleanedRawFolderLabel), url: model.diskStorage.cleanedRawURL) {
                model.diskStorage.cleanedRawPath = $0
            }
            pathRow(model.text(.diskScanPreviewFolderLabel), url: model.diskStorage.scanPreviewsURL) {
                model.diskStorage.scanPreviewsPath = $0
            }
            pathRow(model.text(AppLocalizedPhrase.diskExportFolderLabel), url: model.diskStorage.exportURL) {
                model.exportFolderPath = $0
            }
            pathRow(model.text(.settingsQuickExportFolder), url: model.diskStorage.quickExportURL) {
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
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }

        Section {
            LabeledContent(model.text(AppLocalizedPhrase.diskThumbnailCacheLabel)) {
                Text(cacheSizeText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button(role: .destructive) {
                clearCache()
            } label: {
                Text(model.text(AppLocalizedPhrase.diskClearThumbnailCache))
            }
            .disabled(isClearingCache)
        }
        .task { refreshCacheSize() }
        .onChange(of: model.diskStorage.thumbnailsPath) { _, _ in refreshCacheSize() }

        Section {
            LabeledContent(model.text(AppLocalizedPhrase.diskLibraryBackupLabel)) {
                Text((model.libraryBackupDirectoryURL.path as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            ExternalBackupDestinationView(store: model.backupDestinationStore)
            LibraryBackupScheduleView(store: model.backupScheduleStore)
            Button(model.text(AppLocalizedPhrase.diskLibraryBackupNow)) {
                Task {
                    isBackingUpLibrary = true
                    defer { isBackingUpLibrary = false }
                    _ = await model.createLibraryBackupNow()
                }
            }
            .disabled(
                isBackingUpLibrary
                    || model.isLibraryMaintenanceInProgress
                    || (model.backupDestinationStore.isConfigured
                        && model.backupDestinationStore.status.readyInfo == nil)
            )
            Button(model.text(AppLocalizedPhrase.diskLibraryBackupBrowse)) {
                showRestoreBrowser = true
            }
            .disabled(isBackingUpLibrary || model.isLibraryMaintenanceInProgress)
            LibraryArchiveButton()
        }
        .sheet(isPresented: $showRestoreBrowser) {
            LibraryRestoreBrowser()
                .environmentObject(model)
        }
    }

    private var storageLocationPicker: some View {
        HStack(spacing: 3) {
            ForEach(DiskStorageLocationMode.allCases, id: \.self) { mode in
                let isSelected = model.diskStorage.locationMode == mode
                Button {
                    selectLocationMode(mode)
                } label: {
                    Text(locationLabel(mode))
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(AppTypography.minimumScaleFactor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.background)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(locationLabel(mode))
                .accessibilitySelectionState(
                    isSelected,
                    selectedValue: model.accessibilityText(.selected),
                    unselectedValue: model.accessibilityText(.notSelected),
                    unselectedHint: model.accessibilityText(.select)
                )
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        }
    }

    private func locationLabel(_ mode: DiskStorageLocationMode) -> String {
        switch mode {
        case .iCloud:
            return model.text(.diskLocationICloud)
        case .desktop:
            return model.text(.diskLocationDesktop)
        case .specificFolder:
            return model.text(.diskLocationSpecificFolder)
        case .custom:
            return model.text(.diskLocationCustom)
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
        sizeText(cacheSizeBytes)
    }

    private func sizeText(_ bytes: Int64?) -> String {
        guard let bytes else {
            return model.text(AppLocalizedPhrase.diskCacheSizeCalculating)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func pathRow(_ title: String, url: URL, onChange: @escaping (String) -> Void) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text((url.path as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.diskStorage.locationMode == .custom {
                    Button {
                        chooseFolder(startingAt: url, onChange: onChange)
                    } label: {
                        Label(model.text(.exportChangeFolder), systemImage: "folder.badge.gearshape")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .fixedSize()
                }
                Button {
                    revealInFinder(url)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(model.text(AppLocalizedPhrase.showInFinder))
                .accessibilityLabel(model.text(AppLocalizedPhrase.showInFinder))
            }
        }
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.open(DiskStorageStore.ensureDirectory(url))
    }

    private func chooseFolder(startingAt url: URL, onChange: @escaping (String) -> Void) {
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
