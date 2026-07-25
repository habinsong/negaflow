import SwiftUI
import AppKit
import Chromabase
import ScannerKit
import CoreImage
import UniformTypeIdentifiers

struct ScanProgressOverlay: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let fraction = model.displayedScanFraction(at: context.date)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label(model.scanPhase.displayName(language: model.appLanguage), systemImage: "scanner")
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 12)
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: fraction)
                    .frame(width: 240)
                // statusCenter 직접 읽기 — TimelineView 0.25s 틱마다 재평가되므로 별도 구독
                // 없이도 스캔 중 메시지가 그 주기로 갱신된다(오버레이의 설계 주기와 동일).
                Text(model.statusCenter.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .liquidSurface(cornerRadius: 10, interactive: false)
        }
        .frame(width: 264)
    }
}

extension ScanPhase {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .idle: return AppLocalization.text(.scanPhaseIdle, language: language)
        case .connecting: return AppLocalization.text(.scanPhaseConnecting, language: language)
        case .warmingLamp: return AppLocalization.text(.scanPhaseWarmingLamp, language: language)
        case .ready: return AppLocalization.text(.scanPhaseReady, language: language)
        case .previewScanning: return AppLocalization.text(.scanPhasePreviewScanning, language: language)
        case .waitingForFilmHolder: return AppLocalization.text(.scanPhaseWaitingForFilmHolder, language: language)
        case .scanningRGB: return AppLocalization.text(.scanPhaseScanningRGB, language: language)
        case .scanningIR: return AppLocalization.text(.scanPhaseScanningIR, language: language)
        case .processingNegative: return AppLocalization.text(.scanPhaseProcessingNegative, language: language)
        case .renderingLook: return AppLocalization.text(.scanPhaseRenderingLook, language: language)
        case .exporting: return AppLocalization.text(.scanPhaseExporting, language: language)
        case .complete: return AppLocalization.text(.scanPhaseComplete, language: language)
        case .scannerBusy: return AppLocalization.text(.scanPhaseScannerBusy, language: language)
        case .disconnected: return AppLocalization.text(.scanPhaseDisconnected, language: language)
        case .error: return AppLocalization.text(.scanPhaseError, language: language)
        case .backendFallbackActive: return AppLocalization.text(.scanPhaseBackendFallbackActive, language: language)
        }
    }
}
