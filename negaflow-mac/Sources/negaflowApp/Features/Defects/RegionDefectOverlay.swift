import SwiftUI
import AppKit
import Chromabase

// 가이드 영역 결함 제거 오버레이.
//  - 검출 전: 드래그로 ROI 사각형 지정 → 종료 시 검출(빨강 표시).
//  - 검출 후: 빨강 컴포넌트를 탭하면 제외↔포함 토글. 빈 곳을 드래그하면 새 ROI 로 재검출.
//  - 컨트롤 바: 민감도 슬라이더, 제거/취소.
// 좌표는 base 정규로 들고 baseUnitToDisplay 로 화면에 매핑 — 회전/플립/회전보정/크롭과 정합한다.
struct RegionDefectOverlay: View {
    @ObservedObject var frame: ScanFrame
    @EnvironmentObject var model: AppModel
    let imageFrame: CGRect

    var body: some View {
        ZStack {
            RegionPreviewCanvas(
                components: frame.defectPreview,
                excludedIDs: frame.defectExcludedIDs,
                baseSize: frame.defectBaseSize,
                transform: frame.imageTransform,
                imageFrame: imageFrame
            )
            .equatable()
            RegionROIGestureLayer(frame: frame, model: model, imageFrame: imageFrame)
            // 컨트롤 캡슐(최상단 중앙) / 종류별 칩(최하단 중앙).
            VStack(spacing: 0) {
                controlBar
                Spacer(minLength: 0)
                if frame.defectActive, !frame.defectIsDetecting, !frame.defectPreview.isEmpty {
                    classChipsBar
                }
            }
            .padding(.vertical, 12)
        }
        .onChange(of: frame.isRemovingDefects) { _, removing in
            // 모델이 정상 종료를 소유한다. 이 관찰자는 오래된 비동기 경로가 남긴 상태의 방어용이다.
            if !removing, frame.defectIsRemoving { model.clearRegionDefectSession(frame) }
        }
    }

    // MARK: 컨트롤 바

