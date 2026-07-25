import SwiftUI
import AppKit

struct ExternalBackupDestinationView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: LibraryBackupDestinationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(localized(.title)).font(.callout.weight(.semibold))
                Spacer()
                Button(localized(store.isConfigured ? .change : .choose), action: chooseDestination)
                    .controlSize(.small)
                if store.isConfigured {
                    Button(localized(.remove)) { model.clearExternalBackupDestination() }
                        .controlSize(.small)
                    Button { model.refreshExternalBackupDestinationStatus() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .help(localized(.refresh))
                    .accessibilityLabel(localized(.refresh))
                }
            }
            if let path = store.configuredPath {
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Label(statusText, systemImage: statusIcon)
                .font(.caption)
                .foregroundStyle(statusColor)
            if let info = statusVolumeInfo {
                Text(capacityText(info))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LabeledContent(localized(.lastSuccess)) {
                Text(lastSuccessText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
