import Darwin
import Foundation

/// 결함 기록 지연 읽기. 시작할 때는 카탈로그의 식별값만 얹고, 항목(마스크 — IR 은 장당 수십 MB)은
/// 그 사진을 실제로 쓸 때(선택·현상·클린 raw 재빌드·내보내기) 읽는다. 클린 raw 가 메모리 캐시에서
/// 밀려날 때 디스크와 같은 세대로 확정된 항목은 다시 내려놓아, 상주량이 메모리 캐시 한도를 따른다.
extension AppModel {
    /// 항목이 메모리에 있으면 true. 같은 사진의 요청은 한 번의 읽기를 함께 기다린다.
    @discardableResult
    func loadDeferredDefectEdits(_ frame: ScanFrame) async -> Bool {
        guard frame.defectEditsLoadDeferred else { return !frame.defectEditsNeedRestore }
        return await startDeferredDefectEditsLoad(frame).value
    }

    @discardableResult
    func startDeferredDefectEditsLoad(_ frame: ScanFrame) -> Task<Bool, Never> {
        if let task = frame.defectEditsLoadTask { return task }
        let frameID = frame.id
        let directory = libraryDefectDirectoryURL
        let backupDirectory = libraryBackupDirectoryURL
        let task = Task { [weak self, weak frame] () -> Bool in
            let restored = await Task.detached(priority: .userInitiated) {
                // 내려놓기 전에 예약된 쓰기가 남아 있으면 그 결과를 읽는다.
                DefectSidecarFile.flushSync()
                return DefectRecipeRestoration.read(
                    frameID: frameID,
                    in: directory,
                    backupDirectory: backupDirectory
                )
            }.value
            guard let self, let frame else { return false }
            frame.defectEditsLoadTask = nil
            if frame.defectEditsLoadDeferred, self.ownsFrame(frame) {
                self.applyDeferredDefectRecipe(restored, to: frame)
            }
            return !frame.defectEditsNeedRestore
        }
        frame.defectEditsLoadTask = task
        return task
    }

    private func applyDeferredDefectRecipe(_ restored: DefectRecipeRestoration, to frame: ScanFrame) {
        frame.defectEditsLoadDeferred = false
        let catalogIdentity = frame.defectRecipeIdentity
        guard let snapshot = restored.snapshot, snapshot.frameID == frame.id else {
            // 기록이 사라졌거나 깨졌고 백업으로도 못 살렸다. 시작 때 읽기에 실패한 것과 같은
            // 상태로 둔다 — 저장 검증이 막고 수동 복구가 다룬다.
            frame.defectRecipeIdentity = nil
            invalidateLibraryQueryContext()
            return
        }
        // 카탈로그가 기록보다 늦을 수 있다(기록을 쓴 직후 비정상 종료 등). 기록이 진실이다 —
        // identity 가 바뀌면 프레임 변경 관찰이 이 사진의 카탈로그 행을 다시 쓴다.
        restored.apply(to: frame)
        LaunchTrace.markOnce("first deferred defect recipe loaded")
        if frame.defectRecipeIdentity != catalogIdentity { invalidateLibraryQueryContext() }
    }

    /// 선택한 사진의 앞뒤 사진 중 아직 읽지 않은 결함 기록 파일을 OS 페이지 캐시에 올려 둔다.
    /// 클릭 때 드는 기록 읽기는 대부분 디스크 대기라, 화살표로 넘길 다음 사진은 이미 데워진 파일을
    /// 읽는다(실측: 중앙값 126ms → 26ms). 항목은 올리지 않으므로 앱 메모리는 늘지 않는다.
    func warmNeighborDefectRecords(around frame: ScanFrame) {
        defectRecordWarmTask?.cancel()
        defectRecordWarmTask = nil
        let ids = interactionFrameIDs
        guard let index = ids.firstIndex(of: frame.id) else { return }
        let neighborIDs = [index + 1, index - 1]
            .filter { ids.indices.contains($0) }
            .compactMap { libraryFramesByIDCache[ids[$0]] }
            .filter(\.defectEditsLoadDeferred)
            .map(\.id)
        guard !neighborIDs.isEmpty else { return }
        let directory = libraryDefectDirectoryURL
        defectRecordWarmTask = Task.detached(priority: .utility) {
            for frameID in neighborIDs {
                guard !Task.isCancelled else { return }
                Self.warmPageCache(of: DefectSidecarFile.url(for: frameID, in: directory))
            }
        }
    }

    /// 파일을 끝까지 읽고 내용은 버린다. 읽기 권고(F_RDADVISE)만으로는 실측상 캐시가 데워지지 않았다.
    private nonisolated static func warmPageCache(of url: URL) {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var buffer = [UInt8](repeating: 0, count: 1 << 20)
        while !Task.isCancelled, read(descriptor, &buffer, buffer.count) > 0 {}
    }

    /// 클린 raw 가 메모리 캐시에서 밀려날 때 부른다. 디스크 기록과 같은 세대로 확정됐고 지금 이
    /// 항목을 쓰는 작업이 없을 때만 내려놓는다 — 다음에 쓸 때 같은 기록을 다시 읽는다. 되돌리기
    /// 기록이 남은 사진은 그 스냅샷이 항목을 다시 얹으므로 그대로 둔다.
    func unloadCommittedDefectEditsIfIdle(_ frame: ScanFrame) {
        guard !frame.isPreviewScan,
              !frame.defectEditsNeedRestore,
              !frame.defectEdits.isEmpty,
              frame.id != selectedFrameID,
              frame.defectHistoryDepth == 0,
              frame.pendingDefectHistorySnapshot == nil,
              frame.cleanRawTask == nil,
              frame.defectDetectTask == nil,
              !frame.defectActive,
              !frame.defectIsDetecting,
              !frame.defectIsRemoving,
              !frame.isRemovingDefects,
              !frame.isDeveloping,
              !InfraredCleanSessionRegistry.isRunning(owner: self, frameID: frame.id),
              isDefectRecipeCommitted(frame) else { return }
        frame.defectEditsNeedRestore = true
        frame.defectEditsLoadDeferred = true
        frame.defectEdits = []
    }
}
