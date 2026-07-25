import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

struct SourceDeletionPlan: Identifiable {
    struct Group {
        let sourceURL: URL
        let frameIDs: Set<UUID>
        let infraredURLs: [URL]
    }

    let id = UUID()
    let groups: [Group]

    var frameCount: Int { Set(groups.flatMap(\.frameIDs)).count }
    var sourceCount: Int { groups.count }
    var firstSourcePath: String { groups.first?.sourceURL.path ?? "" }
}

struct LibraryRemovalRecord {
    struct Entry {
        let index: Int
        let frame: ScanFrame
    }

    struct FolderEntry {
        let index: Int
        let folder: LibraryFolder
    }

    let entries: [Entry]
    let folderEntries: [FolderEntry]
    let selectedFrameIDs: Set<UUID>
    let selectedFrameID: UUID?
    let selectionAnchorID: UUID?
    let rollRemovalDelta: RollMembershipRemovalDelta
    let stackRemovalDelta: LibraryStackRemovalDelta
    let manualCollectionMemberships: [LibraryManualCollectionMembershipPosition]

    var frameIDs: Set<UUID> { Set(entries.map { $0.frame.id }) }
    var folderIDs: Set<UUID> { Set(folderEntries.map { $0.folder.id }) }
    /// 현재 폴더 제거 호출은 단일 폴더와 그 안의 프레임을 함께 전달한다. 프레임이 있으면 사진 수를,
    /// 빈 폴더만 제거하면 폴더 수를 보고해 둘을 중복 합산하지 않는다.
    var statusItemCount: Int { entries.isEmpty ? folderEntries.count : entries.count }
}
