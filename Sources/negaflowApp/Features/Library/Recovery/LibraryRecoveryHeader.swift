import SwiftUI

struct LibraryRecoveryHeader: View {
    @EnvironmentObject private var model: AppModel
    let reason: String
    let catalogPath: String
    let isWorking: Bool
    let copiedDiagnostics: Bool
    let retry: () -> Void
    let reveal: () -> Void
    let copyDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized(.title))
                        .font(.headline)
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Text(verbatim: catalogPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                Button(action: retry) {
                    Label(localized(.retry), systemImage: "arrow.clockwise")
                }
                .disabled(isWorking)

                Button(action: reveal) {
                    Label(localized(.revealInFinder), systemImage: "folder")
                }
                .help(catalogPath)

                Spacer()

                Button(action: copyDiagnostics) {
                    Label(
                        localized(.copyDiagnostics),
                        systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc"
                    )
                }
            }
        }
    }

    private func localized(_ key: LibraryRecoveryLocalizedText) -> String {
        AppLocalization.libraryRecoveryText(key, language: model.appLanguage)
    }
}
