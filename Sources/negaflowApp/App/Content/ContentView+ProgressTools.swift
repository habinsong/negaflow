import SwiftUI
import AppKit
import Chromabase
import ScannerKit
import CoreImage
import UniformTypeIdentifiers

extension ContentView {
    /// 하단 바 진행 슬롯 — 현상 진행 텍스트 전용이다. 스캔 진행률(막대 + %)은 캔버스 위
    /// ScanProgressOverlay 하나로만 보여준다(하단 바에 중복 표시하지 않는다).
    @ViewBuilder
    var statusProgressSlot: some View {
        DevelopProgressStatusView(controller: model.developController)
    }

    func cropModeBinding(for frame: ScanFrame) -> Binding<Bool> {
        Binding(
            get: { cropFrameID == frame.id },
            set: { isOn in
                cropFrameID = isOn ? frame.id : nil
                if isOn {
                    brushFrameID = nil; regionDefectFrameID = nil; cloneStampFrameID = nil
                    basePickerFrameID = nil
                    localAdjustmentSession.deactivate()
                }
            }
        )
    }

    func brushModeBinding(for frame: ScanFrame) -> Binding<Bool> {
        Binding(
            get: { brushFrameID == frame.id },
            set: { isOn in
                brushFrameID = isOn ? frame.id : nil
                if isOn {
                    cropFrameID = nil; regionDefectFrameID = nil; cloneStampFrameID = nil
                    basePickerFrameID = nil
                    localAdjustmentSession.deactivate()
                }
            }
        )
    }

    func regionDefectModeBinding(for frame: ScanFrame) -> Binding<Bool> {
        Binding(
            get: { regionDefectFrameID == frame.id },
            set: { isOn in
                regionDefectFrameID = isOn ? frame.id : nil
                if isOn {
                    cropFrameID = nil; brushFrameID = nil; cloneStampFrameID = nil
                    basePickerFrameID = nil
                    localAdjustmentSession.deactivate()
                }
                else { model.cancelRegionDefect(frame) }   // 모드 종료 시 진행 중 세션 정리
            }
        )
    }

    func cloneStampModeBinding(for frame: ScanFrame) -> Binding<Bool> {
        Binding(
            get: { cloneStampFrameID == frame.id },
            set: { isOn in
                cloneStampFrameID = isOn ? frame.id : nil
                if isOn {
                    cropFrameID = nil; brushFrameID = nil; regionDefectFrameID = nil
                    basePickerFrameID = nil
                    localAdjustmentSession.deactivate()
                }
            }
        )
    }

    func basePickerModeBinding(for frame: ScanFrame) -> Binding<Bool> {
        Binding(
            get: { basePickerFrameID == frame.id },
            set: { isOn in
                basePickerFrameID = isOn ? frame.id : nil
                if isOn {
                    cropFrameID = nil; brushFrameID = nil; regionDefectFrameID = nil
                    cloneStampFrameID = nil
                    localAdjustmentSession.deactivate()
                }
            }
        )
    }

    func handleDevelopToolShortcutRequest() {
        guard let action = model.pendingDevelopToolShortcutAction else { return }
        model.pendingDevelopToolShortcutAction = nil
        guard let frame = model.actionableFrame else { return }

        let wasActive: Bool
        switch action {
        case .cropTool:
            wasActive = cropFrameID == frame.id
        case .basePickerTool:
            wasActive = basePickerFrameID == frame.id
        case .autoDefectTool:
            wasActive = regionDefectFrameID == frame.id && frame.defectAutoMode
        case .guidedDefectTool:
            wasActive = regionDefectFrameID == frame.id && !frame.defectAutoMode
        case .brushDefectTool:
            wasActive = brushFrameID == frame.id
        case .cloneStampTool:
            wasActive = cloneStampFrameID == frame.id
        default:
            return
        }

        exitActiveDevelopInteraction()
        guard !wasActive else { return }

        withAnimation(.snappy(duration: 0.18)) {
            switch action {
            case .cropTool:
                cropFrameID = frame.id
            case .basePickerTool:
                basePickerFrameID = frame.id
            case .autoDefectTool:
                frame.defectAutoMode = true
                model.cancelRegionDefect(frame)
                regionDefectFrameID = frame.id
                model.runRegionDetect(
                    frame,
                    displayROI: CGRect(x: 0, y: 0, width: 1, height: 1)
                )
            case .guidedDefectTool:
                frame.defectAutoMode = false
                model.cancelRegionDefect(frame)
                regionDefectFrameID = frame.id
            case .brushDefectTool:
                brushFrameID = frame.id
            case .cloneStampTool:
                cloneStampFrameID = frame.id
            default:
                break
            }
        }
    }
}

private struct DevelopProgressStatusView: View {
    @ObservedObject var controller: DevelopController

    var body: some View {
        if controller.processingActive, !controller.processingDetail.isEmpty {
            Text(controller.processingDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}
