import Chromabase
import Foundation

extension AppModel {
    /// 프로세스 목록과 메뉴가 현재 선택으로 표시할 항목. 프레임이 있으면 프레임 기준이다.
    var activeDevelopmentProcess: DevelopmentProcess {
        guard let frame = actionableFrame else {
            return DevelopmentProcess(filmType: filmType, isDigitalSource: isDigitalSource)
        }
        return DevelopmentProcess(
            filmType: frame.filmType,
            isDigitalSource: frame.params.isDigitalSource
        )
    }

    func applyDevelopmentProcess(_ newFilmType: FilmType, to frame: ScanFrame?) {
        applyDevelopmentProcess(.film(newFilmType), to: frame)
    }

    func applyDevelopmentProcess(_ process: DevelopmentProcess, to frame: ScanFrame?) {
        let newFilmType = process.filmType
        filmType = newFilmType
        isDigitalSource = process.isDigitalSource
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
            // 필름이면 nil로 되돌려 기존 프레임의 레시피 지문을 그대로 유지한다.
            $0.isDigitalSource = process.isDigitalSource ? true : nil
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
