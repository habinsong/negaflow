import Foundation

struct InfraredCleanSessionToken: Equatable {
    fileprivate let ownerID: ObjectIdentifier
    fileprivate let frameID: UUID
    fileprivate let revision: UInt64
}

private struct InfraredCleanSessionKey: Hashable {
    let ownerID: ObjectIdentifier
    let frameID: UUID
}

@MainActor
enum InfraredCleanSessionRegistry {
    private static var nextRevision: UInt64 = 0
    private static var currentRevisions: [InfraredCleanSessionKey: UInt64] = [:]
    private static var tasks: [InfraredCleanSessionKey: Task<Void, Never>] = [:]

    static func begin(owner: AppModel, frameID: UUID) -> InfraredCleanSessionToken {
        let key = InfraredCleanSessionKey(ownerID: ObjectIdentifier(owner), frameID: frameID)
        tasks.removeValue(forKey: key)?.cancel()
        nextRevision += 1
        currentRevisions[key] = nextRevision
        return InfraredCleanSessionToken(
            ownerID: key.ownerID,
            frameID: frameID,
            revision: nextRevision
        )
    }

    static func install(_ task: Task<Void, Never>, for token: InfraredCleanSessionToken) {
        guard isCurrent(token) else {
            task.cancel()
            return
        }
        tasks[key(for: token)] = task
    }

    static func isCurrent(_ token: InfraredCleanSessionToken) -> Bool {
        currentRevisions[key(for: token)] == token.revision
    }

    static func finish(_ token: InfraredCleanSessionToken) {
        let key = key(for: token)
        guard currentRevisions[key] == token.revision else { return }
        currentRevisions.removeValue(forKey: key)
        tasks.removeValue(forKey: key)
    }

    static func cancel(owner: AppModel, frameID: UUID) {
        let key = InfraredCleanSessionKey(ownerID: ObjectIdentifier(owner), frameID: frameID)
        currentRevisions.removeValue(forKey: key)
        tasks.removeValue(forKey: key)?.cancel()
    }

    private static func key(for token: InfraredCleanSessionToken) -> InfraredCleanSessionKey {
        InfraredCleanSessionKey(ownerID: token.ownerID, frameID: token.frameID)
    }
}
