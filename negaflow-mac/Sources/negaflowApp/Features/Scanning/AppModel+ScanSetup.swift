import Chromabase
import Foundation

extension AppModel {
    var scanFolderNameText: String {
        if let scanFolderNameDraft {
            return scanFolderNameDraft
        }
        if let selectedFolder = recentCreatedScanFolder {
            return selectedFolder.lastPathComponent
        }
        return text(.untitledFilm)
    }

    var resolvedScanFolderName: String {
        let sanitized = FrameStorageNaming.sanitizeComponent(scanFolderNameText)
        return sanitized.isEmpty ? text(.untitledFilm) : sanitized
    }

    func scanFolderParentURL(for date: Date = Date()) -> URL {
        diskStorage.scansURL
            .appendingPathComponent(
                FrameStorageNaming.dateFolderName(for: date),
                isDirectory: true
            )
            .appendingPathComponent(
                FrameStorageNaming.filmTypeFolderName(scanFilmType),
                isDirectory: true
            )
    }

    func updateScanFolderName(_ name: String) {
        scanFolderNameDraft = name
        diskStorage.recentCreatedScanFolderPath = nil
    }

    func commitScanFolderName() {
        let sanitized = FrameStorageNaming.sanitizeComponent(scanFolderNameText)
        scanFolderNameDraft = sanitized.isEmpty ? nil : sanitized
    }

    func selectScanStorageRoot(_ url: URL) {
        diskStorage.scansPath = url.standardizedFileURL.path
        diskStorage.recentCreatedScanFolderPath = nil
    }

    func selectScanFilmType(_ newFilmType: FilmType) {
        guard scanFilmType != newFilmType else { return }
        scanFilmType = newFilmType
        scanDevelopFilmType = newFilmType
        diskStorage.recentCreatedScanFolderPath = nil
        if !InfraredFilmCompatibility(filmType: newFilmType).allowsAutomaticCorrection {
            infraredEnabled = false
        }
        if let frame = actionableFrame, frame.isPreviewScan {
            applyDevelopmentProcess(newFilmType, to: frame)
        } else if actionableFrame == nil {
            filmType = newFilmType
        }
    }

    func updateActiveScanDevelopFilmType(_ newFilmType: FilmType) {
        guard let activeScanSessionID,
              let index = scanRollAssignments.firstIndex(where: {
                  $0.sessionID == activeScanSessionID
              }) else {
            return
        }
        scanRollAssignments[index].developFilmType = newFilmType
    }
}
