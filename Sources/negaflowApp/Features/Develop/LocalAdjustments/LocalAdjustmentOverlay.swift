import SwiftUI
import Chromabase

struct LocalAdjustmentOverlay: View {
    @ObservedObject var frame: ScanFrame
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: LocalAdjustmentSession
    let imageFrame: CGRect

    @State private var dragStart: CGPoint?
    @State private var dragPoints: [CGPoint] = []

    var body: some View {
        ZStack(alignment: .top) {
            maskCanvas
            gestureLayer
            promptBar
        }
        .onExitCommand { session.deactivate() }
    }

    private var maskCanvas: some View {
        Canvas { context, _ in
            for adjustment in frame.params.localDodgeBurn {
                draw(adjustment, in: &context)
            }
            drawDraft(in: &context)
        }
        .allowsHitTesting(false)
    }

    private var gestureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: imageFrame.width, height: imageFrame.height)
            .position(x: imageFrame.midX, y: imageFrame.midY)
            .gesture(activeGesture)
    }

    private var activeGesture: some Gesture {
        DragGesture(minimumDistance: session.maskKind == .polygon ? 0 : 2, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                guard session.maskKind != .polygon else { return }
                if dragStart == nil { dragStart = value.startLocation }
                if session.maskKind == .brush {
                    if dragPoints.last.map({ hypot($0.x - value.location.x, $0.y - value.location.y) >= 2 }) ?? true {
                        dragPoints.append(value.location)
                    }
                } else {
                    dragPoints = [value.startLocation, value.location]
                }
            }
            .onEnded { value in
                if session.maskKind == .polygon {
                    session.polygonPoints.append(basePoint(value.location))
                } else {
                    finishDrag(at: value.location)
                }
            }
    }

    private var promptBar: some View {
        HStack(spacing: 8) {
            Image(systemName: session.maskKind.systemImage)
            Text(localized(.drawPrompt))
            if session.maskKind == .polygon, session.polygonPoints.count >= 3 {
                Button(localized(.finishPolygon), action: finishPolygon)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Button { session.deactivate() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .liquidSurface(cornerRadius: 9, interactive: true)
        .padding(.top, 12)
    }

    private func finishDrag(at location: CGPoint) {
        defer { dragStart = nil; dragPoints.removeAll() }
        let points = dragPoints.isEmpty ? [location] : dragPoints
        let basePoints = session.maskKind == .brush
            ? points.map(basePoint)
            : [basePoint(dragStart ?? location), basePoint(location)]
        guard let mask = LocalAdjustmentMaskFactory.make(
            kind: session.maskKind,
            points: basePoints,
            thickness: session.brushThickness,
            feather: session.feather,
            imageSize: baseSize
        ) else { return }
        let adjustment = session.makeAdjustment(mask: mask)
        model.addLocalAdjustment(adjustment, to: frame)
        session.selectedAdjustmentID = adjustment.id
    }

    private func finishPolygon() {
        guard session.polygonPoints.count >= 3 else { return }
        guard let mask = LocalAdjustmentMaskFactory.make(
            kind: .polygon,
            points: session.polygonPoints,
            thickness: session.brushThickness,
            feather: session.feather,
            imageSize: baseSize
        ) else { return }
        let adjustment = session.makeAdjustment(mask: mask)
        model.addLocalAdjustment(adjustment, to: frame)
        session.selectedAdjustmentID = adjustment.id
        session.polygonPoints.removeAll()
    }

    private func draw(_ adjustment: LocalDodgeBurnAdjustment, in context: inout GraphicsContext) {
        let selected = adjustment.id == session.selectedAdjustmentID
        let color = adjustment.isEnabled
            ? (adjustment.mode == .dodge ? Color.yellow : Color.cyan)
            : Color.gray
        let opacity = selected ? 0.95 : 0.42
        switch adjustment.mask.kind {
        case .brush:
            for stroke in adjustment.mask.strokes {
                strokePath(stroke.points.map(screenPoint), width: stroke.thickness * min(imageFrame.width, imageFrame.height), color: color.opacity(opacity), context: &context)
            }
        case .radial:
            let samples = (0..<48).map { index -> LocalDodgeBurnPoint in
                let angle = Double(index) / 48 * .pi * 2
                return radialBoundaryPoint(
                    center: adjustment.mask.center,
                    radius: adjustment.mask.radius,
                    angle: angle
                )
            }
            closedPath(samples.map(screenPoint), color: color.opacity(opacity), context: &context)
        case .linear:
            strokePath([screenPoint(adjustment.mask.start), screenPoint(adjustment.mask.end)], width: selected ? 2 : 1, color: color.opacity(opacity), context: &context)
        case .polygon:
            closedPath(adjustment.mask.points.map(screenPoint), color: color.opacity(opacity), context: &context)
        }
    }

    private func drawDraft(in context: inout GraphicsContext) {
        if session.maskKind == .polygon {
            strokePath(session.polygonPoints.map(screenPoint), width: 2, color: .white.opacity(0.9), context: &context)
        } else {
            strokePath(dragPoints, width: max(2, session.brushThickness * min(imageFrame.width, imageFrame.height)), color: .white.opacity(0.8), context: &context)
        }
    }

    private func strokePath(_ points: [CGPoint], width: CGFloat, color: Color, context: inout GraphicsContext) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(1, width), lineCap: .round, lineJoin: .round))
    }

    private func closedPath(_ points: [CGPoint], color: Color, context: inout GraphicsContext) {
        guard points.count >= 2 else { return }
        var path = Path()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
    }

    private var baseSize: CGSize? {
        guard let width = frame.sourcePixelWidth, let height = frame.sourcePixelHeight else { return nil }
        return CGSize(width: width, height: height)
    }

    private func basePoint(_ screen: CGPoint) -> LocalDodgeBurnPoint {
        let display = CGPoint(
            x: min(max((screen.x - imageFrame.minX) / max(imageFrame.width, 1), 0), 1),
            y: min(max((screen.y - imageFrame.minY) / max(imageFrame.height, 1), 0), 1)
        )
        let base = frame.imageTransform.displayUnitToBase(display, baseSize: baseSize)
        return LocalDodgeBurnPoint(x: min(max(base.x, 0), 1), y: min(max(base.y, 0), 1))
    }

    private func screenPoint(_ point: LocalDodgeBurnPoint) -> CGPoint {
        let display = frame.imageTransform.baseUnitToDisplay(CGPoint(x: point.x, y: point.y), baseSize: baseSize)
        return CGPoint(x: imageFrame.minX + display.x * imageFrame.width, y: imageFrame.minY + display.y * imageFrame.height)
    }

    private func radialBoundaryPoint(
        center: LocalDodgeBurnPoint,
        radius: Double,
        angle: Double
    ) -> LocalDodgeBurnPoint {
        guard let baseSize, baseSize.width > 0, baseSize.height > 0 else {
            return LocalDodgeBurnPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
        let minimumDimension = min(baseSize.width, baseSize.height)
        return LocalDodgeBurnPoint(
            x: center.x + cos(angle) * radius * minimumDimension / baseSize.width,
            y: center.y + sin(angle) * radius * minimumDimension / baseSize.height
        )
    }

    private func localized(_ text: LocalAdjustmentLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}
