import AppKit
import SwiftUI

extension CanvasView {
    @ViewBuilder
    func movableCompareHUD(canvasSize: CGSize) -> some View {
        if canCompare && !isDebugPreviewActive {
            let origin = resolvedCanvasHUDOrigins(canvasSize: canvasSize).compare
            beforeAfterToggle
                .fixedSize()
                .reportCanvasHUDSize(.compare)
                .onPreferenceChange(CanvasHUDSizePreferenceKey.self) { sizes in
                    guard let size = sizes[.compare],
                          size.width > 0,
                          size.height > 0,
                          canvasHUDState.compareSize != size else { return }
                    canvasHUDState.compareSize = size
                }
                .position(
                    x: origin.x + canvasHUDState.compareSize.width / 2,
                    y: origin.y + canvasHUDState.compareSize.height / 2
                )
                .highPriorityGesture(canvasHUDDragGesture(
                    kind: .compare,
                    currentOrigin: origin,
                    canvasSize: canvasSize
                ))
                .zIndex(20)
        }
    }

    func movableZoomHUD(imageSize: NSSize, canvasSize: CGSize) -> some View {
        let origin = resolvedCanvasHUDOrigins(canvasSize: canvasSize).zoom
        return CanvasToolHUD(
            zoomText: viewport.zoomText,
            onZoomOut: {
                setScale(viewport.scale / 1.25, imageSize: imageSize, canvasSize: canvasSize)
            },
            onZoomIn: {
                setScale(viewport.scale * 1.25, imageSize: imageSize, canvasSize: canvasSize)
            },
            onSetZoomPercent: { percent in
                setZoomPercent(percent, imageSize: imageSize, canvasSize: canvasSize)
            },
            onFit: { resetViewport() },
            onActualSize: {
                let actualScale = viewport.actualSizeScale(for: imageSize, in: canvasSize)
                setScale(actualScale, imageSize: imageSize, canvasSize: canvasSize)
            }
        )
        .fixedSize()
        .reportCanvasHUDSize(.zoom)
        .onPreferenceChange(CanvasHUDSizePreferenceKey.self) { sizes in
            guard let size = sizes[.zoom],
                  size.width > 0,
                  size.height > 0,
                  canvasHUDState.zoomSize != size else { return }
            canvasHUDState.zoomSize = size
        }
        .position(
            x: origin.x + canvasHUDState.zoomSize.width / 2,
            y: origin.y + canvasHUDState.zoomSize.height / 2
        )
        .highPriorityGesture(canvasHUDDragGesture(
            kind: .zoom,
            currentOrigin: origin,
            canvasSize: canvasSize
        ))
        .zIndex(20)
    }

    func resolvedCanvasHUDOrigins(canvasSize: CGSize) -> CanvasHUDOrigins {
        let defaults = CanvasHUDPlacement.defaultOrigins(
            canvasSize: canvasSize,
            compareSize: canvasHUDState.compareSize,
            zoomSize: canvasHUDState.zoomSize
        )
        let compare = CanvasHUDPlacement.clampedOrigin(
            canvasHUDState.compareOrigin ?? defaults.compare,
            hudSize: canvasHUDState.compareSize,
            canvasSize: canvasSize
        )
        let zoom = CanvasHUDPlacement.avoidingOverlap(
            proposedOrigin: canvasHUDState.zoomOrigin ?? defaults.zoom,
            movingSize: canvasHUDState.zoomSize,
            otherOrigin: compare,
            otherSize: canvasHUDState.compareSize,
            canvasSize: canvasSize
        )
        return CanvasHUDOrigins(compare: compare, zoom: zoom)
    }

    func canvasHUDDragGesture(
        kind: CanvasHUDKind,
        currentOrigin: CGPoint,
        canvasSize: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let origins = resolvedCanvasHUDOrigins(canvasSize: canvasSize)
                switch kind {
                case .compare:
                    if canvasHUDState.compareDragStart == nil {
                        canvasHUDState.compareDragStart = currentOrigin
                    }
                    guard let start = canvasHUDState.compareDragStart else { return }
                    canvasHUDState.compareOrigin = CanvasHUDPlacement.avoidingOverlap(
                        proposedOrigin: CGPoint(
                            x: start.x + value.translation.width,
                            y: start.y + value.translation.height
                        ),
                        movingSize: canvasHUDState.compareSize,
                        otherOrigin: origins.zoom,
                        otherSize: canvasHUDState.zoomSize,
                        canvasSize: canvasSize
                    )
                case .zoom:
                    if canvasHUDState.zoomDragStart == nil {
                        canvasHUDState.zoomDragStart = currentOrigin
                    }
                    guard let start = canvasHUDState.zoomDragStart else { return }
                    canvasHUDState.zoomOrigin = CanvasHUDPlacement.avoidingOverlap(
                        proposedOrigin: CGPoint(
                            x: start.x + value.translation.width,
                            y: start.y + value.translation.height
                        ),
                        movingSize: canvasHUDState.zoomSize,
                        otherOrigin: origins.compare,
                        otherSize: canvasHUDState.compareSize,
                        canvasSize: canvasSize
                    )
                }
            }
            .onEnded { _ in
                switch kind {
                case .compare:
                    canvasHUDState.compareDragStart = nil
                case .zoom:
                    canvasHUDState.zoomDragStart = nil
                }
            }
    }
}

private struct CanvasHUDSizePreferenceKey: PreferenceKey {
    static let defaultValue: [CanvasHUDKind: CGSize] = [:]

    static func reduce(
        value: inout [CanvasHUDKind: CGSize],
        nextValue: () -> [CanvasHUDKind: CGSize]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func reportCanvasHUDSize(_ kind: CanvasHUDKind) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CanvasHUDSizePreferenceKey.self,
                    value: [kind: proxy.size]
                )
            }
        }
    }
}
