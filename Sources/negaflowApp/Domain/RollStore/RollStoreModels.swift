import Combine
import Foundation
import Chromabase

struct RollStoreSnapshot: Equatable {
    let rolls: [LibraryRoll]
    let activeRollID: UUID?
}

struct RollMembershipRemovalDelta: Equatable {
    struct Entry: Equatable {
        let frameID: UUID
        let rollID: UUID
        let membershipIndex: Int
        let sourceRollCreatedAt: Date
    }

    struct RemovedUnassignedRoll: Equatable {
        let createdAt: Date
        let rollIndex: Int
    }

    let entries: [Entry]
    let removedUnassignedRoll: RemovedUnassignedRoll?
}
