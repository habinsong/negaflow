import SwiftUI
import AppKit
import Chromabase

// 복제 도장 오버레이.
//  - ⌥ 클릭: 복제 소스 지정(십자 마커). 다시 ⌥ 클릭하면 소스와 정렬 오프셋을 재설정한다.
//  - 드래그: 소스 오프셋으로 복제. 첫 스트로크가 소스−시작점 오프셋을 확정하고, 이후 스트로크는
//    같은 오프셋을 유지한다(소스가 브러시를 따라 움직임). 드래그 중에는 소스 창의 실제 픽셀을
//    스트로크 모양으로 미리 보여주고, 십자 마커가 샘플 위치를 따라간다.
//  - 컨트롤 바: 크기(px)·경도(%) 슬라이더, 되돌리기.
// 소스/오프셋은 base 정규좌표로 보관해 줌/팬/회전/크롭과 무관하게 정합한다.
struct CloneStampOverlay: View {
    @ObservedObject var frame: ScanFrame
    @EnvironmentObject var model: AppModel
    let imageFrame: CGRect
    let referenceImage: NSImage?
    @Binding var sizePx: CGFloat
    @Binding var hardness: CGFloat

    @State private var sourceBase: CGPoint?          // 복제 소스(base 정규, y-down)
    @State private var alignedOffsetBase: CGVector?  // 첫 스트로크에서 확정되는 소스−대상 오프셋

    var body: some View {
        ZStack(alignment: .top) {
            CloneStampGestureLayer(
                frame: frame,
                model: model,
                imageFrame: imageFrame,
                referenceImage: referenceImage,
                sizePx: sizePx,
                hardness: hardness,
                sourceBase: $sourceBase,
                alignedOffsetBase: $alignedOffsetBase
            )
            controlBar
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle").foregroundStyle(.red)
            if sourceBase == nil {
                Text(model.text(AppLocalizedPhrase.cloneStampSourceHint))
                    .font(.caption).foregroundStyle(.secondary)
                Divider().frame(height: 16)
            }
            HStack(spacing: 6) {
                Text(model.text(AppLocalizedPhrase.cloneStampSize))
                    .font(.caption2).foregroundStyle(.secondary)
                Slider(value: $sizePx, in: 4...512).frame(width: 96)
                Text("\(Int(sizePx))px")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
            Divider().frame(height: 16)
            HStack(spacing: 6) {
                Text(model.text(AppLocalizedPhrase.cloneStampHardness))
                    .font(.caption2).foregroundStyle(.secondary)
                Slider(value: $hardness, in: 0...1).frame(width: 80)
                Text("\(Int((hardness * 100).rounded()))%")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            Divider().frame(height: 16)
            Button(action: { model.undoDefects(frame) }) { Image(systemName: "arrow.uturn.backward") }
                .help(model.text(AppLocalizedPhrase.undoDefectRemovalHelp))
                .disabled(!frame.canUndoDefects || frame.isRemovingDefects)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .adaptiveCapsuleSurface(.ultraThin)
        .padding(.top, 12)
    }
}

// MARK: 제스처/커서 레이어

/// 드래그·호버 @State 를 이 자식 뷰에 격리한다 — 매 마우스 틱마다 부모 오버레이(컨트롤 바 포함)가
/// 재평가되지 않는다. 스트로크가 끝날 때만 모델에 1회 반영한다.
private struct CloneStampGestureLayer: View {
    let frame: ScanFrame
    let model: AppModel
    let imageFrame: CGRect
    let referenceImage: NSImage?
    let sizePx: CGFloat
    let hardness: CGFloat
    @Binding var sourceBase: CGPoint?
    @Binding var alignedOffsetBase: CGVector?

    @State private var current: [CGPoint] = []   // 진행 중 스트로크(캔버스 좌표)
    @State private var hoverPoint: CGPoint?
    @State private var optionDown = false        // ⌥ 유지 중 = 소스 지정 모드(십자 커서)
    @State private var flagsMonitor: Any?

    var body: some View {
        ZStack {
            Canvas { ctx, _ in draw(&ctx) }
                .allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .named(canvasCoordinateSpace)) { phase in
                    switch phase {
                    case .active(let location): hoverPoint = location
                    case .ended: hoverPoint = nil
                    }
                }
                .gesture(sourceGesture.exclusively(before: paintGesture))
        }
        .onAppear {
            optionDown = NSEvent.modifierFlags.contains(.option)
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                optionDown = event.modifierFlags.contains(.option)
                return event
            }
        }
        .onDisappear {
            if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
            flagsMonitor = nil
        }
    }

    /// ⌥ 클릭 = 소스 지정. 새 소스는 정렬 오프셋도 초기화한다(다음 스트로크가 다시 확정).
    private var sourceGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .modifiers(.option)
            .onEnded { value in
                sourceBase = frame.imageTransform.displayUnitToBase(
                    unit(value.startLocation),
                    baseSize: model.sourcePixelSize(for: frame)
                )
                alignedOffsetBase = nil
            }
    }

