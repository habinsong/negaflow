import SwiftUI
import AppKit
import Chromabase

enum CanvasCompareMode: String {
    case raw
    case developed
    case splitVertical
    case splitHorizontal
}

private struct BeforeAfterToggleRequestModifier: ViewModifier {
    @ObservedObject var model: AppModel
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: model.beforeAfterToggleRequest) { _, _ in
            action()
        }
    }
}

/// 좌우/상하 비교에서 "Before"로 보여줄 대상.
///  - main: 현재 조정에서 현상 타깃만 MAIN으로 적용한 비교본.
///  - unedited: 무보정 현상본(Target main, 프로파일/조정 없음) — 기본값.
///  - raw: 반전 전 raw 스캔.
enum CompareBeforeContent: String, CaseIterable {
    case main
    case unedited
    case raw

    func label(language: AppLanguage) -> String {
        switch self {
        case .main: return DevelopTarget.main.displayName(language: language)
        case .unedited: return AppLocalization.text(AppLocalizedPhrase.unedited, language: language)
        case .raw: return AppLocalization.text(AppLocalizedPhrase.raw, language: language)
        }
    }
}

struct CanvasView: View {
    @ObservedObject var frame: ScanFrame
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var localAdjustmentSession: LocalAdjustmentSession
    @Binding var cropMode: Bool
    @Binding var brushMode: Bool
    @Binding var regionDefectMode: Bool
    @Binding var cloneStampMode: Bool
    @Binding var basePickerMode: Bool
    @Environment(\.displayScale) var displayScale
    @State var viewport = CanvasViewportState()
    @State var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    // 크롭 진입 시점의 엔진 크롭(취소 시 복원용). nil = 크롭 없음.
    @State var preCropRect: SIMD4<Double>?
    @State var cropSessionActive = false
    @State var brushThickness: CGFloat = 0.010
    @State var brushStrokes: [DefectStroke] = []
    @State var cloneStampSizePx: CGFloat = 48
    @State var cloneStampHardness: CGFloat = 0.5
    @State var compareMode: CanvasCompareMode = .developed
    @State var previousCompareMode: CanvasCompareMode = .raw
    // 분할선 위치(이미지 기준 비율). 좌/우와 상/하가 각자의 위치를 기억한다.
    @State var splitVerticalFraction: CGFloat = 0.5
    @State var splitHorizontalFraction: CGFloat = 0.5
    @State var canvasHUDState = CanvasHUDInteractionState()
    @AppStorage("compare.beforeContent") var beforeContentRaw: String = CompareBeforeContent.unedited.rawValue
    @AppStorage("crop.aspectLocked") var isCropAspectLocked = true

