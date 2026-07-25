import Combine
import Foundation

struct LibraryStackRemovalDelta: Equatable {
    struct Change: Equatable {
        let index: Int
        let before: LibraryPhotoStack
        let after: LibraryPhotoStack?
    }

    let changes: [Change]
}

@MainActor
final class StackStore: ObservableObject {
    @Published private(set) var stacks: [LibraryPhotoStack] = []

    func replace(with stacks: [LibraryPhotoStack]) {
        self.stacks = stacks
    }

    func stack(containing frameID: UUID) -> LibraryPhotoStack? {
        let matches = stacks.filter { $0.frameIDs.contains(frameID) }
        return matches.count == 1 ? matches[0] : nil
    }

    @discardableResult
    func create(frameIDs: [UUID], isCollapsed: Bool = true) -> LibraryPhotoStack? {
        guard frameIDs.allSatisfy({ stack(containing: $0) == nil }),
              let stack = LibraryPhotoStack(
                  frameIDs: frameIDs,
                  isCollapsed: isCollapsed
              ) else { return nil }
        stacks.append(stack)
        return stack
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        guard let index = uniqueIndex(id: id) else { return false }
        stacks.remove(at: index)
        return true
    }

    @discardableResult
    func toggleCollapsed(id: UUID) -> Bool {
        guard let index = uniqueIndex(id: id) else { return false }
        stacks[index].isCollapsed.toggle()
        return true
    }

    func projectedFrameIDs(_ orderedFrameIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        let ordered = orderedFrameIDs.filter { seen.insert($0).inserted }
        let order = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1, $0) })
        var hidden = Set<UUID>()

        for stack in stacks where stack.isCollapsed {
            let visibleMembers = stack.frameIDs
                .filter { order[$0] != nil }
                .sorted { order[$0, default: .max] < order[$1, default: .max] }
            hidden.formUnion(visibleMembers.dropFirst())
        }
        return ordered.filter { !hidden.contains($0) }
    }

    func removalDelta(for frameIDs: Set<UUID>) -> LibraryStackRemovalDelta {
        let changes = stacks.enumerated().compactMap {
            index, stack -> LibraryStackRemovalDelta.Change? in
            guard stack.frameIDs.contains(where: frameIDs.contains) else { return nil }
            let remaining = stack.frameIDs.filter { !frameIDs.contains($0) }
            let after = LibraryPhotoStack(
                id: stack.id,
                frameIDs: remaining,
                isCollapsed: stack.isCollapsed
            )
            return .init(index: index, before: stack, after: after)
        }
        return LibraryStackRemovalDelta(changes: changes)
    }

    func removeFrameIDs(_ frameIDs: Set<UUID>) {
        guard !frameIDs.isEmpty else { return }
        stacks = stacks.compactMap { stack in
            LibraryPhotoStack(
                id: stack.id,
                frameIDs: stack.frameIDs.filter { !frameIDs.contains($0) },
                isCollapsed: stack.isCollapsed
            )
        }
    }

    @discardableResult
    func restore(_ delta: LibraryStackRemovalDelta) -> Bool {
        guard canRestore(delta) else { return false }
        for change in delta.changes.sorted(by: { $0.index < $1.index }) {
            if let index = stacks.firstIndex(where: { $0.id == change.before.id }) {
                stacks[index] = change.before
            } else {
                stacks.insert(change.before, at: min(change.index, stacks.count))
            }
        }
        return true
    }

    private func canRestore(_ delta: LibraryStackRemovalDelta) -> Bool {
        let restoringFrameIDs = Set(delta.changes.flatMap { change in
            let afterIDs = Set(change.after?.frameIDs ?? [])
            return change.before.frameIDs.filter { !afterIDs.contains($0) }
        })
        guard stacks.allSatisfy({ stack in
            stack.frameIDs.allSatisfy { !restoringFrameIDs.contains($0) }
        }) else { return false }

        return delta.changes.allSatisfy { change in
            let matches = stacks.filter { $0.id == change.before.id }
            if let after = change.after {
                return matches == [after]
            }
            return matches.isEmpty
        }
    }

    private func uniqueIndex(id: UUID) -> Int? {
        let matches = stacks.indices.filter { stacks[$0].id == id }
        return matches.count == 1 ? matches[0] : nil
    }
}
