import AppKit
import SwiftUI

enum FlatbedRegionHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

enum FlatbedScanAreaOverlayGeometry {
    static func canBeginCreation(
        at point: CGPoint,
        existingRects: [CGRect],
        exclusionPadding: CGFloat = 12
    ) -> Bool {
        !existingRects.contains {
            $0.insetBy(dx: -exclusionPadding, dy: -exclusionPadding).contains(point)
        }
    }

    static func resizedRect(
        from start: CGRect,
        toward point: CGPoint,
        handle: FlatbedRegionHandle,
        within bounds: CGRect,
        minimumSize: CGFloat = 12
    ) -> CGRect {
        let pointX = min(max(point.x, bounds.minX), bounds.maxX)
        let pointY = min(max(point.y, bounds.minY), bounds.maxY)
        var minX = max(start.minX, bounds.minX)
        var maxX = min(start.maxX, bounds.maxX)
        var minY = max(start.minY, bounds.minY)
        var maxY = min(start.maxY, bounds.maxY)
        let minimumWidth = min(max(minimumSize, 0), bounds.width)
        let minimumHeight = min(max(minimumSize, 0), bounds.height)

        switch handle {
        case .topLeft:
            minX = min(pointX, max(bounds.minX, maxX - minimumWidth))
            minY = min(pointY, max(bounds.minY, maxY - minimumHeight))
        case .top:
            minY = min(pointY, max(bounds.minY, maxY - minimumHeight))
        case .topRight:
            maxX = max(pointX, min(bounds.maxX, minX + minimumWidth))
            minY = min(pointY, max(bounds.minY, maxY - minimumHeight))
        case .right:
            maxX = max(pointX, min(bounds.maxX, minX + minimumWidth))
        case .bottomRight:
            maxX = max(pointX, min(bounds.maxX, minX + minimumWidth))
            maxY = max(pointY, min(bounds.maxY, minY + minimumHeight))
        case .bottom:
            maxY = max(pointY, min(bounds.maxY, minY + minimumHeight))
        case .bottomLeft:
            minX = min(pointX, max(bounds.minX, maxX - minimumWidth))
            maxY = max(pointY, min(bounds.maxY, minY + minimumHeight))
        case .left:
            minX = min(pointX, max(bounds.minX, maxX - minimumWidth))
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func handlePoint(_ handle: FlatbedRegionHandle, in size: CGSize) -> CGPoint {
        switch handle {
        case .topLeft: return .zero
        case .top: return CGPoint(x: size.width / 2, y: 0)
        case .topRight: return CGPoint(x: size.width, y: 0)
        case .right: return CGPoint(x: size.width, y: size.height / 2)
        case .bottomRight: return CGPoint(x: size.width, y: size.height)
        case .bottom: return CGPoint(x: size.width / 2, y: size.height)
        case .bottomLeft: return CGPoint(x: 0, y: size.height)
        case .left: return CGPoint(x: 0, y: size.height / 2)
        }
    }
}

struct FlatbedScanAreaOverlay: View {
    @ObservedObject var frame: ScanFrame
    @EnvironmentObject private var model: AppModel
    let imageFrame: CGRect
    @State private var createStartPoint: CGPoint?
    @State private var createCurrentPoint: CGPoint?
    @State private var dragStartRect: CGRect?
    /// 프레임 편집 단축키는 이 오버레이가 포커스를 가진 동안에만 산다. ⌘C/⌘V 가 텍스트 필드의
    /// 복사·붙여넣기를 빼앗지 않게 하는 유일하게 확실한 방법이다.
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)
                .contentShape(Rectangle())
                .gesture(createGesture)

            if let start = createStartPoint, let current = createCurrentPoint {
                let rect = screenRect(for: createdUnitRect(from: start, to: current))
                Rectangle()
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay {
                        Rectangle()
                            .stroke(
                                Color.accentColor,
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                            )
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }

            ForEach(Array(model.flatbedScanRegions.enumerated()), id: \.element.id) { index, region in
                regionView(region, number: index + 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        // 이 뷰는 프리뷰 영역을 가득 채운다. 포커스 링을 그대로 두면 프레임을 하나 집는
        // 순간 화면 테두리를 따라 파란 사각형이 그려져, 스캔 영역의 경계처럼 보인다.
        // 포커스는 방향키 미세이동과 ⌘C/⌘V 에 필요하므로 표시만 끈다. 어느 프레임이
        // 선택됐는지는 프레임 자신의 강조색 테두리가 이미 알려 준다.
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { nudge(dx: -1, dy: 0, press: $0) }
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { nudge(dx: 1, dy: 0, press: $0) }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { nudge(dx: 0, dy: -1, press: $0) }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { nudge(dx: 0, dy: 1, press: $0) }
        .background { frameClipboardShortcuts }
    }

    /// ⌘C/⌘V. 포커스가 없으면 비활성이라 키 이벤트가 그대로 responder chain 으로 흘러간다 —
    /// 사이드바 텍스트 필드에서 복사·붙여넣기는 평소대로 동작한다.
    private var frameClipboardShortcuts: some View {
        Group {
            Button("") { model.copySelectedFlatbedScanRegion() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(!isFocused || model.selectedFlatbedScanRegion == nil)

            Button("") { model.pasteFlatbedScanRegion() }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(!isFocused || !model.canPasteFlatbedScanRegion)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func nudge(dx: CGFloat, dy: CGFloat, press: KeyPress) -> KeyPress.Result {
        guard model.selectedFlatbedScanRegion != nil else { return .ignored }
        model.nudgeSelectedFlatbedScanRegion(
            dx: dx,
            dy: dy,
            coarse: press.modifiers.contains(.shift)
        )
        return .handled
    }

    private func regionView(_ region: FlatbedScanRegion, number: Int) -> some View {
        let rect = screenRect(for: region.unitRect)
        let selected = model.selectedFlatbedScanRegionID == region.id
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(selected ? Color.accentColor.opacity(0.09) : Color.black.opacity(0.04))
            Rectangle()
                .stroke(selected ? Color.accentColor : Color.white, lineWidth: selected ? 2 : 1)
            Text(number, format: .number)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(selected ? Color.accentColor : Color.white.opacity(0.82), in: Capsule())
                .padding(5)
                .allowsHitTesting(false)
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.selectFlatbedScanRegion(region.id)
                    isFocused = true
                }
                .gesture(moveGesture(for: region))
            if selected {
                ForEach(FlatbedRegionHandle.allCases, id: \.self) { handle in
                    handleView(handle)
                        .position(FlatbedScanAreaOverlayGeometry.handlePoint(
                            handle,
                            in: rect.size
                        ))
                        .gesture(resizeGesture(for: region, handle: handle))
                }
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.text(AppLocalizedPhrase.flatbedFrameFormat, number))
        .accessibilityAction(named: Text(model.accessibilityText(.moveLeft))) {
            moveByAccessibility(region, dx: -1, dy: 0)
        }
        .accessibilityAction(named: Text(model.accessibilityText(.moveRight))) {
            moveByAccessibility(region, dx: 1, dy: 0)
        }
        .accessibilityAction(named: Text(model.accessibilityText(.moveUp))) {
            moveByAccessibility(region, dx: 0, dy: -1)
        }
        .accessibilityAction(named: Text(model.accessibilityText(.moveDown))) {
            moveByAccessibility(region, dx: 0, dy: 1)
        }
    }

    private func moveByAccessibility(_ region: FlatbedScanRegion, dx: CGFloat, dy: CGFloat) {
        model.selectFlatbedScanRegion(region.id)
        model.nudgeSelectedFlatbedScanRegion(dx: dx, dy: dy)
    }

    private func handleView(_ handle: FlatbedRegionHandle) -> some View {
        let size: CGSize
        switch handle {
        case .top, .bottom:
            size = CGSize(width: 18, height: 8)
        case .left, .right:
            size = CGSize(width: 8, height: 18)
        default:
            size = CGSize(width: 12, height: 12)
        }
        return RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.accentColor, lineWidth: 1))
            .frame(width: size.width, height: size.height)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }

    private var createGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                if createStartPoint == nil {
                    guard FlatbedScanAreaOverlayGeometry.canBeginCreation(
                        at: value.startLocation,
                        existingRects: model.flatbedScanRegions.map { screenRect(for: $0.unitRect) }
                    ) else { return }
                    createStartPoint = basePoint(value.startLocation)
                }
                createCurrentPoint = basePoint(value.location)
            }
            .onEnded { value in
                defer {
                    createStartPoint = nil
                    createCurrentPoint = nil
                }
                guard let start = createStartPoint else { return }
                model.addFlatbedScanRegion(
                    unitRect: createdUnitRect(from: start, to: basePoint(value.location))
                )
                isFocused = true
            }
    }

    private func moveGesture(for region: FlatbedScanRegion) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                if dragStartRect == nil { dragStartRect = screenRect(for: region.unitRect) }
                guard let start = dragStartRect else { return }
                let moved = clampedScreenRect(start.offsetBy(
                    dx: value.translation.width,
                    dy: value.translation.height
                ))
                model.updateFlatbedScanRegion(region.id, unitRect: baseRect(from: moved))
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func resizeGesture(
        for region: FlatbedScanRegion,
        handle: FlatbedRegionHandle
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                if dragStartRect == nil { dragStartRect = screenRect(for: region.unitRect) }
                guard let start = dragStartRect else { return }
                let proposed = FlatbedScanAreaOverlayGeometry.resizedRect(
                    from: start,
                    toward: value.location,
                    handle: handle,
                    within: imageFrame
                )
                model.updateFlatbedScanRegion(
                    region.id,
                    unitRect: frameAspectAdjusted(
                        baseRect(from: proposed),
                        anchoredTo: baseRect(from: start)
                    )
                )
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func createdUnitRect(from start: CGPoint, to current: CGPoint) -> CGRect {
        frameAspectAdjusted(
            unitRect(from: start, to: current),
            anchoredTo: CGRect(origin: start, size: .zero)
        )
    }

    /// 규격 비율로 맞춘다. ⌥를 누르고 있으면 자유 비율(규격 목록에 없는 필름용 탈출구).
    private func frameAspectAdjusted(_ rect: CGRect, anchoredTo previous: CGRect) -> CGRect {
        guard let previewArea = model.flatbedPreviewScanArea,
              !NSEvent.modifierFlags.contains(.option) else { return rect }
        return clampedUnitRect(FlatbedScanRegionLayout.snappedToFrameAspect(
            rect,
            anchoredTo: previous,
            frameFormat: model.scanFrameFormat,
            previewArea: previewArea
        ))
    }

    private func screenRect(for baseRect: CGRect) -> CGRect {
        let points = corners(of: baseRect).map { point -> CGPoint in
            let display = frame.imageTransform.baseUnitToDisplay(point, baseSize: baseSize)
            return CGPoint(
                x: imageFrame.minX + display.x * imageFrame.width,
                y: imageFrame.minY + display.y * imageFrame.height
            )
        }
        return boundingRect(points)
    }

    private func baseRect(from screenRect: CGRect) -> CGRect {
        let points = corners(of: screenRect).map { point -> CGPoint in
            let display = CGPoint(
                x: (point.x - imageFrame.minX) / max(imageFrame.width, 1),
                y: (point.y - imageFrame.minY) / max(imageFrame.height, 1)
            )
            return frame.imageTransform.displayUnitToBase(display, baseSize: baseSize)
        }
        return clampedUnitRect(boundingRect(points))
    }

    private func basePoint(_ point: CGPoint) -> CGPoint {
        let display = CGPoint(
            x: min(max((point.x - imageFrame.minX) / max(imageFrame.width, 1), 0), 1),
            y: min(max((point.y - imageFrame.minY) / max(imageFrame.height, 1), 0), 1)
        )
        let base = frame.imageTransform.displayUnitToBase(display, baseSize: baseSize)
        return CGPoint(x: min(max(base.x, 0), 1), y: min(max(base.y, 0), 1))
    }

    private var baseSize: CGSize? {
        guard let width = frame.sourcePixelWidth,
              let height = frame.sourcePixelHeight,
              width > 0,
              height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private func clampedScreenRect(_ rect: CGRect) -> CGRect {
        let minimum: CGFloat = 12
        let width = min(max(rect.width, minimum), imageFrame.width)
        let height = min(max(rect.height, minimum), imageFrame.height)
        return CGRect(
            x: min(max(rect.minX, imageFrame.minX), imageFrame.maxX - width),
            y: min(max(rect.minY, imageFrame.minY), imageFrame.maxY - height),
            width: width,
            height: height
        )
    }

    private func corners(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
    }

    private func boundingRect(_ points: [CGPoint]) -> CGRect {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else {
            return .zero
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
