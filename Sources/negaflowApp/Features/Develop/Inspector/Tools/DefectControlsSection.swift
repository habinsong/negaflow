import SwiftUI
import Chromabase

struct DefectControlsSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @Binding var cropMode: Bool
    @Binding var brushMode: Bool
    @Binding var regionDefectMode: Bool
    @Binding var cloneStampMode: Bool

    var body: some View {
        InspectorCard {
            InspectorCardHeader(title: model.text(AppLocalizedPhrase.inspectorTabDefect), systemImage: "paintbrush.pointed.fill")
            HStack(spacing: 8) {
                // 자동: 진입 즉시 전체 프레임 검출. 가이드와 같은 검출 오버레이/세션을 공유하되
                // defectAutoMode 로 구분한다(ROI 드래그 없이 자동 검출).
                InspectorActionPill(
                    title: model.text(AppLocalizedPhrase.autoDefect),
                    help: model.text(AppLocalizedPhrase.autoDefectHelp),
                    resetTitle: model.text(AppLocalizedPhrase.reset),
                    isActive: regionDefectMode && frame.defectAutoMode,
                    action: {
                        withAnimation(.snappy(duration: 0.18)) {
                            if regionDefectMode && frame.defectAutoMode {
                                regionDefectMode = false   // 끄기(바인딩이 세션 정리)
                            } else {
                                frame.defectAutoMode = true
                                cropMode = false; brushMode = false; cloneStampMode = false
                                model.cancelRegionDefect(frame)   // 가이드→자동 전환 시 세션 초기화
                                regionDefectMode = true
                                model.runRegionDetect(frame, displayROI: CGRect(x: 0, y: 0, width: 1, height: 1))
                            }
                        }
                    },
                    reset: {
                        regionDefectMode = false
                        model.resetRegionDefect(frame)
                    }
                )

                InspectorActionPill(
                    title: model.text(AppLocalizedPhrase.guidedDefect),
                    help: model.text(AppLocalizedPhrase.guidedDefectHelp),
                    resetTitle: model.text(AppLocalizedPhrase.reset),
                    isActive: regionDefectMode && !frame.defectAutoMode,
                    action: {
                        withAnimation(.snappy(duration: 0.18)) {
                            if regionDefectMode && !frame.defectAutoMode {
                                regionDefectMode = false
                            } else {
                                frame.defectAutoMode = false
                                cropMode = false; brushMode = false; cloneStampMode = false
                                model.cancelRegionDefect(frame)   // 자동→가이드 전환 시 세션 초기화
                                regionDefectMode = true
                            }
                        }
                    },
                    reset: {
                        regionDefectMode = false
                        model.resetRegionDefect(frame)
                    }
                )

                InspectorActionPill(
                    title: model.text(AppLocalizedPhrase.brushDefect),
                    help: model.text(AppLocalizedPhrase.brushDefectHelp),
                    resetTitle: model.text(AppLocalizedPhrase.reset),
                    isActive: brushMode,
                    action: {
                        withAnimation(.snappy(duration: 0.18)) { brushMode.toggle(); if brushMode { cropMode = false; regionDefectMode = false; cloneStampMode = false } }
                    },
                    reset: {
                        brushMode = false
                        model.resetBrushDefect(frame)
                    }
                )

                InspectorActionPill(
                    title: model.text(AppLocalizedPhrase.cloneStamp),
                    help: model.text(AppLocalizedPhrase.cloneStampHelp),
                    resetTitle: model.text(AppLocalizedPhrase.reset),
                    isActive: cloneStampMode,
                    action: {
                        withAnimation(.snappy(duration: 0.18)) { cloneStampMode.toggle(); if cloneStampMode { cropMode = false; brushMode = false; regionDefectMode = false } }
                    },
                    reset: {
                        cloneStampMode = false
                        model.resetCloneStampDefect(frame)
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct InspectorActionPill: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let help: String
    let resetTitle: String
    let isActive: Bool
    let action: () -> Void
    let reset: () -> Void
    @State private var actionHovered = false
    @State private var resetHovered = false

    var body: some View {
        HStack(spacing: 1) {
            Button(action: action) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
                    .frame(maxWidth: .infinity, minHeight: 31)
                    .padding(.leading, 7)
                    .background(
                        Color.primary.opacity(actionHovered ? 0.12 : 0),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { actionHovered = $0 }
            .accessibilityLabel(help)
            .accessibilitySelectionState(
                isActive,
                selectedValue: model.accessibilityText(.active),
                unselectedValue: model.accessibilityText(.inactive),
                selectedHint: model.accessibilityText(.deactivate),
                unselectedHint: model.accessibilityText(.activate)
            )

            Button(action: reset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption2.weight(.bold))
                    .frame(width: 23, height: 23)
                    .background(Color.primary.opacity(resetHovered ? 0.12 : 0), in: Circle())
            }
            .buttonStyle(.plain)
            .onHover { resetHovered = $0 }
            .help(resetTitle)
            .accessibilityLabel(resetTitle)
            .padding(.trailing, 3)
        }
        .frame(maxWidth: .infinity)
        .background(isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(isActive ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.12)))
        .help(help)
    }
}