    var body: some View {
        GeometryReader { geo in
            // 레이아웃은 안정화된 표시 크기(frame.displayPixelSize)를 쓴다. 인터랙티브/정착 프록시의
            // 반올림 종횡비 차이(<0.5%)가 fitted frame을 서브픽셀 단위로 흔드는 것을 막는다.
            let image = referenceImage
            let imageSize = image.map { frame.displayPixelSize ?? $0.size }
            let fittedImageFrame = imageSize.map {
                canvasFittedImageFrame(for: $0, in: geo.size, scale: viewport.scale, offset: viewport.offset)
            }
            ZStack(alignment: .topLeading) {
                model.canvasBackground.color
                if let layoutSize = imageSize, let imageFrame = fittedImageFrame {
                    imageLayer(in: imageFrame)
                    if frame.isPreviewScan,
                       model.flatbedPreviewFrameID == frame.id,
                       model.usesFlatbedRegionWorkflow,
                       !cropMode,
                       !brushMode,
                       !regionDefectMode,
                       !cloneStampMode,
                       !basePickerMode {
                        FlatbedScanAreaOverlay(frame: frame, imageFrame: imageFrame)
                    }
                    if cropMode {
                        CropOverlay(
                            cropRect: $cropRect,
                            imageFrame: imageFrame,
                            lockedAspectRatio: cropAspectLockRatio(for: layoutSize),
                            onApply: applyCrop,
                            onReset: resetCrop,
                            onCancel: cancelCrop
                        )
                    }
                    if brushMode {
                        BrushOverlay(
                            strokes: $brushStrokes,
                            thickness: brushThickness,
                            imageFrame: imageFrame
                        )
                    }
                    if regionDefectMode {
                        RegionDefectOverlay(frame: frame, imageFrame: imageFrame)
                    }
                    if cloneStampMode {
                        CloneStampOverlay(
                            frame: frame,
                            imageFrame: imageFrame,
                            referenceImage: image,
                            sizePx: $cloneStampSizePx,
                            hardness: $cloneStampHardness
                        )
                    }
                    if basePickerMode {
                        basePickerOverlay(imageFrame: imageFrame)
                    }
                    if localAdjustmentSession.isActive(for: frame) {
                        LocalAdjustmentOverlay(frame: frame, imageFrame: imageFrame)
                    }
                    if frame.defectMaskPreviewID != nil {
                        DefectMaskOverlay(frame: frame, imageFrame: imageFrame)
                    }
                    canvasHUD
                    movableCompareHUD(canvasSize: geo.size)
                    movableZoomHUD(imageSize: layoutSize, canvasSize: geo.size)
                    debugStageBadge
                        .padding(10)
                }
                PixelSamplerReadoutView(
                    store: model.pixelSamplerStore,
                    language: model.appLanguage
                )
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
            }
            // 확대하면 imageFrame 이 캔버스 크기를 넘는다. ZStack 은 자식이 자기 bounds 밖으로
            // 그려도 자르지 않으므로, 넘친 픽셀이 좌우 패널과 상단 툴바 위로 그려진다(패널을
            // 덮거나 툴바와의 이음새로 비침) — 캔버스 영역에서 잘라낸다.
            .clipped()
            .coordinateSpace(name: canvasCoordinateSpace)
            .onContinuousHover(coordinateSpace: .named(canvasCoordinateSpace)) { phase in
                switch phase {
                case .active(let location):
                    guard model.pixelSamplerStore.isEnabled,
                          let imageFrame = fittedImageFrame,
                          imageFrame.contains(location) else {
                        model.pixelSamplerStore.update(nil)
                        return
                    }
                    model.updatePixelSampler(
                        for: frame,
                        displayUnitPoint: CGPoint(
                            x: (location.x - imageFrame.minX) / max(imageFrame.width, 1),
                            y: (location.y - imageFrame.minY) / max(imageFrame.height, 1)
                        )
                    )
                case .ended:
                    model.pixelSamplerStore.update(nil)
                }
            }
            .contentShape(Rectangle())
            .gesture(panGesture(imageSize: imageSize, canvasSize: geo.size))
            .simultaneousGesture(zoomGesture(imageSize: imageSize, canvasSize: geo.size))
            .contextMenu { canvasBackgroundMenu }
            .background {
                canvasKeyboardShortcuts(imageSize: imageSize, canvasSize: geo.size)
            }
            .background {
                CanvasScrollPanBridge { translation in
                    guard let imageSize else { return }
                    viewport.applyScrollPan(
                        translation: translation,
                        imageSize: imageSize,
                        canvasSize: geo.size
                    )
                }
            }
            .onAppear {
                adoptDisplayTarget(displayTargetPixels(imageSize: imageSize, canvasSize: geo.size))
            }
            .onChange(of: displayTargetPixels(imageSize: imageSize, canvasSize: geo.size)) { _, newValue in
                adoptDisplayTarget(newValue)
            }
        }
        .environment(\.colorScheme, model.canvasBackground.hudColorScheme)
        .onAppear { updateCompareGating() }
        .onDisappear {
            model.beforeAfterCompareActive = false
            model.beforeAfterMainCompareActive = false
        }
        .onChange(of: beforeContentRaw) { _, _ in updateCompareGating() }
        .onChange(of: cropMode) { _, isOn in
            if isOn {
                // 크롭 진입: 현재 크롭을 일시 해제해 **원본 전체**를 보여주고, 기존 크롭을 선택
                // 영역으로 미리 채운다. 이렇게 해야 핸들을 바깥으로 끌어 잘렸던 영역을 다시 키울 수 있다.
                cropSessionActive = true
                preCropRect = frame.imageTransform.cropRect
                cropRect = displayRect(for: frame.imageTransform.cropRect)
                if frame.imageTransform.cropRect != nil {
                    frame.updateTransform { $0.cropRect = nil }
                    model.applyTransformFast(frame)
                }
            } else {
                restorePreCropAfterCancellation()
            }
        }
        .onChange(of: brushMode) { _, isOn in
            if !isOn { brushStrokes.removeAll() }
        }
        .onChange(of: frame.imageTransform.displayName) { _, _ in
            if !cropMode {
                resetViewport(animated: false)
            }
        }
        .onChange(of: basePickerMode) { _, isOn in
            // 베이스는 반전 전 raw 에서 보인다(오렌지 마스크). 진입 시 Raw 보기, 종료 시 복원.
            if isOn {
                selectCompareMode(.raw)
            } else if activeCompareMode == .raw {
                selectCompareMode(.developed)
            }
        }
        .modifier(BeforeAfterToggleRequestModifier(model: model, action: toggleDevelopedShortcut))
        // ⌘Z/⇧⌘Z 는 편집 메뉴 한 곳에서만 받는다. 캔버스가 ⌘Z 를 가로채면 사진을 지운 직후의
        // 되돌리기가 지운 사진이 아니라 지금 사진의 GrainMend 로 가 버린다.
    }

    /// 캔버스가 실제로 쓰는 픽셀 수를 모델에 반영한다.
    ///
    /// 여기서 다시 현상을 요청하지 않는다. 표시 크기는 렌더 결과의 종횡비에 의존하고, 프록시
    /// 치수가 바뀌면 반올림 때문에 종횡비가 미세하게 흔들린다. 그 변화가 다시 이 경로를
    /// 부르면 요청과 취소가 맞물려 프리뷰가 영영 나오지 않는다.
    private func adoptDisplayTarget(_ target: CGFloat) {
        model.canvasDisplayTargetPixels = target
    }
}
