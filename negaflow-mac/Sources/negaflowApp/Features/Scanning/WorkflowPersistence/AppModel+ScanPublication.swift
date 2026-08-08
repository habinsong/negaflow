import AppKit
import Chromabase
import Foundation
import ScannerKit

extension AppModel {
    func publishScanGeneration(
        frames snapshotFrames: [ScanFrame],
        rolls snapshotRolls: [LibraryRoll],
        activeRollID snapshotActiveRollID: UUID?,
        sessions snapshotSessions: [ScanSession],
        assignments snapshotAssignments: [LibraryScanRollAssignment]
    ) -> Bool {
        if libraryPersistenceEnabled {
            guard beginAcknowledgedLibraryTransaction() else { return false }
            defer { endAcknowledgedLibraryTransaction() }
            guard case .success = commitAcknowledgedLibrarySnapshot(
                frames: snapshotFrames,
                rolls: snapshotRolls,
                activeRollID: snapshotActiveRollID,
                scanSessions: snapshotSessions,
                scanRollAssignments: snapshotAssignments
            ) else { return false }
        } else {
            guard makeLibraryCatalogSnapshot(
                frames: snapshotFrames,
                rolls: snapshotRolls,
                activeRollID: snapshotActiveRollID,
                scanSessions: snapshotSessions,
                scanRollAssignments: snapshotAssignments
            ) != nil else { return false }
        }

        if frames != snapshotFrames { frames = snapshotFrames }
        if rolls != snapshotRolls || activeRollID != snapshotActiveRollID {
            replaceRollState(with: RollStoreSnapshot(
                rolls: snapshotRolls,
                activeRollID: snapshotActiveRollID
            ))
        }
        if scanSessions != snapshotSessions { scanSessions = snapshotSessions }
        if scanRollAssignments != snapshotAssignments {
            scanRollAssignments = snapshotAssignments
        }
        return true
    }

    func replaceAndPublishScanSession(_ updatedSession: ScanSession) -> Bool {
        guard let index = scanSessions.firstIndex(where: { $0.id == updatedSession.id }) else {
            return false
        }
        var sessions = scanSessions
        sessions[index] = updatedSession
        return publishScanGeneration(
            frames: frames,
            rolls: rolls,
            activeRollID: activeRollID,
            sessions: sessions,
            assignments: scanRollAssignments
        )
    }

