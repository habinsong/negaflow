import SwiftUI
import AppKit
import Chromabase

extension CanvasView {
    @ViewBuilder
    var canvasHUD: some View {
        CanvasHUDLayer(
            brushMode: brushMode,
            brushThickness: $brushThickness,
            hasBrushStrokes: !brushStrokes.isEmpty || frame.canUndoDefects,
            hasAppliedDefects: !frame.defectEdits.isEmpty,
            isRemovingDefects: frame.isRemovingDefects,
            onApplyBrush: applyBrush,
            onUndoBrush: undoBrushDraftOrApplied,
            onClearBrushDraft: { brushStrokes.removeAll() },
            onResetBrushes: { model.clearAllDefects(frame) }
        )
    }

    @ViewBuilder
    func canvasKeyboardShortcuts(imageSize: NSSize?, canvasSize: CGSize) -> some View {
        Group {
            Button("") { applyActiveTool() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApplyActiveTool)

            Button("") { zoomBy(1.25, imageSize: imageSize, canvasSize: canvasSize) }
                .keyboardShortcut("+", modifiers: [])
                .disabled(imageSize == nil)
            Button("") { zoomBy(1.25, imageSize: imageSize, canvasSize: canvasSize) }
                .keyboardShortcut("=", modifiers: [])
                .disabled(imageSize == nil)
            Button("") { zoomBy(1 / 1.25, imageSize: imageSize, canvasSize: canvasSize) }
                .keyboardShortcut("-", modifiers: [])
                .disabled(imageSize == nil)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Return 은 크롭에만 이 숨은 버튼으로 걸린다. GrainMend(자동/가이드/브러시)는 컨트롤 바의
    /// 실제 실행 버튼이 직접 `.defaultAction` 을 가진다 — 화면에 보이는 그 버튼과 1:1 로 대응하고,
    /// 같은 Return 이 두 경로로 중복 실행되지 않는다.
    var canApplyActiveTool: Bool {
        cropMode
    }

    func applyActiveTool() {
        if cropMode { applyCrop() }
    }

    func applyBrush() {
        guard !brushStrokes.isEmpty else { return }
        let strokes = brushStrokes
        brushStrokes.removeAll()
        // 표시 좌표 스트로크를 base 좌표로 변환·누적하고 결함 제거를 재적용(변형/재현상 후에도 유지).
        model.applyDefectStrokes(strokes, to: frame)
    }

    func undoBrushDraftOrApplied() {
        if !brushStrokes.isEmpty {
            _ = brushStrokes.popLast()
        } else {
            model.undoDefects(frame)
        }
    }

    /// 베이스 스포이드 오버레이: 클릭 지점을 raw 정규좌표로 역변환해 Dmin을 실측한다.
    /// 반전 전 raw 를 보면서 찍도록 진입 시 Raw 비교 모드로 전환한다(종료 시 복원).
    @ViewBuilder
    func basePickerOverlay(imageFrame: CGRect) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: imageFrame.width, height: imageFrame.height)
            .position(x: imageFrame.midX, y: imageFrame.midY)
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        // 로컬 좌표(오버레이 원점 = imageFrame 좌상단) → 0...1 정규(y-down).
                        let unit = CGPoint(
                            x: min(max(value.location.x / max(imageFrame.width, 1), 0), 1),
                            y: min(max(value.location.y / max(imageFrame.height, 1), 0), 1)
                        )
                        handleBasePick(atDisplayUnit: unit)
                    }
            )
            .overlay(alignment: .top) {
                HStack(spacing: 6) {
                    Image(systemName: "eyedropper")
                    Text(model.text(AppLocalizedPhrase.basePickerOverlayPrompt))
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .liquidSurface(cornerRadius: 8)
                .padding(.top, 12)
            }
            .onExitCommand { withAnimation(.snappy(duration: 0.18)) { basePickerMode = false } }
    }

    func handleBasePick(atDisplayUnit unit: CGPoint) {
        // 표시 좌표(변형 후, y-down) → 변형 전 raw 정규좌표. 픽셀 샘플러와 동일하게
        // baseSize 를 전달해 미세 회전(straighten) 역변환까지 정확히 푼다.
        let basePoint = frame.imageTransform.displayUnitToBase(
            unit,
            baseSize: model.sourcePixelSize(for: frame)
        )
        model.pickFilmBase(at: basePoint, frame: frame)
        withAnimation(.snappy(duration: 0.18)) { basePickerMode = false }
    }

    func toggleCropMode() {
        withAnimation(.snappy(duration: 0.18)) {
            cropMode.toggle()
            if cropMode {
                brushMode = false
                regionDefectMode = false
                cloneStampMode = false
            }
        }
    }

    func toggleBrushMode() {
        withAnimation(.snappy(duration: 0.18)) {
            brushMode.toggle()
            if brushMode {
                cropMode = false
                regionDefectMode = false
                cloneStampMode = false
            }
        }
    }

    func toggleRegionDefectMode() {
        withAnimation(.snappy(duration: 0.18)) {
            regionDefectMode.toggle()
            if regionDefectMode {
                cropMode = false
                brushMode = false
                cloneStampMode = false
            }
        }
    }

    func toggleCloneStampMode() {
        withAnimation(.snappy(duration: 0.18)) {
            cloneStampMode.toggle()
            if cloneStampMode {
                cropMode = false
                brushMode = false
                regionDefectMode = false
            }
        }
    }


}
