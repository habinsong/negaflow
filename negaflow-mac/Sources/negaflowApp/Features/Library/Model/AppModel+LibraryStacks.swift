import Foundation

extension AppModel {
    var stacks: [LibraryPhotoStack] { stackStore.stacks }

    func stack(containing frameID: UUID) -> LibraryPhotoStack? {
        stackStore.stack(containing: frameID)
    }

    func stackProjectedFrameIDs(_ orderedFrameIDs: [UUID]) -> [UUID] {
        stackStore.projectedFrameIDs(orderedFrameIDs)
    }

    @discardableResult
    func createStack(frameIDs: [UUID]) -> LibraryPhotoStack? {
        guard allowsLibraryMutation else { return nil }
        let availableIDs = Set(frames.lazy.filter { !$0.isPreviewScan }.map(\.id))
        var seen = Set<UUID>()
        let orderedIDs = frameIDs.filter {
            availableIDs.contains($0) && seen.insert($0).inserted
        }
        let stack = stackStore.create(frameIDs: orderedIDs)
        if stack != nil {
            updateInteractionScope(stackProjectedFrameIDs(interactionFrameIDs))
        }
        return stack
    }

    @discardableResult
    func ungroupStack(id: UUID) -> Bool {
        guard allowsLibraryMutation else { return false }
        let changed = stackStore.remove(id: id)
        if changed {
            updateInteractionScope(stackProjectedFrameIDs(interactionFrameIDs))
        }
        return changed
    }

    @discardableResult
    func toggleStackCollapsed(id: UUID) -> Bool {
        guard allowsLibraryMutation else { return false }
        let changed = stackStore.toggleCollapsed(id: id)
        if changed {
            updateInteractionScope(stackProjectedFrameIDs(interactionFrameIDs))
        }
        return changed
    }
}
