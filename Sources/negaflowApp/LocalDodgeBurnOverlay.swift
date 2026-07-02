import SwiftUI
import Chromabase

enum LocalDodgeBurnToolShape: String, CaseIterable, Identifiable {
    case brush
    case radial
    case linear
    case polygon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .brush: return "Brush"
        case .radial: return "Radial"
        case .linear: return "Linear"
        case .polygon: return "Polygon"
        }
    }

    var systemImage: String {
        switch self {
        case .brush: return "paintbrush.pointed"
        case .radial: return "circle.dashed"
        case .linear: return "line.diagonal"
        case .polygon: return "pentagon"
        }
    }
}

struct LocalDodgeBurnOverlay: View {
    @Binding var shape: LocalDodgeBurnToolShape
    @Binding var brushStrokes: [LocalDodgeBurnStroke]
    @Binding var currentPoints: [LocalDodgeBurnPoint]
    @Binding var dragStart: LocalDodgeBurnPoint?
    @Binding var dragCurrent: LocalDodgeBurnPoint?
    @Binding var polygonPoints: [LocalDodgeBurnPoint]
    let mode: LocalDodgeBurnMode
    let thickness: Double
    let imageFrame: CGRect

    var body: some View {
        ZStack {
            Canvas { context, _ in
                drawDraft(in: &context)
            }
            .allowsHitTesting(false)

            interactionLayer
        }
    }

    @ViewBuilder
    private var interactionLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
                    .onChanged(handleChanged(_:))
                    .onEnded(handleEnded(_:))
            )
    }

    private func handleChanged(_ value: DragGesture.Value) {
        let point = unit(value.location)
        switch shape {
        case .brush:
            currentPoints.append(point)
        case .radial, .linear:
            if dragStart == nil {
                dragStart = unit(value.startLocation)
            }
            dragCurrent = point
        case .polygon:
            break
        }
    }

    private func handleEnded(_ value: DragGesture.Value) {
        let point = unit(value.location)
        switch shape {
        case .brush:
            if !currentPoints.isEmpty {
                brushStrokes.append(LocalDodgeBurnStroke(points: currentPoints, thickness: thickness))
                currentPoints = []
            }
        case .radial, .linear:
            if dragStart == nil {
                dragStart = unit(value.startLocation)
            }
            dragCurrent = point
        case .polygon:
            let movement = hypot(value.translation.width, value.translation.height)
            if movement < 6 {
                polygonPoints.append(point)
            }
        }
    }

    private func drawDraft(in context: inout GraphicsContext) {
        for stroke in brushStrokes {
            paintStroke(stroke.points, thickness: stroke.thickness, in: &context)
        }
        if !currentPoints.isEmpty {
            paintStroke(currentPoints, thickness: thickness, in: &context)
        }
        if let dragStart, let dragCurrent {
            switch shape {
            case .radial:
                paintRadial(start: dragStart, current: dragCurrent, in: &context)
            case .linear:
                paintLinear(start: dragStart, current: dragCurrent, in: &context)
            case .brush, .polygon:
                break
            }
        }
        if !polygonPoints.isEmpty {
            paintPolygon(points: polygonPoints, in: &context)
        }
    }

    private var tint: Color {
        mode == .dodge ? Color.white.opacity(0.46) : Color.black.opacity(0.46)
    }

    private var outline: Color {
        mode == .dodge ? Color.black.opacity(0.40) : Color.white.opacity(0.42)
    }

    private func unit(_ point: CGPoint) -> LocalDodgeBurnPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else {
            return LocalDodgeBurnPoint(x: 0, y: 0)
        }
        return LocalDodgeBurnPoint(
            x: min(max((point.x - imageFrame.minX) / imageFrame.width, 0), 1),
            y: min(max((point.y - imageFrame.minY) / imageFrame.height, 0), 1)
        )
    }

    private func canvasPoint(_ point: LocalDodgeBurnPoint) -> CGPoint {
        CGPoint(
            x: imageFrame.minX + point.x * imageFrame.width,
            y: imageFrame.minY + point.y * imageFrame.height
        )
    }

    private func paintStroke(_ points: [LocalDodgeBurnPoint], thickness: Double, in context: inout GraphicsContext) {
        guard let first = points.first else { return }
        let width = max(1, CGFloat(thickness) * min(imageFrame.width, imageFrame.height))
        if points.count == 1 {
            let center = canvasPoint(first)
            let radius = width / 2
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(tint))
            context.stroke(Path(ellipseIn: rect), with: .color(outline), lineWidth: 1)
            return
        }
        var path = Path()
        path.move(to: canvasPoint(first))
        for point in points.dropFirst() {
            path.addLine(to: canvasPoint(point))
        }
        context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
    }

    private func paintRadial(start: LocalDodgeBurnPoint, current: LocalDodgeBurnPoint, in context: inout GraphicsContext) {
        let a = canvasPoint(start)
        let b = canvasPoint(current)
        let radius = max(2, hypot(b.x - a.x, b.y - a.y))
        let rect = CGRect(x: a.x - radius, y: a.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(tint))
        context.stroke(Path(ellipseIn: rect), with: .color(outline), lineWidth: 1)
    }

    private func paintLinear(start: LocalDodgeBurnPoint, current: LocalDodgeBurnPoint, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: canvasPoint(start))
        path.addLine(to: canvasPoint(current))
        context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        context.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 1, lineCap: .round))
    }

    private func paintPolygon(points: [LocalDodgeBurnPoint], in context: inout GraphicsContext) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: canvasPoint(first))
        for point in points.dropFirst() {
            path.addLine(to: canvasPoint(point))
        }
        if points.count >= 3 {
            path.closeSubpath()
            context.fill(path, with: .color(tint))
        }
        context.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}

