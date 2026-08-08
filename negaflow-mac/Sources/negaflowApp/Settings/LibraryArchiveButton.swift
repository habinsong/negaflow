import AppKit
import SwiftUI

struct LibraryArchiveButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var isCreating = false

    var body: some View {
        Button {
            presentSavePanel()
        } label: {
            Text(model.archiveText(.create))
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .disabled(isCreating || model.isLibraryMaintenanceInProgress)
    }

    private func presentSavePanel() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "negaflow Library.negaflowarchive"
        panel.prompt = model.archiveText(.save)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in
                isCreating = true
                defer { isCreating = false }
                _ = await model.createLibraryArchive(at: destination)
            }
        }
    }
}
