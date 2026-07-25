import SwiftUI

struct ExportBatchProgressView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: ExportBatchStore

    var body: some View {
        if !store.items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(
                        model.text(
                            AppLocalizedPhrase.batchFrameProgressFormat,
                            store.finishedCount,
                            store.items.count
                        )
                    )
                    Spacer()
                    if store.failedCount > 0 {
                        Label {
                            Text(verbatim: "\(store.failedCount)")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .foregroundStyle(.orange)
                    }
                }
                ProgressView(
                    value: Double(store.finishedCount),
                    total: Double(max(store.items.count, 1))
                )
                controls
            }
            .controlSize(.small)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if store.isRunning {
                Button {
                    store.isPaused ? model.resumeExportBatch() : model.pauseExportBatch()
                } label: {
                    Label(
                        localized(store.isPaused ? .resume : .pause),
                        systemImage: store.isPaused ? "play.fill" : "pause.fill"
                    )
                }
                Button(localized(.cancel), role: .cancel) {
                    model.cancelExportBatch()
                }
                .disabled(store.isCancellationRequested)
            } else if !store.retryableItemIDs.isEmpty {
                Button(localized(.retryFailed)) {
                    model.retryFailedExportBatchItems()
                }
            }
        }
        .buttonStyle(.borderless)
    }

    private func localized(_ text: BatchExportLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}