struct LocalDodgeBurnControlBar: View {
    @Binding var mode: LocalDodgeBurnMode
    @Binding var shape: LocalDodgeBurnToolShape
    @Binding var amount: Double
    @Binding var thickness: Double
    @Binding var feather: Double
    let appliedCount: Int
    let canApply: Bool
    let canUndoDraft: Bool
    let onApply: () -> Void
    let onUndo: () -> Void
    let onClearDraft: () -> Void
    let onResetApplied: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker("", selection: $mode) {
                Text("Dodge").tag(LocalDodgeBurnMode.dodge)
                Text("Burn").tag(LocalDodgeBurnMode.burn)
            }
            .pickerStyle(.segmented)
            .frame(width: 124)
            .labelsHidden()

            Menu {
                ForEach(LocalDodgeBurnToolShape.allCases) { option in
                    Button {
                        shape = option
                    } label: {
                        Label(option.label, systemImage: option.systemImage)
                    }
                }
            } label: {
                Label(shape.label, systemImage: shape.systemImage)
                    .frame(width: 94)
            }
            .menuStyle(.borderlessButton)

            compactSlider(systemName: "plusminus", value: $amount, range: 0.05...1, width: 100)
            if shape == .brush {
                compactSlider(systemName: "lineweight", value: $thickness, range: 0.004...0.16, width: 86)
            }
            compactSlider(systemName: "circle.dashed", value: $feather, range: 0...0.35, width: 86)

            Divider().frame(height: 16)
            Text("\(appliedCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 16)
            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                .help("마지막 드래프트 취소")
                .disabled(!canUndoDraft)
            Button(action: onClearDraft) { Image(systemName: "trash") }
                .help("드래프트 지우기")
                .disabled(!canUndoDraft)
            Button(action: onResetApplied) { Image(systemName: "arrow.counterclockwise") }
                .help("적용된 Dodge/Burn 초기화")
                .disabled(appliedCount == 0)
            Button(action: onApply) {
                Label("Apply", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canApply)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func compactSlider(
        systemName: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        width: CGFloat
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Slider(value: value, in: range)
                .frame(width: width)
        }
    }
}
