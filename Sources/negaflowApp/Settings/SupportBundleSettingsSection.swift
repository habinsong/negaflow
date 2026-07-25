import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SupportBundleSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var isExporting = false
    @State private var resultText: String?

    var body: some View {
        Section {
            LabeledContent(localized(.title)) {
                Button(localized(isExporting ? .creating : .export), action: presentSavePanel)
                    .disabled(isExporting)
            }
            if let resultText {
                Text(resultText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func presentSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFileName
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await export(to: url) }
        }
    }

    private func export(to url: URL) async {
        isExporting = true
        resultText = nil
        defer { isExporting = false }
        do {
            try await model.exportSupportBundle(to: url)
            resultText = localized(.complete)
        } catch {
            resultText = localized(.failed)
        }
    }

    private var defaultFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return ["negaflow-support-", formatter.string(from: Date()), ".zip"].joined()
    }

    private func localized(_ key: SupportBundleLocalizedText) -> String {
        key.resolved(language: model.appLanguage)
    }
}