    private var paintGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                guard sourceBase != nil else { return }
                current.append(value.location)
            }
            .onEnded { value in
                defer { current = [] }
                // 드래그 동안 호버 이벤트가 멈추므로, 종료 지점으로 갱신해 두지 않으면
                // 커서 링이 드래그 시작점(마지막 호버 위치)으로 되돌아가 보인다.
                hoverPoint = value.location
                guard let sourceBase, !current.isEmpty else { return }
                alignedOffsetBase = model.applyCloneStampStroke(
                    displayUnits: current.map(unit),
                    sourceBase: sourceBase,
                    existingOffset: alignedOffsetBase,
                    diameterPx: sizePx,
                    hardness: hardness,
                    to: frame
                )
            }
    }

    // MARK: 드로잉

    private func draw(_ ctx: inout GraphicsContext) {
        let diameter = screenDiameter
        let cursor = current.last ?? hoverPoint

        // ⌥ 유지 중 = 소스 지정 모드: 브러시 원 대신 십자 커서만 보여준다.
        if optionDown {
            if let sourceBase { drawCrosshair(&ctx, at: canvasPoint(fromBase: sourceBase)) }
            if let cursor { drawCrosshair(&ctx, at: cursor) }
            return
        }

        // 오프셋: 스트로크 중에는 첫 점 기준으로 고정, 그 외에는 커서 위치 기준
        // (정렬 전이면 원 안이 소스 지점을 그대로 보여준다).
        let anchor = current.first ?? cursor
        let offset = anchor.flatMap { displayOffset(forCursorAt: $0) }

        // 진행 중 스트로크: 소스 창의 실제 픽셀을 스트로크 모양으로 미리 보여준다.
        if !current.isEmpty, let offset, let referenceImage {
            var layer = ctx
            layer.clip(to: Path(imageFrame))
            layer.clip(to: strokeShape(current, diameter: diameter))
            layer.draw(Image(nsImage: referenceImage),
                       in: imageFrame.offsetBy(dx: -offset.width, dy: -offset.height))
        }

        if let p = cursor, imageFrame.insetBy(dx: -diameter, dy: -diameter).contains(p) {
            let rect = CGRect(x: p.x - diameter / 2, y: p.y - diameter / 2,
                              width: diameter, height: diameter)
            // 원 안에 복제될 소스 픽셀 미리보기(소스 지정 후).
            if sourceBase != nil, let offset, let referenceImage {
                var layer = ctx
                layer.clip(to: Path(ellipseIn: rect))
                layer.draw(Image(nsImage: referenceImage),
                           in: imageFrame.offsetBy(dx: -offset.width, dy: -offset.height))
            }
            ctx.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.55)), lineWidth: 2.5)
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)), lineWidth: 1)
        }

        // 샘플 위치 십자: 스트로크 중에는 커서를 따라가고, 그 외에는 지정된 소스에 표시.
        if !current.isEmpty, let offset, let last = current.last {
            drawCrosshair(&ctx, at: CGPoint(x: last.x + offset.width, y: last.y + offset.height))
        } else if let sourceBase {
            drawCrosshair(&ctx, at: canvasPoint(fromBase: sourceBase))
        }
    }

    private func strokeShape(_ pts: [CGPoint], diameter: CGFloat) -> Path {
        guard let first = pts.first else { return Path() }
        if pts.count == 1 {
            return Path(ellipseIn: CGRect(x: first.x - diameter / 2, y: first.y - diameter / 2,
                                          width: diameter, height: diameter))
        }
        var path = Path()
        path.move(to: first)
        for p in pts.dropFirst() { path.addLine(to: p) }
        return path.strokedPath(StrokeStyle(lineWidth: diameter, lineCap: .round, lineJoin: .round))
    }

    private func drawCrosshair(_ ctx: inout GraphicsContext, at p: CGPoint) {
        let arm: CGFloat = 7
        var path = Path()
        path.move(to: CGPoint(x: p.x - arm, y: p.y))
        path.addLine(to: CGPoint(x: p.x + arm, y: p.y))
        path.move(to: CGPoint(x: p.x, y: p.y - arm))
        path.addLine(to: CGPoint(x: p.x, y: p.y + arm))
        ctx.stroke(path, with: .color(.black.opacity(0.65)), lineWidth: 3)
        ctx.stroke(path, with: .color(.white.opacity(0.95)), lineWidth: 1.2)
    }

    /// 기준점 p 에서의 화면 오프셋(소스 표시점 − 대상 표시점). 정렬 오프셋이 있으면 그것을,
    /// 없으면 소스−p 를 쓴다. 변형이 affine 이라 스트로크 안에서 상수다 — 첫 점 기준 1회 계산.
    private func displayOffset(forCursorAt p: CGPoint) -> CGSize? {
        guard let sourceBase else { return nil }
        let baseSize = model.sourcePixelSize(for: frame)
        let transform = frame.imageTransform
        let cursorUnit = unit(p)
        let cursorBase = transform.displayUnitToBase(cursorUnit, baseSize: baseSize)
        let offset = alignedOffsetBase ?? CGVector(dx: sourceBase.x - cursorBase.x,
                                                   dy: sourceBase.y - cursorBase.y)
        let sourceUnit = transform.baseUnitToDisplay(
            CGPoint(x: cursorBase.x + offset.dx, y: cursorBase.y + offset.dy),
            baseSize: baseSize
        )
        let d0 = canvasPoint(fromUnit: cursorUnit)
        let ds = canvasPoint(fromUnit: sourceUnit)
        return CGSize(width: ds.x - d0.x, height: ds.y - d0.y)
    }

    // MARK: 좌표 변환

    private func unit(_ p: CGPoint) -> CGPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return .zero }
        return CGPoint(x: min(max((p.x - imageFrame.minX) / imageFrame.width, 0), 1),
                       y: min(max((p.y - imageFrame.minY) / imageFrame.height, 0), 1))
    }

    private func canvasPoint(fromUnit u: CGPoint) -> CGPoint {
        CGPoint(x: imageFrame.minX + u.x * imageFrame.width,
                y: imageFrame.minY + u.y * imageFrame.height)
    }

    private func canvasPoint(fromBase b: CGPoint) -> CGPoint {
        canvasPoint(fromUnit: frame.imageTransform.baseUnitToDisplay(
            b, baseSize: model.sourcePixelSize(for: frame)
        ))
    }

    /// raw 픽셀 → 화면 포인트 배율. 표시 픽셀 크기 기준이라 줌/크롭과 정합한다.
    private var pxToScreenScale: CGFloat {
        if let displayPixels = frame.displayPixelSize, displayPixels.width > 0 {
            return imageFrame.width / displayPixels.width
        }
        let base = model.sourcePixelSize(for: frame)
        let width: CGFloat
        switch frame.imageTransform.rotation {
        case .deg90, .deg270: width = base.height
        default: width = base.width
        }
        return imageFrame.width / max(width, 1)
    }

    private var screenDiameter: CGFloat {
        max(3, sizePx * pxToScreenScale)
    }
}
