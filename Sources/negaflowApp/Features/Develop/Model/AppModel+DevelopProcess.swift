import Chromabase
import Foundation

extension AppModel {
    func applyDevelopmentProcess(_ newFilmType: FilmType, to frame: ScanFrame?) {
        filmType = newFilmType
        if frame?.isPreviewScan == true || activeScanSessionID != nil || frame == nil {
            scanDevelopFilmType = newFilmType
        }
        updateActiveScanDevelopFilmType(newFilmType)

        let target = frame?.params.developTarget ?? developTarget
        let currentProfileID = frame?.params.scannerProfileID ?? scannerProfileID
        let compatibleProfileID = currentProfileID.flatMap { profileID in
            ScannerProfileMatcher.matchingProfiles(
                target: target,
                filmType: newFilmType,
                profiles: scannerProfiles
            ).contains(where: { $0.id == profileID }) ? profileID : nil
        }
        scannerProfileID = compatibleProfileID

        guard let frame else { return }
        frame.filmType = newFilmType
        frame.updateParams {
            $0.filmType = newFilmType
            $0.scannerProfileID = compatibleProfileID
        }
        Task { await developFrame(frame) }
    }

    func applyDevelopTarget(_ target: DevelopTarget, to frame: ScanFrame?) {
        developTarget = target
        let filmType = frame?.filmType ?? self.filmType
        let currentProfileID = frame?.params.scannerProfileID ?? scannerProfileID
        let profileID: String?
        if target.isScannerEmulation {
            profileID = nil
        } else if let currentProfileID,
                  ScannerProfileMatcher.matchingProfiles(
                    target: target,
                    filmType: filmType,
                    profiles: scannerProfiles
                  ).contains(where: { $0.id == currentProfileID }) {
            profileID = currentProfileID
        } else {
            profileID = nil
        }
        scannerProfileID = profileID

        guard let frame else { return }
        frame.updateParams {
            $0.developTarget = target
            $0.scannerProfileID = profileID
        }
        Task { await developFrame(frame) }
    }
}
