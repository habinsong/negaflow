import Foundation

struct LibraryPhotoStack: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var frameIDs: [UUID]
    var isCollapsed: Bool

    init?(
        id: UUID = UUID(),
        frameIDs: [UUID],
        isCollapsed: Bool = true
    ) {
        var seen = Set<UUID>()
        let uniqueIDs = frameIDs.filter { seen.insert($0).inserted }
        guard uniqueIDs.count >= 2, uniqueIDs.count == frameIDs.count else { return nil }
        self.id = id
        self.frameIDs = uniqueIDs
        self.isCollapsed = isCollapsed
    }

    var coverFrameID: UUID { frameIDs[0] }
}
