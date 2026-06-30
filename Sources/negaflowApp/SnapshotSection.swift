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
            Picker("Snapshot", selection: $selectedSnapshotID) {
                if frame.developSnapshots.isEmpty {
                    Text("No snapshots").tag(UUID?.none)
                } else {
                    ForEach(frame.developSnapshots) { snapshot in
                        Text(snapshot.name).tag(snapshot.id as UUID?)
                    }
                }
            }
            .disabled(frame.developSnapshots.isEmpty)

            HStack(spacing: 8) {
                TransferButton(
                    title: "Save",
                    systemName: "camera.aperture",
                    help: "현재 현상 상태를 Snapshot으로 저장"
                ) {
                    selectedSnapshotID = model.saveSnapshot(for: frame)
                }

                TransferButton(
                    title: "Apply",
                    systemName: "arrow.down.doc",
                    help: "선택한 Snapshot 적용",
                    isDisabled: selectedSnapshot == nil
                ) {
                    guard let selectedSnapshot else { return }
                    model.applySnapshot(selectedSnapshot, to: frame)
                }

                TransferButton(
                    title: isComparingSelectedSnapshot ? "Current" : "A/B",
                    systemName: "rectangle.split.2x1",
                    help: "현재 설정과 선택한 Snapshot 임시 비교",
                    isDisabled: selectedSnapshot == nil
                ) {
                    guard let selectedSnapshot else { return }
                    model.toggleSnapshotCompare(selectedSnapshot, for: frame)
                }
            }
        } header: {
            sectionHeader("Snapshot", systemImage: "camera.aperture")
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
