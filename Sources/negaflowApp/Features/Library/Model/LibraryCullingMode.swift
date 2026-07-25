import Foundation

enum LibraryCullingMode: String, CaseIterable, Identifiable {
    case grid
    case compare
    case survey

    var id: Self { self }

    private static let systemImages: [Self: String] = [
        .grid: "square.grid.2x2",
        .compare: "rectangle.split.2x1",
        .survey: "rectangle.grid.3x2",
    ]

    var systemImage: String { Self.systemImages[self] ?? "photo" }
}

enum LibraryCullingProjection {
    static func selectedFrameIDs(
        orderedFrameIDs: [UUID],
        selectedFrameIDs: Set<UUID>
    ) -> [UUID] {
        var seen = Set<UUID>()
        return orderedFrameIDs.filter {
            selectedFrameIDs.contains($0) && seen.insert($0).inserted
        }
    }

    static func compareFrameIDs(
        orderedFrameIDs: [UUID],
        selectedFrameIDs: Set<UUID>,
        activeFrameID: UUID?
    ) -> [UUID] {
        let selected = Self.selectedFrameIDs(
            orderedFrameIDs: orderedFrameIDs,
            selectedFrameIDs: selectedFrameIDs
        )
        guard selected.count >= 2 else { return [] }

        let candidateID = activeFrameID.flatMap { selected.contains($0) ? $0 : nil }
            ?? selected[1]
        guard let referenceID = selected.first(where: { $0 != candidateID }) else { return [] }
        return [referenceID, candidateID]
    }
}
