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

    /// 여러 컷을 이어 스캔할 때는 배치 전체의 진행률을 보여준다.
    ///
    /// 컷 하나의 진행률만 보여주면 실제로는 정상인데 실패처럼 보인다. 백엔드는 본 획득을
    /// 0.92까지만 매핑하고, 앱이 획득 직후 1로 올리지만 그 대입과 다음 컷의 0 초기화 사이에
    /// 중단 지점이 없어서 100%가 화면에 그려지는 일이 없다. 그래서 매 컷이 92%에서 멈췄다가
    /// 0%로 튀는 것처럼 보인다. 사진은 배치가 다 끝난 뒤에야 발행되므로 그때까지 아무것도
    /// 나타나지 않는다. 배치 기준으로 환산하면 진행률이 되돌아가지 않고 끝까지 올라간다.
    func displayedScanFraction(at _: Date = Date()) -> Double {
        let frame = min(max(scanFraction, 0), 1)
        let base: Double
        if batchTotal > 1 {
            let completed = Double(min(max(batchIndex, 0), batchTotal - 1))
            base = min(max((completed + frame) / Double(batchTotal), 0), 1)
        } else {
            base = frame
        }
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
