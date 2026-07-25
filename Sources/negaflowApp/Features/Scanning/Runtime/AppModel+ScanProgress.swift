import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    func update(_ p: ScanProgress, sessionID: UUID) {
        // 스캔 종료 후 늦게 도착하는 진행 콜백이 완료/취소 상태를 덮어써(역행) 진행률이 어긋나는 것을 막는다.
        guard isScanning, activeScanSessionID == sessionID else { return }
        let now = Date()
        let nextFraction = normalizedScanFraction(for: p)
        let message = userFacingScanMessage(for: p)
        let phaseChanged = p.phase != lastProgressPhase
        let messageChanged = message != lastProgressMessage
        let fractionMoved = abs(nextFraction - lastProgressFraction) >= 0.015
        let timeElapsed = now.timeIntervalSince(lastProgressUpdateAt) >= 0.20
        guard phaseChanged || messageChanged || fractionMoved || timeElapsed else { return }
        lastProgressUpdateAt = now
        lastProgressFraction = nextFraction
        lastProgressPhase = p.phase
        lastProgressMessage = message
        scanPhase = p.phase
        scanFraction = nextFraction
        statusMessage = message
    }

    func displayedScanFraction(at _: Date = Date()) -> Double {
        let base = min(max(scanFraction, 0), 1)
        return isScanning ? base : (scanPhase == .complete ? 1 : base)
    }

    private func normalizedScanFraction(for progress: ScanProgress) -> Double {
        if progress.phase == .complete { return 1 }
        let explicit = progress.fraction.map { min(max($0, 0), 1) }
        let fallback = scanFallbackFraction(for: progress.phase)
        return min(0.995, max(scanFraction, explicit ?? fallback))
    }

    private func scanFallbackFraction(for phase: ScanPhase) -> Double {
        switch phase {
        case .idle: return 0
        case .connecting: return 0.06
        case .warmingLamp: return 0.18
        case .ready: return 0.22
        case .previewScanning: return 0.35
        case .waitingForFilmHolder: return 0.24
        case .scanningRGB: return 0.42
        case .scanningIR: return 0.70
        case .processingNegative: return 0.88
        case .renderingLook: return 0.94
        case .exporting: return 0.96
        case .complete: return 1
        case .scannerBusy, .disconnected, .error, .backendFallbackActive: return scanFraction
        }
    }

    private func userFacingScanMessage(for progress: ScanProgress) -> String {
        switch progress.phase {
        case .idle: return text(AppLocalizedPhrase.scanProgressIdle)
        case .connecting: return text(AppLocalizedPhrase.scanProgressConnecting)
        case .warmingLamp: return text(AppLocalizedPhrase.scanProgressWarmingLamp)
        case .ready: return text(AppLocalizedPhrase.scanProgressReady)
        case .previewScanning: return text(AppLocalizedPhrase.scanProgressPreviewScanning)
        case .waitingForFilmHolder: return text(AppLocalizedPhrase.scanProgressWaitingForFilmHolder)
        case .scanningRGB: return text(AppLocalizedPhrase.scanProgressScanningRGB)
        case .scanningIR: return text(AppLocalizedPhrase.scanProgressScanningIR)
        case .processingNegative: return text(AppLocalizedPhrase.scanProgressProcessingNegative)
        case .renderingLook: return text(AppLocalizedPhrase.scanProgressRenderingLook)
        case .exporting: return text(AppLocalizedPhrase.scanProgressExporting)
        case .complete: return text(AppLocalizedPhrase.scanProgressComplete)
        case .scannerBusy: return text(AppLocalizedPhrase.scanProgressScannerBusy)
        case .disconnected: return text(AppLocalizedPhrase.scanProgressDisconnected)
        case .error:
            return progress.message.isEmpty ? text(AppLocalizedPhrase.scanProgressError) : progress.message
        case .backendFallbackActive: return text(AppLocalizedPhrase.scanProgressBackendFallbackActive)
        }
    }

}
