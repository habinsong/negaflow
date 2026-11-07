import AppKit
import Combine
import SwiftUI

enum CropHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

struct CropOverlay: View {
    @EnvironmentObject private var model: AppModel
    @Binding var cropRect: CGRect
    let imageFrame: CGRect
    let lockedAspectRatio: CGFloat?
    let straightenAngle: Double
    let onStraighten: (Double) -> Void
    let onApply: () -> Void
    let onReset: () -> Void
    let onCancel: () -> Void
    @State private var dragStartRect: CGRect?
    @State private var dragStartPoint: CGPoint?
    /// 기준선 드래그 중이면 시작점과 지금 점(캔버스 좌표).
    @State private var straightenLine: (start: CGPoint, end: CGPoint)?
    /// 이번 드래그가 기준선인지는 누르는 순간 한 번만 정한다. 끄는 도중 키를 떼거나 눌러도 바뀌지
    /// 않아야 사각형이 갑자기 움직이거나 선이 사라지지 않는다.
    @State private var dragIsStraightenLine: Bool?
    @StateObject private var modifierMonitor = ModifierKeyMonitor()

    var body: some View {
        let r = screenRect
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)
                .contentShape(Rectangle())
                .gesture(createGesture)
            Color.black.opacity(0.45)
                .allowsHitTesting(false)
                .mask {
                    GeometryReader { g in
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: g.size))
                            p.addRect(r)
                        }
                        .fill(style: FillStyle(eoFill: true))
                    }
                }
            selectionFrame(r)
                .allowsHitTesting(hasActiveCrop)
            if showsStraightenGrid {
                straightenGrid(r)
                    .allowsHitTesting(false)
            }
            ForEach(handlePoints(r), id: \.0) { handle, pt in
                handleView(for: handle)
                    .position(pt)
                    .gesture(handleGesture(handle))
            }
            if let line = straightenLine {
                straightenLineView(line)
                    .allowsHitTesting(false)
            }
            cropActionBar(r)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { modifierMonitor.start() }
        .onDisappear { modifierMonitor.stop() }
    }

    private var showsStraightenGrid: Bool {
        straightenLine != nil
            || model.gestureModifier(for: .straightenGrid).isHeld(in: modifierMonitor.flags)
    }

    /// 수평을 맞출 때 쓰는 촘촘한 격자. 3분할 안내선 위에 겹친다.
    private func straightenGrid(_ r: CGRect) -> some View {
        Path { p in
            let spacing: CGFloat = 24
            let columns = max(Int((r.width / spacing).rounded()), 4)
            let rows = max(Int((r.height / spacing).rounded()), 4)
            for i in 1..<columns {
                let x = r.minX + r.width * CGFloat(i) / CGFloat(columns)
                p.move(to: CGPoint(x: x, y: r.minY))
                p.addLine(to: CGPoint(x: x, y: r.maxY))
            }
            for i in 1..<rows {
                let y = r.minY + r.height * CGFloat(i) / CGFloat(rows)
                p.move(to: CGPoint(x: r.minX, y: y))
                p.addLine(to: CGPoint(x: r.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.42), lineWidth: 0.5)
        .shadow(color: .black.opacity(0.35), radius: 0, x: 0.5, y: 0.5)
    }

    private func straightenLineView(_ line: (start: CGPoint, end: CGPoint)) -> some View {
        let correction = CropOverlayGeometry.straightenCorrection(from: line.start, to: line.end)
        return ZStack {
            Path { p in
                p.move(to: line.start)
                p.addLine(to: line.end)
            }
            .stroke(Color.black.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Path { p in
                p.move(to: line.start)
                p.addLine(to: line.end)
            }
            .stroke(Color.yellow, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 3]))
            if let correction {
                Text(angleText(clampedStraighten(straightenAngle + correction)))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .canvasControlSurface(model.canvasBackground, cornerRadius: 6)
                    .position(x: line.end.x, y: line.end.y - 18)
            }
        }
    }

    private func angleText(_ value: Double) -> String {
        abs(value) < 0.05 ? "0.0°" : String(format: "%+.1f°", value)
    }

    private func clampedStraighten(_ value: Double) -> Double {
        min(max(value, -45), 45)
    }

    /// 누르는 순간 기준선 조합키가 눌려 있으면 이번 드래그는 사각형이 아니라 기준선이다.
    private func beginsStraightenLine() -> Bool {
        if let decided = dragIsStraightenLine { return decided }
        let decided = model.gestureModifier(for: .straightenWithLine).isHeld(in: NSEvent.modifierFlags)
        dragIsStraightenLine = decided
        return decided
    }

    private func updateStraightenLine(_ value: DragGesture.Value) {
        straightenLine = (clampedToImage(value.startLocation), clampedToImage(value.location))
    }

    private func finishStraightenLine() {
        defer {
            straightenLine = nil
            dragIsStraightenLine = nil
        }
        guard let line = straightenLine,
              let correction = CropOverlayGeometry.straightenCorrection(from: line.start, to: line.end)
        else { return }
        onStraighten(clampedStraighten(straightenAngle + correction))
    }

    private func clampedToImage(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, imageFrame.minX), imageFrame.maxX),
            y: min(max(point.y, imageFrame.minY), imageFrame.maxY)
        )
    }

    private func selectionFrame(_ r: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.white, lineWidth: 1.5)
            GeometryReader { g in
                let w = g.size.width / 3
                let h = g.size.height / 3
                Path { p in
                    for i in 1...2 {
                        p.move(to: CGPoint(x: w * CGFloat(i), y: 0))
                        p.addLine(to: CGPoint(x: w * CGFloat(i), y: g.size.height))
                        p.move(to: CGPoint(x: 0, y: h * CGFloat(i)))
                        p.addLine(to: CGPoint(x: g.size.width, y: h * CGFloat(i)))
                    }
                }
                .stroke(Color.white.opacity(0.34), lineWidth: 0.5)
            }
        }
        .frame(width: r.width, height: r.height)
        .contentShape(Rectangle())
        .position(x: r.midX, y: r.midY)
        .gesture(moveGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.text(AppLocalizedPhrase.cropArea))
        .accessibilityValue(cropAccessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: resizeCrop(0.02)
            case .decrement: resizeCrop(-0.02)
            @unknown default: break
            }
        }
        .accessibilityAction(named: Text(model.accessibilityText(.moveLeft))) {
            moveCrop(dx: -0.01, dy: 0)
        }
        .accessibilityAction(named: Text(model.accessibilityText(.moveRight))) {
            moveCrop(dx: 0.01, dy: 0)
        }
        .accessibilityAction(named: Text(model.accessibilityText(.moveUp))) {
            moveCrop(dx: 0, dy: -0.01)
        }
        .accessibilityAction(named: Text(model.accessibilityText(.moveDown))) {
            moveCrop(dx: 0, dy: 0.01)
        }
        .focusable()
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { handleCropKey(dx: -1, dy: 0, press: $0) }
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { handleCropKey(dx: 1, dy: 0, press: $0) }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { handleCropKey(dx: 0, dy: -1, press: $0) }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { handleCropKey(dx: 0, dy: 1, press: $0) }
    }

    private func handleView(for handle: CropHandle) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black.opacity(0.4), lineWidth: 1))
            .frame(
                width: (handle == .top || handle == .bottom) ? 24 : 14,
                height: (handle == .left || handle == .right) ? 24 : 14
            )
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
    }

    private func cropActionBar(_ r: CGRect) -> some View {
        HStack(spacing: 6) {
            Button(model.text(AppLocalizedPhrase.apply), action: onApply)
                .buttonStyle(.borderedProminent)
            Button(model.text(AppLocalizedPhrase.full), action: onReset)
            Button(model.text(AppLocalizedPhrase.cancel), action: onCancel)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // 글래스가 아니라 캔버스 배경에서 유도한 불투명 면을 쓴다 — 줌 HUD 와 같은 표면이다.
        // 글래스는 뒤의 캔버스 색을 그대로 통과시켜, 배경을 흰색으로 두면 버튼과 글자가 함께
        // 흰색이 돼 읽히지 않는다. 버튼 구성·순서·라벨·배치는 그대로 둔다.
        .canvasControlSurface(model.canvasBackground, cornerRadius: 8)
        .position(
            x: min(max(r.midX, imageFrame.minX + 86), imageFrame.maxX - 86),
            y: min(max(r.maxY + 30, imageFrame.minY + 28), imageFrame.maxY - 28)
        )
    }

    var screenRect: CGRect {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return .zero }
        return CGRect(
            x: imageFrame.minX + cropRect.minX * imageFrame.width,
            y: imageFrame.minY + cropRect.minY * imageFrame.height,
            width: cropRect.width * imageFrame.width,
            height: cropRect.height * imageFrame.height
        )
    }

    var hasActiveCrop: Bool {
        cropRect.width < 0.995 || cropRect.height < 0.995
    }

    private func handlePoints(_ r: CGRect) -> [(CropHandle, CGPoint)] {
        [
            (.topLeft, CGPoint(x: r.minX, y: r.minY)),
            (.top, CGPoint(x: r.midX, y: r.minY)),
            (.topRight, CGPoint(x: r.maxX, y: r.minY)),
            (.right, CGPoint(x: r.maxX, y: r.midY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)),
            (.bottom, CGPoint(x: r.midX, y: r.maxY)),
            (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)),
            (.left, CGPoint(x: r.minX, y: r.midY))
        ]
    }

    var createGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                if beginsStraightenLine() {
                    updateStraightenLine(value)
                    return
                }
                if dragStartPoint == nil {
                    dragStartPoint = unitPoint(value.startLocation)
                }
                guard let start = dragStartPoint else { return }
                cropRect = cropSelectionRect(from: start, to: unitPoint(value.location))
            }
            .onEnded { _ in
                if dragIsStraightenLine == true {
                    finishStraightenLine()
                    return
                }
                dragIsStraightenLine = nil
                dragStartPoint = nil
            }
    }

    var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                if beginsStraightenLine() {
                    updateStraightenLine(value)
                    return
                }
                if dragStartRect == nil {
                    dragStartRect = cropRect
                }
                guard let start = dragStartRect, imageFrame.width > 0, imageFrame.height > 0 else { return }
                let dx = value.translation.width / imageFrame.width
                let dy = value.translation.height / imageFrame.height
                cropRect = movedRect(start.offsetBy(dx: dx, dy: dy))
            }
            .onEnded { _ in
                if dragIsStraightenLine == true {
                    finishStraightenLine()
                    return
                }
                dragIsStraightenLine = nil
                dragStartRect = nil
            }
    }

    private func handleGesture(_ handle: CropHandle) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                // 손잡이는 늘 크기 조절이다. 기준선은 사진이나 선택 영역 위에서 시작한다.
                dragIsStraightenLine = false
                if dragStartRect == nil {
                    dragStartRect = cropRect
                }
                guard let start = dragStartRect else { return }
                let p = unitPoint(value.location)
                var next = start
                if let unitAspectRatio {
                    next = CropOverlayGeometry.lockedHandleRect(
                        handle,
                        start: start,
                        point: p,
                        unitAspectRatio: unitAspectRatio
                    )
                } else {
                    switch handle {
                    case .topLeft:
                        next = CGRect(x: p.x, y: p.y, width: start.maxX - p.x, height: start.maxY - p.y)
                    case .top:
                        next = CGRect(x: start.minX, y: p.y, width: start.width, height: start.maxY - p.y)
                    case .topRight:
                        next = CGRect(x: start.minX, y: p.y, width: p.x - start.minX, height: start.maxY - p.y)
                    case .right:
                        next = CGRect(x: start.minX, y: start.minY, width: p.x - start.minX, height: start.height)
                    case .bottomRight:
                        next = CGRect(x: start.minX, y: start.minY, width: p.x - start.minX, height: p.y - start.minY)
                    case .bottom:
                        next = CGRect(x: start.minX, y: start.minY, width: start.width, height: p.y - start.minY)
                    case .bottomLeft:
                        next = CGRect(x: p.x, y: start.minY, width: start.maxX - p.x, height: p.y - start.minY)
                    case .left:
                        next = CGRect(x: p.x, y: start.minY, width: start.maxX - p.x, height: start.height)
                    }
                }
                cropRect = clampedUnitRect(next)
            }
            .onEnded { _ in
                dragIsStraightenLine = nil
                dragStartRect = nil
            }
    }

    private func unitPoint(_ point: CGPoint) -> CGPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return .zero }
        return CGPoint(
            x: min(max((point.x - imageFrame.minX) / imageFrame.width, 0), 1),
            y: min(max((point.y - imageFrame.minY) / imageFrame.height, 0), 1)
        )
    }

    private func movedRect(_ rect: CGRect) -> CGRect {
        let width = min(max(rect.width, 0.035), 1)
        let height = min(max(rect.height, 0.035), 1)
        return CGRect(
            x: min(max(rect.minX, 0), 1 - width),
            y: min(max(rect.minY, 0), 1 - height),
            width: width,
            height: height
        )
    }

    private var cropAccessibilityValue: String {
        model.accessibilityText(
            .cropValueFormat,
            Int((cropRect.minX * 100).rounded()),
            Int((cropRect.minY * 100).rounded()),
            Int((cropRect.width * 100).rounded()),
            Int((cropRect.height * 100).rounded())
        )
    }

    private func handleCropKey(dx: CGFloat, dy: CGFloat, press: KeyPress) -> KeyPress.Result {
        let step: CGFloat = press.modifiers.contains(.shift) ? 0.02 : 0.005
        moveCrop(dx: dx * step, dy: dy * step)
        return .handled
    }

    private func moveCrop(dx: CGFloat, dy: CGFloat) {
        cropRect = CropAccessibilityEditing.move(cropRect, dx: dx, dy: dy)
    }

    private func resizeCrop(_ delta: CGFloat) {
        cropRect = CropAccessibilityEditing.resize(cropRect, scaleDelta: delta)
    }

    private var unitAspectRatio: CGFloat? {
        guard let lockedAspectRatio,
              lockedAspectRatio > 0,
              lockedAspectRatio.isFinite,
              imageFrame.width > 0,
              imageFrame.height > 0 else { return nil }
        return lockedAspectRatio / (imageFrame.width / imageFrame.height)
    }

    private func cropSelectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CropOverlayGeometry.selectionRect(
            from: start,
            to: end,
            unitAspectRatio: unitAspectRatio
        )
    }
}

/// 조합키만 누르고 떼는 것은 키 이벤트가 아니라서 SwiftUI 가 알려 주지 않는다. 크롭 화면이 떠
/// 있는 동안만 이 앱의 flagsChanged 를 듣는다.
@MainActor
final class ModifierKeyMonitor: ObservableObject {
    @Published private(set) var flags: NSEvent.ModifierFlags = []
    private var monitor: Any?

    func start() {
        flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { @MainActor [weak self] event in
            self?.flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        flags = []
    }
}
