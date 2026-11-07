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
    @State private var dragStartShape: FlatbedRegionScreenShape?
    @State private var dragStartRegion: FlatbedScanRegion?
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
                let shape = shape(for: createdRegion(from: start, to: current))
                Rectangle()
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay {
                        Rectangle()
                            .stroke(
                                Color.accentColor,
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                            )
                    }
                    .frame(width: shape.size.width, height: shape.size.height)
                    .rotationEffect(.radians(Double(shape.angle)))
                    .position(shape.center)
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
        let shape = shape(for: region)
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
                            in: shape.size
                        ))
                        .gesture(resizeGesture(for: region, handle: handle))
                }
            }
        }
        .frame(width: shape.size.width, height: shape.size.height)
        .rotationEffect(.radians(Double(shape.angle)))
        .position(shape.center)
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
                        existingRects: model.flatbedScanRegions.map { shape(for: $0).boundingRect }
                    ) else { return }
                    createStartPoint = clampedScreenPoint(value.startLocation)
                }
                createCurrentPoint = clampedScreenPoint(value.location)
            }
            .onEnded { value in
                defer {
                    createStartPoint = nil
                    createCurrentPoint = nil
                }
                guard let start = createStartPoint else { return }
                let region = createdRegion(from: start, to: clampedScreenPoint(value.location))
                model.addFlatbedScanRegion(
                    unitRect: region.unitRect,
                    straightenAngle: region.straightenAngle
                )
                isFocused = true
            }
    }

    /// 누르기만 하면 아무것도 바꾸지 않는다. 예전에는 누르는 순간 이동 0 으로 자리를 다시 써서
    /// 경계 상자 왕복만큼 프레임이 커지고, 검출이 잰 기울기도 0 으로 지워졌다.
    private func moveGesture(for region: FlatbedScanRegion) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                if dragStartShape == nil {
                    dragStartShape = shape(for: region)
                    dragStartRegion = region
                }
                guard let start = dragStartShape,
                      hypot(value.translation.width, value.translation.height) >= 0.5 else { return }
                var moved = start
                moved.center.x += value.translation.width
                moved.center.y += value.translation.height
                model.updateFlatbedScanRegion(region.id, unitRect: unitRect(for: moved))
            }
            .onEnded { _ in
                dragStartShape = nil
                dragStartRegion = nil
            }
    }

    private func resizeGesture(
        for region: FlatbedScanRegion,
        handle: FlatbedRegionHandle
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                if dragStartShape == nil {
                    dragStartShape = shape(for: region)
                    dragStartRegion = region
                }
                guard let start = dragStartShape,
                      let startRegion = dragStartRegion,
                      hypot(value.translation.width, value.translation.height) >= 0.5 else { return }
                let localStart = CGRect(origin: .zero, size: start.size)
                let proposed = FlatbedScanAreaOverlayGeometry.resizedRect(
                    from: localStart,
                    toward: start.localPoint(screen: value.location),
                    handle: handle,
                    within: localImageBounds(for: start)
                )
                let resized = unitRect(for: start.reshaped(localRect: proposed))
                model.updateFlatbedScanRegion(
                    region.id,
                    unitRect: frameAspectAdjusted(
                        resized,
                        angle: startRegion.straightenAngle,
                        anchoredTo: FlatbedScanRegionFrameGeometry.frameLocalRect(
                            unitRect: startRegion.unitRect,
                            straightenAngle: startRegion.straightenAngle,
                            localAngle: startRegion.straightenAngle,
                            baseSize: baseSize
                        )
                    )
                )
            }
            .onEnded { _ in
                dragStartShape = nil
                dragStartRegion = nil
            }
    }

    /// 화면에서 수평으로 그린 사각형을 프레임으로. 각도는 지금 화면 방향(`flatbedNewRegionAngle`)이다.
    private func createdRegion(from start: CGPoint, to current: CGPoint) -> FlatbedScanRegion {
        let angle = model.flatbedNewRegionAngle
        let screenRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        let drawn = unitRect(for: FlatbedRegionScreenShape(
            center: CGPoint(x: screenRect.midX, y: screenRect.midY),
            size: screenRect.size,
            angle: 0
        ))
        let startDisplay = CGPoint(
            x: (start.x - imageFrame.minX) / max(imageFrame.width, 1),
            y: (start.y - imageFrame.minY) / max(imageFrame.height, 1)
        )
        let startBase = frame.imageTransform.displayUnitToBase(startDisplay, baseSize: baseSize)
        let anchor = FlatbedScanRegionFrameGeometry.frameLocalRect(
            unitRect: CGRect(origin: startBase, size: .zero),
            straightenAngle: 0,
            localAngle: angle,
            baseSize: baseSize
        )
        return FlatbedScanRegion(
            unitRect: frameAspectAdjusted(drawn, angle: angle, anchoredTo: anchor),
            straightenAngle: angle
        )
    }

    /// 규격 비율로 맞춘다. ⌥를 누르고 있으면 자유 비율(규격 목록에 없는 필름용 탈출구).
    /// 비율은 칸을 자기 방향으로 눕힌 좌표에서 맞춘다 — 기울어진 칸의 경계 상자는 규격 비율이 아니다.
    private func frameAspectAdjusted(
        _ rect: CGRect,
        angle: Double,
        anchoredTo previousLocal: CGRect
    ) -> CGRect {
        guard let previewArea = model.flatbedPreviewScanArea,
              !NSEvent.modifierFlags.contains(.option) else { return clampedUnitRect(rect) }
        let local = FlatbedScanRegionFrameGeometry.frameLocalRect(
            unitRect: rect,
            straightenAngle: angle,
            localAngle: angle,
            baseSize: baseSize
        )
        let snapped = FlatbedScanRegionLayout.snappedToFrameAspect(
            local,
            anchoredTo: previousLocal,
            frameSize: model.scanFrameSize,
            previewArea: previewArea
        )
        return clampedUnitRect(FlatbedScanRegionFrameGeometry.unitRect(
            fromFrameLocal: snapped,
            localAngle: angle,
            baseSize: baseSize
        ))
    }

    private func shape(for region: FlatbedScanRegion) -> FlatbedRegionScreenShape {
        FlatbedScanRegionFrameGeometry.screenShape(
            unitRect: region.unitRect,
            straightenAngle: region.straightenAngle,
            transform: frame.imageTransform,
            baseSize: baseSize,
            imageFrame: imageFrame
        )
    }

    private func unitRect(for shape: FlatbedRegionScreenShape) -> CGRect {
        FlatbedScanRegionFrameGeometry.unitRect(
            for: shape,
            transform: frame.imageTransform,
            baseSize: baseSize,
            imageFrame: imageFrame
        )
    }

    /// 사진 자리를 프레임 자기 좌표로 옮긴 경계. 손잡이를 끌어도 사진 밖으로 나가지 않는다.
    private func localImageBounds(for shape: FlatbedRegionScreenShape) -> CGRect {
        FlatbedScanRegionFrameGeometry.boundingRect(of: [
            CGPoint(x: imageFrame.minX, y: imageFrame.minY),
            CGPoint(x: imageFrame.maxX, y: imageFrame.minY),
            CGPoint(x: imageFrame.maxX, y: imageFrame.maxY),
            CGPoint(x: imageFrame.minX, y: imageFrame.maxY),
        ].map { shape.localPoint(screen: $0) })
    }

    private func clampedScreenPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, imageFrame.minX), imageFrame.maxX),
            y: min(max(point.y, imageFrame.minY), imageFrame.maxY)
        )
    }

    private var baseSize: CGSize? {
        guard let width = frame.sourcePixelWidth,
              let height = frame.sourcePixelHeight,
              width > 0,
              height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}
