import Foundation

extension AppModel {
    func persistDefectRecipe(_ snapshot: DefectRecipeSnapshot, for frame: ScanFrame) {
        DefectSidecarFile.writeAsync(snapshot, in: libraryDefectDirectoryURL) { [weak self, weak frame] result in
            switch result {
            case .success(.written), .success(.alreadyCurrent):
                return
            case .success(.skippedNewer(let existingRevision)):
                // 디스크가 더 새 세대면 메모리 recipe 는 저장되지 않은 것이다 — 성공으로 넘기지 않는다.
                AppModel.recordDefectSidecarWriteFailure("skippedNewer(\(existingRevision))")
            case .failure(let error):
                AppModel.recordDefectSidecarWriteFailure("\(error)")
            }
            Task { @MainActor in
                guard let self, let frame, self.ownsFrame(frame),
                      frame.defectRecipeIdentity == snapshot.identity else { return }
                self.statusMessage = self.text(AppLocalizedPhrase.removingDefectsFailedStatus)
            }
        }
    }

    /// 기록이 저장되지 않으면 다음 카탈로그 저장은 `defect_sidecar_mismatch` 로 막힌다. 그 원인을
    /// 진단 패널의 실패 이벤트에 남긴다 — 상태 문구만으로는 왜 막혔는지 알 수 없었다.
    nonisolated static func recordDefectSidecarWriteFailure(_ reason: String) {
        AppDiagnostics.start(.catalogSave, category: .catalog)
            .fail(code: "defect_sidecar_write_failed.\(reason)")
    }
}
