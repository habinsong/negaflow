import Combine
import Foundation

@MainActor
final class LibraryFolderExpansionStore: ObservableObject {
    nonisolated static let defaultsKey = "library.collapsedFolderIDs"
    /// 사진 격자의 접힘은 파일 목록의 접힘과 따로 기억한다. 같은 폴더라도 사이드바에서는
    /// 파일 이름을 펼쳐 두고 격자에서는 썸네일을 접어 두는 쪽이 흔한 쓰임이다.
    nonisolated static let gridDefaultsKey = "library.grid.collapsedFolderIDs"

    @Published private(set) var collapsedFolderIDs: Set<String>

    private let defaults: UserDefaults
    private let defaultsKey: String

    init(defaults: UserDefaults = .standard, defaultsKey: String = LibraryFolderExpansionStore.defaultsKey) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        collapsedFolderIDs = Set(defaults.stringArray(forKey: defaultsKey) ?? [])
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
        defaults.set(collapsedFolderIDs.sorted(), forKey: defaultsKey)
    }
}
