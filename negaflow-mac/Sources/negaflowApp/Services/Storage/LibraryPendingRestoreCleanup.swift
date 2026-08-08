import Foundation

struct LibraryPendingRestoreCleanup {
    typealias Remover = (URL) throws -> Void

    let removeDirectory: Remover
    let removeMarker: Remover

    static func fileSystem(fileManager: FileManager) -> Self {
        Self(
            removeDirectory: { try fileManager.removeItem(at: $0) },
            removeMarker: { try fileManager.removeItem(at: $0) }
        )
    }

    /// 적용된 snapshot directory를 먼저 치우고 marker를 마지막 durable fence로 지운다.
    /// 어느 단계든 실패하면 marker를 남겨 다음 시작 때 cleanup만 재시도한다.
    func run(
        marker: LibraryPendingRestoreMarker,
        catalogURL: URL,
        fileManager: FileManager
    ) -> Bool {
        let pendingDirectory = LibraryPendingRestoreStore.defaultDirectoryURL(for: catalogURL)
            .appendingPathComponent(marker.directoryName, isDirectory: true)
        do {
            if fileManager.fileExists(atPath: pendingDirectory.path) {
                try removeDirectory(pendingDirectory)
            }
            let markerURL = LibraryPendingRestoreStore.markerURL(for: catalogURL)
            if fileManager.fileExists(atPath: markerURL.path) {
                try removeMarker(markerURL)
            }
            return true
        } catch {
            return false
        }
    }
}
