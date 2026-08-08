import SwiftUI
import Chromabase

struct DevelopHistorySection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @State private var selectedEntryID: UUID?

    var selectedEntry: DevelopHistoryEntry? {
        guard let selectedEntryID else { return frame.developHistory.last }
        return frame.developHistory.first(where: { $0.id == selectedEntryID }) ?? frame.developHistory.last
    }

    var body: some View {
        Section {
            Picker(model.text(AppLocalizedPhrase.history), selection: $selectedEntryID) {
                if frame.developHistory.isEmpty {
                    Text(model.text(AppLocalizedPhrase.noHistory)).tag(UUID?.none)
                } else {
                    ForEach(frame.developHistory.reversed()) { entry in
                        Text(entry.label).tag(entry.id as UUID?)
                    }
                }
            }
            .disabled(frame.developHistory.isEmpty)

            HStack(spacing: 8) {
                TransferButton(
                    title: model.text(AppLocalizedPhrase.record),
                    systemName: "record.circle",
                    help: model.text(AppLocalizedPhrase.recordHistoryHelp)
                ) {
                    selectedEntryID = model.recordDevelopHistory(for: frame)
                }

                TransferButton(
                    title: model.text(AppLocalizedPhrase.apply),
                    systemName: "arrow.uturn.backward",
                    help: model.text(AppLocalizedPhrase.applyHistoryHelp),
                    isDisabled: selectedEntry == nil
                ) {
                    guard let selectedEntry else { return }
                    model.applyDevelopHistory(selectedEntry, to: frame)
                }
            }
        } header: {
            sectionHeader(model.text(AppLocalizedPhrase.history), systemImage: "clock.arrow.circlepath")
        }
        .onAppear { ensureSelection() }
        .onChange(of: frame.developHistory.map(\.id)) { _, _ in ensureSelection() }
    }

    func ensureSelection() {
        if let selectedEntryID,
           frame.developHistory.contains(where: { $0.id == selectedEntryID }) {
            return
        }
        selectedEntryID = frame.developHistory.last?.id
    }
}
