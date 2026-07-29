import AppKit
import SwiftUI

/// 좌/우·상/하 비교의 분할선. 끌어서 경계를 옮긴다.
///
/// 선 자체는 1px이라 잡기 어려우므로 투명한 손잡이 폭을 따로 두고, 가운데에 잡는 곳임을 알리는
/// 표식을 둔다. 위치는 이미지 기준 비율이라 확대/축소·창 크기와 무관하게 유지된다.
struct CanvasCompareDivider: View {
    static let minimumFraction: CGFloat = 0.02
    static let maximumFraction: CGFloat = 0.98
    private static let grabThickness: CGFloat = 18
    private static let adjustmentStep: CGFloat = 0.05

    let imageFrame: CGRect
    let orientation: CanvasCompareOrientation
    let accessibilityLabel: String
    @Binding var fraction: CGFloat
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(0.75))
                .frame(width: lineSize.width, height: lineSize.height)
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(.black.opacity(0.25))
                }
                .frame(width: handleSize.width, height: handleSize.height)
        }
        .frame(width: grabSize.width, height: grabSize.height)
        .contentShape(Rectangle())
        .position(position)
        .gesture(dragGesture)
        .onHover { hovering in
            guard hovering != isHovering else { return }
            isHovering = hovering
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            guard isHovering else { return }
            isHovering = false
            NSCursor.pop()
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(verbatim: "\(Int((fraction * 100).rounded()))%"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setFraction(fraction + Self.adjustmentStep)
            case .decrement: setFraction(fraction - Self.adjustmentStep)
            @unknown default: break
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                switch orientation {
                case .vertical:
                    setFraction((value.location.x - imageFrame.minX) / max(imageFrame.width, 1))
                case .horizontal:
                    setFraction((value.location.y - imageFrame.minY) / max(imageFrame.height, 1))
                }
            }
    }

    private func setFraction(_ value: CGFloat) {
        guard value.isFinite else { return }
        fraction = min(max(value, Self.minimumFraction), Self.maximumFraction)
    }

    private var position: CGPoint {
        switch orientation {
        case .vertical:
            return CGPoint(
                x: imageFrame.minX + imageFrame.width * fraction,
                y: imageFrame.midY
            )
        case .horizontal:
            return CGPoint(
                x: imageFrame.midX,
                y: imageFrame.minY + imageFrame.height * fraction
            )
        }
    }

    private var lineSize: CGSize {
        switch orientation {
        case .vertical: return CGSize(width: 1, height: imageFrame.height)
        case .horizontal: return CGSize(width: imageFrame.width, height: 1)
        }
    }

    private var grabSize: CGSize {
        switch orientation {
        case .vertical: return CGSize(width: Self.grabThickness, height: imageFrame.height)
        case .horizontal: return CGSize(width: imageFrame.width, height: Self.grabThickness)
        }
    }

    private var handleSize: CGSize {
        switch orientation {
        case .vertical: return CGSize(width: 4, height: 34)
        case .horizontal: return CGSize(width: 34, height: 4)
        }
    }

    private var cursor: NSCursor {
        switch orientation {
        case .vertical: return .resizeLeftRight
        case .horizontal: return .resizeUpDown
        }
    }
}
