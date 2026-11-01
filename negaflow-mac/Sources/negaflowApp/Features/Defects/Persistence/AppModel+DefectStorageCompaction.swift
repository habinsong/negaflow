import Foundation

/// 1.2.4 이하가 쓴 v2 결함 기록은 적외선 마스크를 압축 없이 담아 장당 수십 MB 였고, 백업 세대마다
/// 그만큼 다시 복사됐다. 시작 뒤 한 번, 한 장씩 v3 로 다시 쓴다. recipe identity 는 그대로라
/// 카탈로그는 손대지 않는다. 라이브러리를 다루는 다른 일이 시작되면 다음 장부터 멈추고, 남은
/// 기록은 다음 실행에서 이어 간다.
extension AppModel {
    func startDefectStorageCompaction() {
        guard libraryPersistenceEnabled, defectStorageCompactionTask == nil else { return }
        let directory = libraryDefectDirectoryURL
        let frameIDs = frames.filter { $0.defectRecipeIdentity != nil }.map(\.id)
        guard !frameIDs.isEmpty else { return }
        defectStorageCompactionTask = Task { [weak self] in
            for frameID in frameIDs {
                guard let self, !Task.isCancelled, self.canCompactDefectStorage else { break }
                _ = await Task.detached(priority: .background) {
                    DefectSidecarFile.compactUnpackedStorage(for: frameID, in: directory)
                }.value
            }
            self?.defectStorageCompactionTask = nil
        }
    }

    private var canCompactDefectStorage: Bool {
        libraryPersistenceEnabled
            && libraryCatalogBlockReason == nil
            && libraryLifecycleState == .ready
            && !isLibraryMaintenanceInProgress
            && !isLibraryTerminationSaveInProgress
    }
}
