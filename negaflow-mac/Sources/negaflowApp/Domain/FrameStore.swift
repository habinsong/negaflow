import Combine
import Foundation

@MainActor
final class FrameStore: ObservableObject {
    @Published var frames: [ScanFrame] = [] {
        didSet { repairSelectionAfterFramesChanged() }
    }
    @Published var selectedFrameID: UUID?

    var selectedFrame: ScanFrame? {
        guard let id = selectedFrameID else { return nil }
        return frames.first { $0.id == id }
    }

    private func repairSelectionAfterFramesChanged() {
        guard let id = selectedFrameID else { return }
        if frames.contains(where: { $0.id == id }) { return }
        selectedFrameID = frames.last?.id
    }
}
