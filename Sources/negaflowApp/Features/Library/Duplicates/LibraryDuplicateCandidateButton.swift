import SwiftUI

struct LibraryDuplicateCandidateButton: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var scanModel = LibraryDuplicateCandidateScanModel()
    let orderedFrameIDs: [UUID]

    var body: some View {
        Button(action: startScan) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 27, height: 24)
        }
        .buttonStyle(.plain)
        .liquidSurface(cornerRadius: 8, interactive: true)
        .help(model.duplicateText(.find))
        .accessibilityLabel(model.duplicateText(.find))
        .disabled(scanModel.isScanning)
        .sheet(isPresented: $scanModel.isPresented) {
            LibraryDuplicateCandidateSheet(
                scanModel: scanModel,
                onSelect: selectGroup
            )
            .environmentObject(model)
        }
    }

    private func startScan() {
        let framesByID = model.uniqueLibraryFramesByID()
        let inputs = orderedFrameIDs.compactMap { id -> LibraryDuplicateCandidateInput? in
            guard let frame = framesByID[id], !frame.isVirtualCopy else { return nil }
            return LibraryDuplicateCandidateInput(frameID: id, sourceURL: frame.rawScanURL)
        }
        scanModel.start(inputs: inputs)
    }

    private func selectGroup(_ frameIDs: [UUID]) {
        let available = Set(model.interactionFrameIDs)
        let selected = frameIDs.filter(available.contains)
        guard !selected.isEmpty else { return }
        model.selectedFrameIDs = Set(selected)
        model.frameSelectionAnchorID = selected[0]
        model.activateFrame(selected.last)
        scanModel.dismiss()
    }
}
