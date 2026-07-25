import AppKit
import Chromabase
import Foundation
import ScannerKit

extension AppModel {
    func failHardwareJobAndCancelQueued(
        sessionID: UUID,
        jobID: UUID,
        error: ScannerError
    ) -> Bool {
        guard var session = scanSessions.first(where: { $0.id == sessionID }),
              let job = session.jobs.first(where: { $0.id == jobID && $0.state == .running }) else {
            return false
        }
        do {
            let timestamp = max(Date(), job.updatedAt)
            let terminal = error.code == .cancelled
                ? try job.cancelled(at: timestamp)
                : try job.failed(with: error, at: timestamp)
            session = try session.replacing(terminal)
            for queued in session.jobs where queued.state == .queued {
                session = try session.replacing(
                    queued.cancelled(at: max(Date(), queued.updatedAt))
                )
            }
            return replaceAndPublishScanSession(session)
        } catch {
            return false
        }
    }

    func cancelQueuedJobs(in session: ScanSession) -> Bool {
        var updated = session
        do {
            for job in updated.jobs where job.state == .queued {
                updated = try updated.replacing(
                    job.cancelled(at: max(Date(), job.updatedAt))
                )
            }
            return updated == session || replaceAndPublishScanSession(updated)
        } catch {
            return false
        }
    }

    func cancellingHardwareJobs(in session: ScanSession) -> ScanSession? {
        var updated = session
        do {
            for job in updated.jobs where job.state == .running || job.state == .queued {
                guard let current = updated.jobs.first(where: { $0.id == job.id }) else {
                    return nil
                }
                updated = try updated.replacing(
                    current.cancelled(at: max(Date(), current.updatedAt))
                )
            }
            return updated
        } catch {
            return nil
        }
    }

    func failFinalization(
        sessionID: UUID,
        jobID: UUID,
        error: ScannerError
    ) -> Bool {
        guard let session = scanSessions.first(where: { $0.id == sessionID }),
              let job = session.jobs.first(where: {
                  $0.id == jobID && $0.state == .finalizing
              }) else { return false }
        do {
            let failed = try job.failed(with: error, at: max(Date(), job.updatedAt))
            return replaceAndPublishScanSession(try session.replacing(failed))
        } catch {
            return false
        }
    }

    func closeScanSessionIfTerminal(_ sessionID: UUID) -> Bool {
        guard let session = scanSessions.first(where: { $0.id == sessionID }),
              session.closedAt == nil,
              session.jobs.allSatisfy({
                  $0.state != .queued
                      && $0.state != .running
                      && $0.state != .finalizing
                      && $0.pendingCapture == nil
              }) else { return false }
        do {
            let latest = session.jobs.map(\.updatedAt).max() ?? session.createdAt
            return replaceAndPublishScanSession(
                try session.closed(at: max(Date(), latest))
            )
        } catch {
            return false
        }
    }

    func finishFullScanPreparationFailure(_ error: Error, sessionID: UUID) {
        guard activeScanSessionID == sessionID else { return }
        activeScanSessionID = nil
        activeScannerBackend = nil
        batchTotal = 0
        batchIndex = 0
        isScanning = false
        scanPhase = .error
        scanFraction = 0
        setScanWorkflowError(error, frameNumber: 1)
    }

    func setScanWorkflowError(_ error: Error, frameNumber: Int) {
        reportError(text(
            AppLocalizedPhrase.frameScanErrorFormat,
            frameNumber,
            error.localizedDescription
        ))
    }

    func scannerError(from error: Error) -> ScannerError {
        if let scannerError = error as? ScannerError { return scannerError }
        return ScannerError(.ioFailure, error.localizedDescription)
    }

    func scanOrdinal(sessionID: UUID, jobID: UUID) -> Int {
        scanSessions.first(where: { $0.id == sessionID })?
            .jobs.first(where: { $0.id == jobID })?.ordinal ?? 1
    }

}
