import AppKit
import SwiftUI

struct ScanStorageLocationView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: DiskStorageStore
    @State private var status: ScanStorageLocationStatus?

    var body: some View {
        Group {
            AppSettingsRow(localized(.originals)) {
                HStack(spacing: 6) {
                    AppSettingsPathText(
                        text: (store.scansURL.path as NSString).abbreviatingWithTildeInPath
                    )
                    if store.locationMode == .custom {
                        Button(action: chooseFolder) {
                            Image(systemName: "folder.badge.gearshape")
                        }
                        .buttonStyle(.bordered)
                        .help(localized(.change))
                        .accessibilityLabel(localized(.change))
                    }
                    Button {
                        NSWorkspace.shared.open(DiskStorageStore.ensureDirectory(store.scansURL))
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .help(model.text(AppLocalizedPhrase.showInFinder))
                    .accessibilityLabel(model.text(AppLocalizedPhrase.showInFinder))
                }
            }

            AppSettingsValueRow(
                label: localized(.estimatedAvailable),
                value: capacityText
            )

            AppSettingsRow(localized(.storage)) {
                Label(storageText, systemImage: storageIcon)
                    .foregroundStyle(.secondary)
            }
        }
        .task { refresh() }
        .onChange(of: store.scansPath) { _, _ in refresh() }
        .onChange(of: store.locationMode) { _, _ in refresh() }
        .onChange(of: store.specificFolderPath) { _, _ in refresh() }
        .onChange(of: store.rootPath) { _, _ in refresh() }
    }

    private var capacityText: String {
        guard let bytes = status?.availableCapacityBytes else {
            return localized(.unavailable)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var storageText: String {
        status?.kind == .cloudManaged ? localized(.cloudManaged) : localized(.local)
    }

    private var storageIcon: String {
        status?.kind == .cloudManaged ? "icloud" : "internaldrive"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = localized(.change)
        panel.directoryURL = store.scansURL
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in store.scansPath = url.path }
        }
    }

    private func refresh() {
        status = ScanStorageLocationInspector.inspect(store.scansURL)
    }

    private func localized(_ key: ScanStorageLocalizedText) -> String {
        key.resolved(language: model.appLanguage)
    }
}
