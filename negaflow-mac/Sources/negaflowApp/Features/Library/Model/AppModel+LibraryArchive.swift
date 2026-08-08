import Foundation

extension AppModel {
    @discardableResult
    func createLibraryArchive(at destinationURL: URL) async -> Bool {
        if let reason = libraryCatalogBlockReason {
            statusMessage = libraryCatalogBlockMessage(reason)
            return false
        }
        guard libraryPersistenceEnabled,
              !isLibraryMaintenanceInProgress,
              !hasUncommittedDefectGesture,
              !isAcknowledgedLibraryTransactionActive else { return false }

        isLibraryMaintenanceInProgress = true
        defer { isLibraryMaintenanceInProgress = false }
        librarySaveTask?.cancel()
        librarySaveTask = nil
        // 결함 기록은 세션 전용이라 아카이브에 sidecar가 포함되지 않는다(종료 시 이미지에 굽힘).
        guard saveLibrary(synchronous: true) else {
            statusMessage = archiveText(.failed)
            return false
        }
        let catalogURL = libraryCatalogURL
        let defectDirectory = libraryDefectDirectoryURL
        let succeeded = await Task.detached(priority: .utility) {
            do {
                _ = try LibraryArchiveBuilder.create(
                    catalogURL: catalogURL,
                    defectDirectory: defectDirectory,
                    destinationURL: destinationURL
                )
                return true
            } catch {
                return false
            }
        }.value
        statusMessage = archiveText(succeeded ? .created : .failed)
        return succeeded
    }
}
