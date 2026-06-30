import SwiftUI

/// 무지개 색상환 — 클릭/드래그로 색조(각도)와 채도(반경)를 픽한다.
struct ColorWheelView: View {
    @Binding var hue: Double          // 0...360
    @Binding var saturation: Double   // 0...1
    let onChange: () -> Void
    var diameter: CGFloat = 150

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(
                    gradient: Gradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
                        Color(hue: $0, saturation: 1, brightness: 1)
                    }),
                    center: .center,
                    angle: .degrees(0)
                ))
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [.white, .white.opacity(0)]),
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                ))
            Circle().stroke(.white.opacity(0.25), lineWidth: 1)
            handle
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in update(at: value.location) }
        )
    }

    private var handle: some View {
        let r = diameter / 2
        let rad = hue * .pi / 180
        let dist = CGFloat(saturation) * r
        // 0° = 오른쪽, 반시계로 증가(화면 y는 아래로 +라 -sin).
        let pos = CGPoint(x: r + cos(rad) * dist, y: r - sin(rad) * dist)
        return Circle()
            .fill(Color(hue: hue / 360, saturation: max(saturation, 0.001), brightness: 1))
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .frame(width: 16, height: 16)
            .shadow(color: .black.opacity(0.35), radius: 2)
            .position(pos)
    }

    private func update(at location: CGPoint) {
        let r = diameter / 2
        let dx = location.x - r
        let dy = r - location.y
        let dist = sqrt(dx * dx + dy * dy)
        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }
        hue = angle
        saturation = Double(min(max(dist / r, 0), 1))
        onChange()
    }
}
