import SwiftUI
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    /// 드래그 중에는 단일 worker가 약 25Hz로 최신 strength만 coalesce해
    /// snapshot을 만든다. worker가 이미 있으면 tick은 generation만 올리므로
    /// 취소/재생성 task storm이 생기지 않는다. mask 검증·canonical encoding·SHA-256은
    /// MainActor 밖에서 수행하고, 계산 중 더 새 tick이 오면 결과를 폐기한 뒤
    /// 같은 worker가 최신 세대를 계속 처리한다. 드래그 종료는 worker를 취소하고
    /// 현재 값을 동기로 1회 확정한다.
    func scheduleLiveDefectRecipeRefresh(_ frame: ScanFrame, changedIndex: Int) {
        frame.defectRecipeRefreshGeneration &+= 1
        frame.defectRecipeRefreshChangedEditID = frame.defectEdits[changedIndex].id

        // fingerprint 대기 중에 이전 identity/cache를 현재 strength의 결과로 오인하지
        // 않도록 fail-closed한다. source binding은 defectGestureSourceIdentity에 보존된다.
        frame.cleanRawRevision += 1
        frame.cleanRawTask?.cancel()
        frame.cleanRawTask = nil
        if frame.defectRecipeIdentity != nil {
            frame.defectRecipeIdentity = nil
        }
        guard frame.defectRecipeRefreshTask == nil else { return }

        let workerID = UUID()
        frame.defectRecipeRefreshWorkerID = workerID
        let task = Task { @MainActor [weak self, weak frame] in
            guard let self, let frame else { return }
            defer {
                if frame.defectRecipeRefreshWorkerID == workerID {
                    frame.defectRecipeRefreshTask = nil
                    frame.defectRecipeRefreshWorkerID = nil
                    frame.defectRecipeRefreshChangedEditID = nil
                }
            }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: defectRecipeLiveCoalescingNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      self.ownsFrame(frame),
                      frame.defectGestureRecipeAdvanced,
                      let changedEditID = frame.defectRecipeRefreshChangedEditID,
                      let latestChangedIndex = frame.defectEdits.firstIndex(where: {
                          $0.id == changedEditID
                      }) else { return }

                let generation = frame.defectRecipeRefreshGeneration
                // Data는 COW로 전달되므로 MainActor에서는 현재 레코드 snapshot만 캡는다.
                let records = frame.defectEdits.map { DefectEditItemRecord(item: $0) }
                let frameID = frame.id
                let revision = frame.defectRecipeRevision
                let sourceIdentity = frame.defectGestureSourceIdentity
                let snapshot = await Task.detached(priority: .userInitiated) {
                    try? DefectRecipeSnapshot(
                        frameID: frameID,
                        revision: revision,
                        sourceIdentity: sourceIdentity,
                        items: records
                    )
                }.value
                guard !Task.isCancelled,
                      self.ownsFrame(frame),
                      frame.defectGestureRecipeAdvanced else { return }
                guard frame.defectRecipeRefreshGeneration == generation else {
                    continue
                }
                guard let snapshot else {
                    self.statusMessage = self.text(AppLocalizedPhrase.removingDefectsFailedStatus)
                    return
                }

                self.installDefectRecipeIdentity(snapshot.identity, on: frame)
                self.invalidateLibraryQueryContext()
                self.scheduleLibrarySave()
                self.rebuildAfterEdit(
                    frame,
                    changedIndex: latestChangedIndex,
                    live: true,
                    recipeSnapshot: snapshot
                )
                return
            }
        }
        frame.defectRecipeRefreshTask = task
    }

    /// 레이어 삭제(수동 제거). 남은 레이어만으로 재빌드한다.

}
