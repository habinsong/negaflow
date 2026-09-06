import Foundation

extension AppModel {
    func persistDefectRecipe(_ snapshot: DefectRecipeSnapshot, for frame: ScanFrame) {
        DefectSidecarFile.writeAsync(snapshot, in: libraryDefectDirectoryURL) { [weak self, weak frame] result in
            guard case .failure = result else { return }
            Task { @MainActor in
                guard let self, let frame, self.ownsFrame(frame),
                      frame.defectRecipeIdentity == snapshot.identity else { return }
                self.statusMessage = self.text(AppLocalizedPhrase.removingDefectsFailedStatus)
            }
        }
    }
}