    /// 실패 이유를 그대로 돌려준다. 캡처 원본 검증 실패를 카탈로그 저장 실패로 뭉개면
    /// 사용자가 볼 수 있는 단서가 사라진다.
    func publishFinalizedScan(
        _ manifest: CaptureManifest,
        sessionID: UUID,
        jobID: UUID
    ) -> Result<Void, ScannerError> {
        let persistenceFailure = ScannerError(
            .ioFailure,
            text(AppLocalizedPhrase.scanWorkflowPersistenceFailed)
        )
        guard let sessionIndex = scanSessions.firstIndex(where: { $0.id == sessionID }),
              let job = scanSessions[sessionIndex].jobs.first(where: {
                  $0.id == jobID && $0.state == .finalizing
              }),
              let publication = job.framePublication,
              let assignment = scanRollAssignments.first(where: { $0.sessionID == sessionID }),
              !frames.contains(where: { $0.id == publication.frameID }),
              !frames.contains(where: {
                  !$0.isPreviewScan
                      && $0.sourceFrameID == nil
                      && $0.scanIndex == publication.scanIndex
                      && $0.rawScanURL.deletingLastPathComponent().standardizedFileURL
                          == manifest.rgbFile.originalURL
                              .deletingLastPathComponent()
                              .standardizedFileURL
              }) else {
            return .failure(persistenceFailure)
        }

        let succeededJob: ScanJob
        let succeededSession: ScanSession
        do {
            succeededJob = try job.succeeded(
                with: manifest,
                at: max(Date(), job.updatedAt)
            )
            succeededSession = try scanSessions[sessionIndex].replacing(succeededJob)
        } catch {
            return .failure(scannerError(from: error))
        }

        let developFilmType = assignment.developFilmType ?? job.requestedOptions.filmType
        let compatibleScannerProfileID: String?
        if developFilmType == job.requestedOptions.filmType {
            compatibleScannerProfileID = publication.scannerProfileID
        } else {
            compatibleScannerProfileID = publication.scannerProfileID.flatMap { profileID in
                ScannerProfileMatcher.matchingProfiles(
                    target: publication.developTarget,
                    filmType: developFilmType,
                    profiles: scannerProfiles
                ).contains(where: { $0.id == profileID }) ? profileID : nil
            }
        }
        let frame = ScanFrame(
            scanIndex: publication.scanIndex,
            rawScanURL: manifest.rgbFile.originalURL,
            filmType: developFilmType,
            infraredScanURL: manifest.infraredFile?.originalURL,
            sourceKind: .scannerTIFF,
            sourcePixelWidth: manifest.result.width,
            sourcePixelHeight: manifest.result.height,
            sourceResolutionDPI: manifest.result.reportedResolution?.dpi,
            sourceBitDepth: manifest.result.reportedBitDepth?.rawValue,
            sourceMetadata: SourceMetadataReader.read(from: manifest.rgbFile.originalURL),
            scanSessionID: sessionID,
            scanJobID: jobID,
            initialTransform: publication.initialTransform,
            scannedAt: manifest.captureCompletedAt,
            id: publication.frameID,
            storageGroupName: publication.storageGroupName
        )
        frame.preset = publication.presetID.flatMap { presetID in
            presets.first(where: { $0.id == presetID })
        }
        frame.updateParams {
            $0.filmType = developFilmType
            $0.developTarget = publication.developTarget
            $0.scannerProfileID = compatibleScannerProfileID
        }
        frame.establishLibraryWorkflowBaselineIfNeeded()

        guard let rollGeneration = rollsPublishing(frame, assignment: assignment) else {
            return .failure(persistenceFailure)
        }
        var sessions = scanSessions
        sessions[sessionIndex] = succeededSession
        let nextFrames = frames + [frame]
        guard publishScanGeneration(
            frames: nextFrames,
            rolls: rollGeneration.rolls,
            activeRollID: rollGeneration.activeRollID,
            sessions: sessions,
            assignments: scanRollAssignments
        ) else {
            return .failure(persistenceFailure)
        }

        seedInitialThumbnail(for: frame, from: manifest.rgbFile.originalURL)
        includeFrameInInteractionScopeIfNeeded(frame.id)
        selectedFrameID = frame.id
        Task { await developFrameAfterFastPreview(frame) }
        if frame.infraredScanURL != nil { runInfraredClean(frame) }
        if let roi = publication.regionDefectDisplayROI,
           let sensitivity = publication.regionDefectSensitivity {
            frame.defectGuidedSensitivity = sensitivity
            runRegionDetect(frame, displayROI: roi)
        }
        return .success(())
    }

    private func rollsPublishing(
        _ frame: ScanFrame,
        assignment: LibraryScanRollAssignment
    ) -> (rolls: [LibraryRoll], activeRollID: UUID?)? {
        var updatedRolls = rolls
        var createdRoll = false
        if let index = updatedRolls.firstIndex(where: { $0.id == assignment.rollID }) {
            guard updatedRolls[index].kind == .physical,
                  updatedRolls[index].filmType == assignment.filmType,
                  !updatedRolls[index].frameIDs.contains(frame.id) else {
                return nil
            }
            updatedRolls[index].frameIDs.append(frame.id)
        } else {
            guard let roll = LibraryRoll.physical(
                id: assignment.rollID,
                name: assignment.draftName,
                createdAt: assignment.createdAt,
                filmType: assignment.filmType,
                frameIDs: [frame.id]
            ) else { return nil }
            updatedRolls.append(roll)
            createdRoll = true
        }
        return (
            updatedRolls,
            createdRoll ? assignment.rollID : activeRollID
        )
    }


}
