import ScannerKit
import SwiftUI

struct ScannerPluginTrustRows: View {
    @EnvironmentObject private var model: AppModel
    let plugins: [InstalledScannerPlugin]

    var body: some View {
        ForEach(plugins) { plugin in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(plugin.name, systemImage: stateSymbol(plugin))
                        .font(.callout.weight(.medium))
                    Spacer(minLength: 8)
                    Text(stateLabel(plugin))
                        .font(.caption)
                        .foregroundStyle(stateColor(plugin))
                }

                AppSettingsValueRow(
                    label: model.text(AppLocalizedPhrase.scannerPluginVersion),
                    value: plugin.manifest.pluginVersion
                        ?? model.text(AppLocalizedPhrase.scannerPluginNotReported)
                )
                AppSettingsValueRow(
                    label: model.text(AppLocalizedPhrase.scannerPluginLicense),
                    value: plugin.manifest.license
                        ?? model.text(AppLocalizedPhrase.scannerPluginNotReported)
                )
                technicalRow(
                    model.text(AppLocalizedPhrase.scannerPluginManifestPath),
                    value: plugin.manifestURL.path
                )
                if let identity = plugin.trustIdentity {
                    technicalRow(
                        model.text(AppLocalizedPhrase.scannerPluginManifestHash),
                        value: identity.manifestSHA256
                    )
                    technicalRow(
                        model.text(AppLocalizedPhrase.scannerPluginExecutableHash),
                        value: identity.executableSHA256
                    )
                }

                AppSettingsRow(stateLabel(plugin)) {
                    if model.scannerPluginApprovalState(for: plugin) == .approved {
                        Button(
                            model.text(AppLocalizedPhrase.scannerPluginRevokeApproval),
                            role: .destructive
                        ) {
                            Task { await model.revokeScannerPluginApproval(plugin) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isScanning)
                    } else {
                        Button(model.text(AppLocalizedPhrase.scannerPluginApprove)) {
                            Task { await model.approveScannerPlugin(plugin) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            model.isScanning
                                || model.scannerPluginApprovalState(for: plugin) == .invalidIdentity
                                || model.scannerPluginApprovalState(for: plugin) == .storeUnavailable
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func technicalRow(_ label: String, value: String) -> some View {
        AppSettingsRow(label) {
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
    }

    private func stateLabel(_ plugin: InstalledScannerPlugin) -> String {
        switch model.scannerPluginApprovalState(for: plugin) {
        case .approved:
            model.text(AppLocalizedPhrase.scannerPluginApproved)
        case .approvalRequired:
            model.text(AppLocalizedPhrase.scannerPluginApprovalRequired)
        case .identityChanged:
            model.text(AppLocalizedPhrase.scannerPluginChangedApprovalRequired)
        case .invalidIdentity:
            model.text(AppLocalizedPhrase.scannerPluginInvalidIdentity)
        case .storeUnavailable:
            model.text(AppLocalizedPhrase.scannerPluginTrustStoreUnavailable)
        }
    }

    private func stateSymbol(_ plugin: InstalledScannerPlugin) -> String {
        switch model.scannerPluginApprovalState(for: plugin) {
        case .approved: "checkmark.shield"
        case .approvalRequired, .identityChanged: "exclamationmark.shield"
        case .invalidIdentity, .storeUnavailable: "xmark.shield"
        }
    }

    private func stateColor(_ plugin: InstalledScannerPlugin) -> Color {
        switch model.scannerPluginApprovalState(for: plugin) {
        case .approved: .secondary
        case .approvalRequired, .identityChanged: .orange
        case .invalidIdentity, .storeUnavailable: .red
        }
    }
}
