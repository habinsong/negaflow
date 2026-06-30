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
            Picker("History", selection: $selectedEntryID) {
                if frame.developHistory.isEmpty {
                    Text("No history").tag(UUID?.none)
                } else {
                    ForEach(frame.developHistory.reversed()) { entry in
                        Text(entry.label).tag(entry.id as UUID?)
                    }
                }
            }
            .disabled(frame.developHistory.isEmpty)

            HStack(spacing: 8) {
                TransferButton(
                    title: "Record",
                    systemName: "record.circle",
                    help: "현재 현상 상태를 History로 기록"
                ) {
                    selectedEntryID = model.recordDevelopHistory(for: frame)
                }

                TransferButton(
                    title: "Apply",
                    systemName: "arrow.uturn.backward",
                    help: "선택한 History 상태 적용",
                    isDisabled: selectedEntry == nil
                ) {
                    guard let selectedEntry else { return }
                    model.applyDevelopHistory(selectedEntry, to: frame)
                }
            }
        } header: {
            sectionHeader("History", systemImage: "clock.arrow.circlepath")
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
