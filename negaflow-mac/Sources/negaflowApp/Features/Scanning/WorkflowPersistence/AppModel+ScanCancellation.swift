import AppKit
import Chromabase
import Foundation
import ScannerKit

extension AppModel {
    func cancelActiveScanWorkflow() async {
        guard isScanning else { return }
        let sessionID = activeScanSessionID
        let backend = activeScannerBackend
        activeScanSessionID = nil
        await backend?.cancelScan()
        activeScannerBackend = nil

        if let sessionID,
           let session = scanSessions.first(where: { $0.id == sessionID }) {
            let updated = cancellingHardwareJobs(in: session)
            if let updated {
                _ = replaceAndPublishScanSession(updated)
                isScanFinalizationInProgress = updated.jobs.contains {
                    $0.state == .finalizing || $0.pendingCapture != nil
                }
            }
        }

        isScanning = false
        batchTotal = 0
        batchIndex = 0
        scanPhase = .idle
        scanFraction = 0
        statusMessage = text(AppLocalizedPhrase.scanCanceled)
    }


}
