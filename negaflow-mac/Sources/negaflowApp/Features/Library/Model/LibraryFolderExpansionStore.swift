import Combine
import Foundation

@MainActor
final class LibraryFolderExpansionStore: ObservableObject {
    static let defaultsKey = "library.collapsedFolderIDs"

    @Published private(set) var collapsedFolderIDs: Set<String>

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        collapsedFolderIDs = Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    func isExpanded(_ folderID: String) -> Bool {
        !collapsedFolderIDs.contains(folderID)
    }

    func toggle(_ folderID: String) {
        if collapsedFolderIDs.contains(folderID) {
            collapsedFolderIDs.remove(folderID)
        } else {
            collapsedFolderIDs.insert(folderID)
        }
        defaults.set(collapsedFolderIDs.sorted(), forKey: Self.defaultsKey)
    }
}
