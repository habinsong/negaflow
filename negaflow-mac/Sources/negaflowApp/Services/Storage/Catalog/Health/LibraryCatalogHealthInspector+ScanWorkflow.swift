import Foundation
import ScannerKit
import Chromabase

extension LibraryCatalogHealthInspector {
    static func inspectScanWorkflow(
        _ catalog: LibraryCatalog,
        rollMemberships: [UUID: [(rollID: UUID, rollIndex: Int)]],
        issues: inout [LibraryCatalogHealthIssue]
    ) {
        let sessionsByID = Dictionary(grouping: catalog.scanSessions, by: \.id)
        let assignmentsBySessionID = Dictionary(
            grouping: catalog.scanRollAssignments,
            by: \.sessionID
        )
        let assignmentsByRollID = Dictionary(
            grouping: catalog.scanRollAssignments,
            by: \.rollID
        )
        let rollsByID = Dictionary(grouping: catalog.rolls, by: \.id)

        var jobsByID: [UUID: [(sessionID: UUID, job: ScanJob)]] = [:]
        var manifestsByID: [UUID: [(sessionID: UUID, jobID: UUID)]] = [:]

        for session in catalog.scanSessions {
            if sessionsByID[session.id, default: []].count > 1 {
                issues.append(issue(
                    .duplicateScanSessionID,
                    .error,
                    sessionID: session.id
                ))
            }
            if session.jobs.isEmpty {
                issues.append(issue(.emptyScanSession, .error, sessionID: session.id))
            }
            do {
                try session.validate()
            } catch {
                issues.append(issue(.invalidScanSession, .error, sessionID: session.id))
            }
            let assignments = assignmentsBySessionID[session.id, default: []]
            if assignments.isEmpty {
                issues.append(issue(
                    .missingScanRollAssignment,
                    .error,
                    sessionID: session.id
                ))
            } else if assignments.count > 1 {
                issues.append(issue(
                    .duplicateScanRollAssignment,
                    .error,
                    sessionID: session.id
                ))
            }

            for job in session.jobs {
                jobsByID[job.id, default: []].append((session.id, job))
                if job.kind == .preview {
                    issues.append(issue(
                        .previewJobPersisted,
                        .error,
                        sessionID: session.id,
                        jobID: job.id
                    ))
                }
                if let manifest = job.captureManifest {
                    manifestsByID[manifest.id, default: []].append((session.id, job.id))
                }
            }
        }

        for (jobID, owners) in jobsByID where owners.count > 1 {
            issues.append(issue(.duplicateScanJobID, .error, jobID: jobID))
        }
        for (manifestID, owners) in manifestsByID where owners.count > 1 {
            issues.append(issue(
                .duplicateCaptureManifestID,
                .error,
                manifestID: manifestID
            ))
        }

        for assignment in catalog.scanRollAssignments {
            let targetRolls = rollsByID[assignment.rollID, default: []]
            let targetsExistingPhysicalRoll = targetRolls.count == 1
                && targetRolls[0].kind == .physical
            if assignmentsByRollID[assignment.rollID, default: []].count > 1,
               !targetsExistingPhysicalRoll {
                issues.append(issue(
                    .duplicateScanRollAssignmentRollID,
                    .error,
                    rollID: assignment.rollID,
                    sessionID: assignment.sessionID
                ))
            }
            let validName = !assignment.draftName.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            if assignment.rollID == LibraryRoll.unassignedID
                || !validName
                || !assignment.createdAt.timeIntervalSinceReferenceDate.isFinite {
                issues.append(issue(
                    .invalidScanRollAssignment,
                    .error,
                    rollID: assignment.rollID,
                    sessionID: assignment.sessionID
                ))
            }
            if sessionsByID[assignment.sessionID, default: []].count != 1 {
                issues.append(issue(
                    .scanRollAssignmentMissingSession,
                    .error,
                    rollID: assignment.rollID,
                    sessionID: assignment.sessionID
                ))
            }
            if targetRolls.count == 1 {
                let targetRoll = targetRolls[0]
                if targetRoll.kind != .physical
                    || targetRoll.filmType != assignment.filmType {
                    issues.append(issue(
                        .invalidScanRollAssignment,
                        .error,
                        rollID: assignment.rollID,
                        sessionID: assignment.sessionID
                    ))
                }
            }
        }

        for (frameIndex, frame) in catalog.frames.enumerated() {
            switch (frame.scanSessionID, frame.scanJobID) {
            case (nil, nil):
                continue
            case (nil, _), (_, nil):
                issues.append(issue(
                    .partialFrameScanProvenance,
                    .error,
                    frameID: frame.id,
                    frameIndex: frameIndex,
                    sessionID: frame.scanSessionID,
                    jobID: frame.scanJobID
                ))
            case let (sessionID?, jobID?):
                guard let sessions = sessionsByID[sessionID], sessions.count == 1 else {
                    issues.append(issue(
                        .frameScanSessionMissing,
                        .error,
                        frameID: frame.id,
                        frameIndex: frameIndex,
                        sessionID: sessionID,
                        jobID: jobID
                    ))
                    continue
                }
                let matchingJobs = sessions[0].jobs.filter { $0.id == jobID }
                guard matchingJobs.count == 1 else {
                    issues.append(issue(
                        .frameScanJobMissing,
                        .error,
                        frameID: frame.id,
                        frameIndex: frameIndex,
                        sessionID: sessionID,
                        jobID: jobID
                    ))
                    continue
                }
                let job = matchingJobs[0]
                guard job.kind == .full,
                      job.state == .succeeded,
                      job.captureManifest != nil else {
                    issues.append(issue(
                        .frameScanJobNotSucceededFull,
                        .error,
                        frameID: frame.id,
                        frameIndex: frameIndex,
                        sessionID: sessionID,
                        jobID: jobID
                    ))
                    continue
                }
                let assignments = assignmentsBySessionID[sessionID, default: []]
                let memberships = rollMemberships[frame.id, default: []]
                if assignments.count == 1,
                   memberships.count == 1,
                   memberships[0].rollID != assignments[0].rollID {
                    issues.append(issue(
                        .frameScanRollMismatch,
                        .error,
                        frameID: frame.id,
                        frameIndex: frameIndex,
                        rollID: memberships[0].rollID,
                        rollIndex: memberships[0].rollIndex,
                        sessionID: sessionID,
                        jobID: jobID
                    ))
                }
            }
        }

        for session in catalog.scanSessions {
            let succeededJobs = session.jobs.filter {
                $0.kind == .full && $0.state == .succeeded
            }
            guard !succeededJobs.isEmpty else { continue }
            let assignments = assignmentsBySessionID[session.id, default: []]
            if assignments.count == 1,
               rollsByID[assignments[0].rollID, default: []].count != 1 {
                issues.append(issue(
                    .succeededScanRollMissing,
                    .error,
                    rollID: assignments[0].rollID,
                    sessionID: session.id
                ))
            }
            for job in succeededJobs {
                let rootFrames = catalog.frames.filter {
                    $0.sourceFrameID == nil
                        && $0.scanSessionID == session.id
                        && $0.scanJobID == job.id
                }
                if rootFrames.isEmpty {
                    issues.append(issue(
                        .succeededScanJobMissingRootFrame,
                        .warning,
                        sessionID: session.id,
                        jobID: job.id,
                        manifestID: job.captureManifest?.id
                    ))
                } else if rootFrames.count > 1 {
                    issues.append(issue(
                        .succeededScanJobDuplicateRootFrame,
                        .error,
                        sessionID: session.id,
                        jobID: job.id,
                        manifestID: job.captureManifest?.id
                    ))
                } else if let rootFrame = rootFrames.first,
                          let manifest = job.captureManifest {
                    if rootFrame.id != job.framePublication?.frameID
                        || rootFrame.scanIndex != job.framePublication?.scanIndex
                        || rootFrame.sourceKind != FrameSource.scannerTIFF.storageKey
                        || rootFrame.sourcePixelWidth != manifest.result.width
                        || rootFrame.sourcePixelHeight != manifest.result.height
                        || rootFrame.sourceResolutionDPI != manifest.result.reportedResolution?.dpi
                        || rootFrame.sourceBitDepth != manifest.result.reportedBitDepth?.rawValue
                        || rootFrame.scannedAt != manifest.captureCompletedAt {
                        issues.append(issue(
                            .scanRootFrameCaptureMismatch,
                            .error,
                            frameID: rootFrame.id,
                            sessionID: session.id,
                            jobID: job.id,
                            manifestID: manifest.id
                        ))
                    }
                    for virtualFrame in catalog.frames where
                        virtualFrame.scanSessionID == session.id
                            && virtualFrame.scanJobID == job.id
                            && virtualFrame.id != rootFrame.id
                            && virtualFrame.sourceFrameID != rootFrame.id {
                        issues.append(issue(
                            .scanVirtualCopyRootMismatch,
                            .error,
                            frameID: virtualFrame.id,
                            sessionID: session.id,
                            jobID: job.id,
                            manifestID: manifest.id
                        ))
                    }
                }
            }
        }
    }


}
