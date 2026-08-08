import SwiftUI
import AppKit
import Chromabase

extension DevelopWorkflowInspector {
    func batchWBBinding(_ keyPath: WritableKeyPath<DevelopParameters, Double>) -> Binding<Double> {
        DevelopInspectorBindings.batchWhiteBalance(
            frame: frame,
            keyPath: keyPath,
            onChange: { scheduleRedevelop(frame) },
            onSync: syncBatchWBIfNeeded
        )
    }

    var baseModeBinding: Binding<DevelopParameters.BaseMode> {
        DevelopInspectorBindings.baseMode(
            frame: frame,
            autoMatchScannerProfile: .constant(false),
            scannerProfiles: model.scannerProfiles,
            setModelScannerProfileID: { model.scannerProfileID = $0 },
            onChange: { scheduleRedevelop(frame) },
            onSync: syncBatchWBIfNeeded
        )
    }

    var filmStockDminIDBinding: Binding<String?> {
        DevelopInspectorBindings.filmStockDminID(
            frame: frame,
            autoMatchScannerProfile: false,
            scannerProfiles: model.scannerProfiles,
            setModelScannerProfileID: { model.scannerProfileID = $0 },
            onChange: { scheduleRedevelop(frame) },
            onSync: syncBatchWBIfNeeded
        )
    }

    var lightSourceProfileIDBinding: Binding<String?> {
        DevelopInspectorBindings.lightSourceProfileID(frame: frame) { scheduleRedevelop(frame) }
    }

    func autoCorrectionBinding(_ keyPath: WritableKeyPath<DevelopParameters, Bool>) -> Binding<Bool> {
        DevelopInspectorBindings.autoCorrection(frame: frame, keyPath: keyPath) { scheduleRedevelop(frame) }
    }

    var scannerProfileIDBinding: Binding<String?> {
        DevelopInspectorBindings.scannerProfileID(
            frame: frame,
            setModelScannerProfileID: { model.scannerProfileID = $0 },
            onChange: { scheduleRedevelop(frame) },
            onSync: syncBatchWBIfNeeded
        )
    }

    var matchingScannerProfiles: [ScannerProfile] {
        DevelopInspectorProfileMatcher.matchingProfiles(frame: frame, profiles: model.scannerProfiles)
    }

    func manualBaseBinding(channel: Int) -> Binding<Double> {
        DevelopInspectorBindings.manualBase(
            frame: frame,
            channel: channel,
            onChange: { scheduleRedevelop(frame) },
            onSync: syncBatchWBIfNeeded
        )
    }

    func resetManualBase() {
        basePickerMode = false
        frame.updateParams { $0.manualBaseRGB = nil }
        scheduleRedevelop(frame)
        syncBatchWBIfNeeded()
    }

    func syncBatchWBIfNeeded() { }   // Auto Sync WB(배치 WB 동기화) 제거됨 — 기존 호출부 호환용 no-op

    func scheduleRedevelop(_ frame: ScanFrame) {
        // 레이트 throttle은 모델이 담당한다(리딩+트레일링 ~22fps). 매 틱 동기 리비전 증가로 루프를
        // 무제한 렌더시키던 과거 방식이 GPU(IOSurface) 누적·간헐 블랭크 렌더의 원인이었다.
        model.requestDevelop(frame)
    }
}
