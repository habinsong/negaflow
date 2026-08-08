import SwiftUI
import Chromabase

@MainActor
final class LocalAdjustmentSession: ObservableObject {
    @Published var activeFrameID: UUID?
    @Published var selectedAdjustmentID: UUID?
    @Published var maskKind: LocalDodgeBurnMask.Kind = .brush {
        didSet { polygonPoints.removeAll() }
    }
    @Published var mode: LocalDodgeBurnMode = .dodge
    @Published var amount = 0.35
    @Published var feather = 0.20
    @Published var brushThickness = 0.04
    @Published var polygonPoints: [LocalDodgeBurnPoint] = []

    private(set) var copiedAdjustment: LocalDodgeBurnAdjustment?

    func isActive(for frame: ScanFrame) -> Bool {
        activeFrameID == frame.id
    }

    func activate(for frame: ScanFrame) {
        activeFrameID = frame.id
        selectedAdjustmentID = frame.params.localDodgeBurn.last?.id
    }

    func deactivate() {
        activeFrameID = nil
        polygonPoints.removeAll()
    }

    func copy(_ adjustment: LocalDodgeBurnAdjustment) {
        copiedAdjustment = adjustment
    }

    func pastedAdjustment() -> LocalDodgeBurnAdjustment? {
        guard var copy = copiedAdjustment else { return nil }
        copy.id = UUID()
        return copy
    }

    func makeAdjustment(mask: LocalDodgeBurnMask) -> LocalDodgeBurnAdjustment {
        LocalDodgeBurnAdjustment(mode: mode, amount: amount, mask: mask)
    }
}
