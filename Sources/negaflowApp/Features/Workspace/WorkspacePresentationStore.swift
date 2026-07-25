import Combine
import Foundation

@MainActor
final class WorkspacePresentationStore: ObservableObject {
    private enum Keys {
        static let module = "workspace.module"
        static let sidebarTab = "workspace.sidebarTab"
        static let searchText = "workspace.librarySearchText"
        static let activeFrameID = "workspace.activeFrameID"
    }

    private let defaults: UserDefaults

    @Published var module: WorkspaceModule {
        didSet { defaults.set(module.rawValue, forKey: Keys.module) }
    }

    @Published var sidebarTab: WorkflowSidebarTab {
        didSet { defaults.set(sidebarTab.rawValue, forKey: Keys.sidebarTab) }
    }

    @Published var searchText: String {
        didSet { defaults.set(Self.normalizedSearchText(searchText), forKey: Keys.searchText) }
    }

    @Published private(set) var activeFrameID: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        module = defaults.string(forKey: Keys.module)
            .flatMap(WorkspaceModule.init(rawValue:)) ?? .develop
        sidebarTab = defaults.string(forKey: Keys.sidebarTab)
            .flatMap(WorkflowSidebarTab.init(rawValue:)) ?? .library
        searchText = Self.normalizedSearchText(
            defaults.string(forKey: Keys.searchText) ?? ""
        )
        activeFrameID = defaults.string(forKey: Keys.activeFrameID).flatMap(UUID.init(uuidString:))
    }

    func recordActiveFrameID(_ id: UUID?) {
        activeFrameID = id
        if let id {
            defaults.set(id.uuidString, forKey: Keys.activeFrameID)
        } else {
            defaults.removeObject(forKey: Keys.activeFrameID)
        }
    }

    func restorableActiveFrameID(
        availableFrameIDs: Set<UUID>,
        sourceAvailableFrameIDs: Set<UUID>
    ) -> UUID? {
        guard let activeFrameID,
              availableFrameIDs.contains(activeFrameID),
              sourceAvailableFrameIDs.contains(activeFrameID) else {
            return nil
        }
        return activeFrameID
    }

    func discardStaleActiveFrame() {
        recordActiveFrameID(nil)
    }

    private static func normalizedSearchText(_ value: String) -> String {
        String(value.prefix(512))
    }
}
