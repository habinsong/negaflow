import SwiftUI
import Chromabase

struct SnapshotSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @State private var selectedSnapshotID: UUID?

    var selectedSnapshot: DevelopSnapshot? {
        guard let selectedSnapshotID else { return frame.developSnapshots.last }
        return frame.developSnapshots.first(where: { $0.id == selectedSnapshotID }) ?? frame.developSnapshots.last
    }

    var isComparingSelectedSnapshot: Bool {
        guard let selectedSnapshot else { return false }
        return model.snapshotCompareState?.frameID == frame.id
            && model.snapshotCompareState?.snapshotID == selectedSnapshot.id
    }

    var body: some View {
        Section {
            Picker(model.text(AppLocalizedPhrase.snapshot), selection: $selectedSnapshotID) {
                if frame.developSnapshots.isEmpty {
                    Text(model.text(AppLocalizedPhrase.noSnapshots)).tag(UUID?.none)
                } else {
                    ForEach(frame.developSnapshots) { snapshot in
                        Text(snapshot.name).tag(snapshot.id as UUID?)
                    }
                }
            }
            .disabled(frame.developSnapshots.isEmpty)

            HStack(spacing: 8) {
                TransferButton(
                    title: model.text(AppLocalizedPhrase.save),
                    systemName: "camera.aperture",
                    help: model.text(AppLocalizedPhrase.saveSnapshotHelp)
                ) {
                    selectedSnapshotID = model.saveSnapshot(for: frame)
                }

                TransferButton(
                    title: model.text(AppLocalizedPhrase.apply),
                    systemName: "arrow.down.doc",
                    help: model.text(AppLocalizedPhrase.applySnapshotHelp),
                    isDisabled: selectedSnapshot == nil
                ) {
                    guard let selectedSnapshot else { return }
                    model.applySnapshot(selectedSnapshot, to: frame)
                }

                TransferButton(
                    title: isComparingSelectedSnapshot ? model.text(AppLocalizedPhrase.current) : "A/B",
                    systemName: "rectangle.split.2x1",
                    help: model.text(AppLocalizedPhrase.compareSnapshotHelp),
                    isDisabled: selectedSnapshot == nil
                ) {
                    guard let selectedSnapshot else { return }
                    model.toggleSnapshotCompare(selectedSnapshot, for: frame)
                }
            }
        } header: {
            sectionHeader(model.text(AppLocalizedPhrase.snapshot), systemImage: "camera.aperture")
        }
        .onAppear { ensureSelection() }
        .onChange(of: frame.developSnapshots.map(\.id)) { _, _ in ensureSelection() }
    }

    func ensureSelection() {
        if let selectedSnapshotID,
           frame.developSnapshots.contains(where: { $0.id == selectedSnapshotID }) {
            return
        }
        selectedSnapshotID = frame.developSnapshots.last?.id
    }
}

extension DevelopSnapshot {
    var sidecarRecord: Sidecar.DevelopSnapshotRecord {
        Sidecar.DevelopSnapshotRecord(
            id: id.uuidString,
            name: name,
            createdAt: createdAt,
            presetID: presetID,
            parameters: params
        )
    }
}
