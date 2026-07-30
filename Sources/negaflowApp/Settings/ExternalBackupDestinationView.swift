import SwiftUI
import AppKit

struct ExternalBackupDestinationView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: LibraryBackupDestinationStore

    var body: some View {
        Group {
            AppSettingsRow(localized(.title)) {
                HStack(spacing: 6) {
                    if let path = store.configuredPath {
                        AppSettingsPathText(
                            text: (path as NSString).abbreviatingWithTildeInPath
                        )
                    } else {
                        Spacer(minLength: 0)
                    }

                    Button(
                        localized(store.isConfigured ? .change : .choose),
                        action: chooseDestination
                    )
                    .buttonStyle(.bordered)

                    if store.isConfigured {
                        Button(localized(.remove)) {
                            model.clearExternalBackupDestination()
                        }
                        .buttonStyle(.bordered)

                        Button {
                            model.refreshExternalBackupDestinationStatus()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help(localized(.refresh))
                        .accessibilityLabel(localized(.refresh))
                    }
                }
            }

            statusRow

            AppSettingsValueRow(
                label: localized(.lastSuccess),
                value: lastSuccessText
            )
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Label(statusText, systemImage: statusIcon)
                .foregroundStyle(statusColor)
            Spacer(minLength: 8)
            if let info = statusVolumeInfo {
                Text(capacityText(info))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { model.refreshExternalBackupDestinationStatus() }
    }

    private var statusText: String {
        switch store.status {
        case .notConfigured: localized(.notConfigured)
        case .disconnected: localized(.disconnected)
        case .sameVolume: localized(.sameVolume)
        case .readOnly: localized(.readOnly)
        case .insufficientCapacity: localized(.insufficient)
        case let .ready(info): "\(localized(.ready)) · \(info.name)"
        }
    }

    private var statusIcon: String {
        switch store.status {
        case .ready: "externaldrive.fill.badge.checkmark"
        case .notConfigured: "externaldrive"
        case .disconnected: "externaldrive.badge.xmark"
        case .sameVolume, .readOnly, .insufficientCapacity: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        store.status.readyInfo == nil ? .secondary : .green
    }

    private var statusVolumeInfo: LibraryBackupVolumeInfo? {
        switch store.status {
        case let .ready(info), let .sameVolume(info), let .readOnly(info): info
        case let .insufficientCapacity(info, _): info
        case .notConfigured, .disconnected: nil
        }
    }

    private var lastSuccessText: String {
        guard let date = store.lastSuccessAt else { return localized(.never) }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    private func capacityText(_ info: LibraryBackupVolumeInfo) -> String {
        let available = ByteCountFormatter.string(fromByteCount: info.availableBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: info.totalBytes, countStyle: .file)
        return "\(localized(.capacity))  \(available) / \(total)"
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = localized(.choose)
        panel.directoryURL = store.configuredURL
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in model.configureExternalBackupDestination(url) }
        }
    }

    private func localized(_ text: ExternalBackupLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}