    private var controlBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope").foregroundStyle(.red)
            if frame.defectIsDetecting {
                ProgressView().controlSize(.small)
                Text(model.text(AppLocalizedPhrase.detectingDefectsStatus)).font(.caption).foregroundStyle(.secondary)
            } else if frame.defectActive {
                Text(detectSummary).font(.caption).foregroundStyle(.secondary)
                Divider().frame(height: 16)
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.caption2).foregroundStyle(.secondary)
                    // 자동과 가이드는 슬라이더 범위가 다르다 — 값도 따로 저장한다.
                    Slider(value: sensitivity, in: GrainMendSensitivity.range(automatic: frame.defectAutoMode),
                           onEditingChanged: { editing in if !editing { model.redetectRegion(frame) } })
                        .frame(width: 110)
                        .disabled(frame.defectIsRemoving || frame.isRemovingDefects)
                }
                microSpecksToggle
                Divider().frame(height: 16)
                Button(action: { model.cancelRegionDefect(frame) }) { Image(systemName: "xmark") }
                    .help(model.text(AppLocalizedPhrase.cancel)).disabled(frame.defectIsRemoving)
                Button(action: { model.commitRegionDefect(frame) }) {
                    if frame.defectIsRemoving {
                        ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16)
                    } else {
                        Label(model.text(AppLocalizedPhrase.removeDefects), systemImage: "bandage")
                    }
                }
                .buttonStyle(.borderedProminent)
                // Return 으로 바로 제거한다 — 검출 결과를 확인한 뒤 손이 키보드에 있는 채로 끝낸다.
                .keyboardShortcut(.defaultAction)
                .disabled(frame.defectIsRemoving || !hasSelectable)
            } else {
                // 자동과 가이드는 별개 도구다 — 대기 안내도 섞지 않는다(자동에는 드래그가 없다).
                Text(model.text(frame.defectAutoMode
                                ? AppLocalizedPhrase.autoDefectHelp
                                : AppLocalizedPhrase.dragDefectRegion))
                    .font(.caption).foregroundStyle(.secondary)
                microSpecksToggle
                if frame.canUndoDefects {
                    Divider().frame(height: 16)
                    // 가이드 되돌리기. 통합 편집(defectEdits)이라 마지막 편집이 브러시든 가이드든
                    // 되돌린다 — 두 도구가 한 히스토리를 공유한다.
                    Button(action: { model.performUndo() }) {
                        Label(model.text(AppLocalizedPhrase.undo), systemImage: "arrow.uturn.backward")
                    }
                    .help(model.text(AppLocalizedPhrase.undoDefectRemovalHelp))
                    .disabled(frame.isRemovingDefects)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .adaptiveCapsuleSurface(.ultraThin)
    }

    // MARK: 종류별 칩(HUD) — 일괄 제외 + 신뢰도

    /// 검출된 결함 종류별 칩. 탭하면 그 종류 전체를 제외↔포함(개별 클릭 제외와 병행). 각 칩은
    /// 분류색 점 + 이름 + 개수 + 평균 신뢰도를 보여준다. 콘텐츠 폭에 맞춰(여백 없음) 중앙 정렬.
    private var classChipsBar: some View {
        HStack(spacing: 6) {
            ForEach(model.defectClassSummaries(frame)) { summary in
                DefectClassChip(summary: summary,
                                name: summary.classification.displayName(language: model.appLanguage),
                                color: summary.classification.overlayColor,
                                action: { model.toggleRegionClass(frame, classification: summary.classification) })
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .adaptiveCapsuleSurface(.ultraThin)
        .fixedSize()   // 콘텐츠 폭에 딱 맞춘다(오른쪽 여백 제거).
    }

    /// 미세 입자(현상 찌꺼기·유분) 추가 검출 토글. 검출 결과 표시 중에 바꾸면 같은 ROI 로 재검출한다.
    private var microSpecksToggle: some View {
        Toggle(model.text(AppLocalizedPhrase.defectMicroSpeck), isOn: Binding(
            get: { frame.defectMicroSpecks },
            set: { newValue in
                // 자동과 가이드는 값을 공유하지 않는다 — 지금 쓰는 모드 쪽만 바꾼다.
                if frame.defectAutoMode {
                    frame.defectAutoMicroSpecks = newValue
                } else {
                    frame.defectGuidedMicroSpecks = newValue
                }
                if frame.defectActive, !frame.defectIsDetecting { model.redetectRegion(frame) }
            }))
            .toggleStyle(.checkbox)
            .font(.caption)
            .disabled(frame.defectIsRemoving || frame.isRemovingDefects)
    }

    /// 모드별 민감도 저장소. 자동과 가이드는 슬라이더 범위·매핑이 달라 값을 공유하지 않는다.
    private var sensitivity: Binding<Double> {
        frame.defectAutoMode ? $frame.defectAutoSensitivity : $frame.defectGuidedSensitivity
    }

    private var detectSummary: String {
        // 자동 오검출 위험은 경고만 — 검출 결과는 그대로 남아 있고 제외는 사용자가 한다.
        if frame.defectLabelField?.automaticFalsePositiveRisk == true {
            return model.text(AppLocalizedPhrase.automaticDefectFalsePositiveRiskStatus)
        }
        let total = frame.defectPreview.count
        let excluded = frame.defectExcludedIDs.count
        if total == 0 { return model.text(AppLocalizedPhrase.noDefectsStatus) }
        return excluded > 0
            ? model.text(AppLocalizedPhrase.defectsCountExcludedFormat, total, excluded)
            : model.text(AppLocalizedPhrase.defectsCountFormat, total)
    }

    private var hasSelectable: Bool {
        frame.defectPreview.contains { !frame.defectExcludedIDs.contains($0.id) }
    }
}

// MARK: 종류별 칩

/// 한 결함 종류 칩: 분류색 점 + 이름 + 개수 + 평균 신뢰도(%). 탭하면 그 종류 전체 제외↔포함.
/// 배경은 중성(색은 점에만) — 알록달록 배경 없이 담백하게. 전체 제외 상태는 흐리게 + 취소선.
private struct DefectClassChip: View {
    let summary: AppModel.DefectClassSummary
    let name: String
    let color: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(summary.allExcluded ? Color.secondary.opacity(0.4) : color)
                    .frame(width: 7, height: 7)
                Text(name)
                    .font(.caption.weight(.medium))
                    .strikethrough(summary.allExcluded, color: .secondary)
                Text(summary.count, format: .number)
                    .font(.caption.monospacedDigit().weight(.semibold))
                Text("\(Int((summary.meanConfidence * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(summary.allExcluded ? Color.secondary : Color.primary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(hovered ? 0.10 : 0.05)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(name)
    }
}

// MARK: 미리보기(빨강 컴포넌트)

/// 값 입력만 받는 Equatable 캔버스 — ROI 드래그/민감도 슬라이더 같은 무관한 상태 변화에
/// 컴포넌트 점(수백~수천 개) 재드로잉이 끌려가지 않는다.
private struct RegionPreviewCanvas: View, Equatable {
    let components: [DefectPreviewComponent]
    let excludedIDs: Set<Int32>
    let baseSize: CGSize?
    let transform: ImageTransform
    let imageFrame: CGRect

    var body: some View {
        Canvas { ctx, _ in
            guard let baseSize else { return }
            for comp in components {
                let excluded = excludedIDs.contains(comp.id)
                // 분류색 + confidence 불투명도(v2) — 종류와 확신이 한눈에 보인다.
                let color = excluded
                    ? Color.gray.opacity(0.35)
                    : comp.classification.overlayColor.opacity(0.35 + 0.5 * comp.confidence)
                for pt in comp.points {
                    let d0 = transform.baseUnitToDisplay(pt, baseSize: baseSize)
                    let d = CGPoint(x: imageFrame.minX + d0.x * imageFrame.width,
                                    y: imageFrame.minY + d0.y * imageFrame.height)
                    guard imageFrame.contains(d) else { continue }
                    ctx.fill(Path(CGRect(x: d.x - 1.5, y: d.y - 1.5, width: 3, height: 3)), with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: ROI 드래그(러버밴드 + 제스처)

/// 드래그 @State 를 이 자식 뷰에 격리한다 — 매 틱마다 부모 오버레이(미리보기 캔버스 포함)가
/// 재평가되지 않아 ROI 를 그리는 동안 메인 스레드가 가볍다. body 는 로컬 상태만 읽는다.
private struct RegionROIGestureLayer: View {
    let frame: ScanFrame
    let model: AppModel
    let imageFrame: CGRect

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        ZStack {
            if let s = dragStart, let c = dragCurrent {
                let r = screenRect(s, c)
                Rectangle()
                    .strokeBorder(Color.yellow.opacity(0.9), lineWidth: 1.5)
                    .background(Color.yellow.opacity(0.06))
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
                    .allowsHitTesting(false)
            }
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
                        .onChanged { value in
                            if dragStart == nil { dragStart = value.startLocation }
                            // 러버밴드 사각형은 가이드 전용 — 자동 모드에선 표시하지 않는다(ROI 없음).
                            if !frame.defectAutoMode { dragCurrent = value.location }
                        }
                        .onEnded { value in
                            guard !frame.defectIsRemoving, !frame.isRemovingDefects else {
                                dragStart = nil
                                dragCurrent = nil
                                return
                            }
                            let start = dragStart ?? value.startLocation
                            dragStart = nil; dragCurrent = nil
                            let dist = hypot(value.translation.width, value.translation.height)
                            if dist < 6 {
                                // 탭: 검출 상태면 컴포넌트 토글(자동/가이드 공통).
                                if frame.defectActive, !frame.defectIsDetecting {
                                    model.toggleRegionComponent(frame, atDisplay: unit(value.location))
                                }
                            } else if !frame.defectAutoMode {
                                // 드래그: 새 ROI 검출(가이드 전용 — 자동 모드는 전체 프레임 고정).
                                let roi = unitRect(start, value.location)
                                if !frame.defectIsDetecting, roi.width > 0.012, roi.height > 0.012 {
                                    model.runRegionDetect(frame, displayROI: roi)
                                }
                            }
                        }
                )
        }
    }

    private func unit(_ p: CGPoint) -> CGPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return .zero }
        return CGPoint(x: min(max((p.x - imageFrame.minX) / imageFrame.width, 0), 1),
                       y: min(max((p.y - imageFrame.minY) / imageFrame.height, 0), 1))
    }

    private func unitRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        let ua = unit(a), ub = unit(b)
        return CGRect(x: min(ua.x, ub.x), y: min(ua.y, ub.y),
                      width: abs(ua.x - ub.x), height: abs(ua.y - ub.y))
    }

    private func screenRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
