import SwiftUI
import Chromabase

struct CropAngleDial: View {
    let angle: Double
    let onAngleChange: (Double) -> Void
    let onReset: () -> Void

    private let size: CGFloat = 108
    private let radius: CGFloat = 42

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.045))

            Circle()
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)

            Rectangle()
                .fill(Color.primary.opacity(0.18))
                .frame(width: size - 20, height: 1)

            ForEach([-45, -30, -15, 0, 15, 30, 45], id: \.self) { tick in
                Capsule()
                    .fill(tick == 0 ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.28))
                    .frame(width: 1, height: tick == 0 ? 10 : 6)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(tick)))
            }

            Path { path in
                path.move(to: CGPoint(x: size / 2, y: size / 2))
                path.addLine(to: CGPoint(
                    x: size / 2 + knobOffset.width,
                    y: size / 2 + knobOffset.height
                ))
            }
            .stroke(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            Circle()
                .fill(Color.accentColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.85), lineWidth: 1)
                )
                .offset(knobOffset)

            Text(angleText)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .offset(y: 18)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .highPriorityGesture(
            TapGesture(count: 2)
                .onEnded(onReset)
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    onAngleChange(angle(for: value.location))
                }
        )
    }

    private var knobOffset: CGSize {
        let radians = clampedAngle * .pi / 180
        return CGSize(
            width: sin(radians) * radius,
            height: -cos(radians) * radius
        )
    }

    private var clampedAngle: Double {
        min(max(angle, -45), 45)
    }

    private var angleText: String {
        abs(angle) < 0.05 ? "0.0°" : String(format: "%+.1f°", angle)
    }

    private func angle(for location: CGPoint) -> Double {
        let center = CGPoint(x: size / 2, y: size / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        guard abs(dx) + abs(dy) > 1 else { return angle }
        let degrees = Double(atan2(dx, -dy) * 180 / .pi)
        return min(max(degrees, -45), 45)
    }
}
