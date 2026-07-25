import AppKit
import Chromabase
import Foundation
import ScannerKit

extension AppModel {
    /// 앱 재시작은 하드웨어를 절대 자동 재호출하지 않는다. 실행 중이던 job은 interrupted로
    /// 닫고, 이미 durable receipt가 있는 finalizing job만 파일 검증/해시부터 재개한다.
    @discardableResult
    func reconcilePersistedScanWorkflowAfterRestore() async -> Bool {
        guard libraryPersistenceEnabled,
              libraryLifecycleState == .ready,
              !scanSessions.isEmpty else { return true }

        isScanFinalizationInProgress = true
        defer { isScanFinalizationInProgress = false }

        for session in scanSessions where session.closedAt == nil {
            var updated = session
            do {
                for job in updated.jobs where job.state == .running {
                    guard let current = updated.jobs.first(where: { $0.id == job.id }) else {
                        return false
                    }
                    let interrupted = try current.failed(
                        with: ScannerError(
                            .interrupted,
                            text(AppLocalizedPhrase.scanInterruptedFailureReason)
                        ),
                        at: max(Date(), current.updatedAt)
                    )
                    updated = try updated.replacing(interrupted)
                }
            } catch {
                return false
            }
            if updated != session, !replaceAndPublishScanSession(updated) {
                return false
            }
        }

        let sessionIDs = scanSessions.map(\.id)
        for sessionID in sessionIDs {
            guard let session = scanSessions.first(where: { $0.id == sessionID }),
                  session.closedAt == nil else { continue }
            var canPublishNextManifest = true
            for job in session.jobs.sorted(by: { $0.ordinal < $1.ordinal })
                where job.state == .finalizing {
                guard canPublishNextManifest, let pendingCapture = job.pendingCapture else {
                    continue
                }
                do {
                    let manifest = try await Task.detached(priority: .utility) {
                        try CaptureManifest.build(
                            sessionID: sessionID,
                            jobID: job.id,
                            attempt: job.attempt,
                            kind: job.kind,
                            requestedOptions: job.requestedOptions,
                            pendingCapture: pendingCapture
                        )
                    }.value
                    if !publishFinalizedScan(
                        manifest,
                        sessionID: sessionID,
                        jobID: job.id
                    ) {
                        canPublishNextManifest = false
                    }
                } catch {
                    canPublishNextManifest = false
                    _ = failFinalization(
                        sessionID: sessionID,
                        jobID: job.id,
                        error: scannerError(from: error)
                    )
                }
            }
            _ = closeScanSessionIfTerminal(sessionID)
        }
        return true
    }


}
