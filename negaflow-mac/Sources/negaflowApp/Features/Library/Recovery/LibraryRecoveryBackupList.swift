import SwiftUI

struct LibraryRecoveryBackupList: View {
    @EnvironmentObject private var model: AppModel
    let isLoading: Bool
    let loadFailed: Bool
    let generations: [LibraryBackupGeneration]
    @Binding var selectedID: String?

    @ViewBuilder
    var body: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed {
            ContentUnavailableView(
                model.text(AppLocalizedPhrase.libraryBackupLoadFailed),
                systemImage: "exclamationmark.triangle"
            )
        } else if generations.isEmpty {
            ContentUnavailableView {
                Label(
                    model.text(AppLocalizedPhrase.libraryBackupEmpty),
                    systemImage: "archivebox"
                )
            } description: {
                Text(
                    AppLocalization.libraryRecoveryText(
                        .noBackupsHint,
                        language: model.appLanguage
                    )
                )
            }
        } else {
            List(generations, selection: $selectedID) { generation in
                LibraryBackupGenerationRow(generation: generation)
                    .tag(generation.id)
                    .disabled(!generation.state.isRestorable)
                    .help(
                        generation.state.isRestorable
                            ? ""
                            : AppLocalization.libraryRecoveryText(
                                .unusableBackupHint,
                                language: model.appLanguage
                            )
                    )
            }
        }
    }
}
