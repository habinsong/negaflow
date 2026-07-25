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
    let onApply: () -> Void
    let onReset: () -> Void
    let onCancel: () -> Void
    @State private var dragStartRect: CGRect?
    @State private var dragStartPoint: CGPoint?

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
            ForEach(handlePoints(r), id: \.0) { handle, pt in
                handleView(for: handle)
                    .position(pt)
                    .gesture(handleGesture(handle))
            }
            cropActionBar(r)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .liquidSurface(cornerRadius: 8, interactive: true)
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
                if dragStartPoint == nil {
                    dragStartPoint = unitPoint(value.startLocation)
                }
                guard let start = dragStartPoint else { return }
                cropRect = cropSelectionRect(from: start, to: unitPoint(value.location))
            }
            .onEnded { _ in
                dragStartPoint = nil
            }
    }

    var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                if dragStartRect == nil {
                    dragStartRect = cropRect
                }
                guard let start = dragStartRect, imageFrame.width > 0, imageFrame.height > 0 else { return }
                let dx = value.translation.width / imageFrame.width
                let dy = value.translation.height / imageFrame.height
                cropRect = movedRect(start.offsetBy(dx: dx, dy: dy))
            }
            .onEnded { _ in
                dragStartRect = nil
            }
    }

    private func handleGesture(_ handle: CropHandle) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
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
