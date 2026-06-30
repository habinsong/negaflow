import SwiftUI
import Chromabase

/// 라이트룸형 포인트 톤 커브 에디터 — DR(휘도)/R/G/B 채널을 그래프에서 클릭·드래그로 조절.
struct ToneCurveEditor: View {
    @Binding var curves: PointCurves
    let onChange: () -> Void
    @State private var channel: Channel = .rgb

    enum Channel: String, CaseIterable, Identifiable {
        case rgb, red, green, blue
        var id: Self { self }
        var label: String {
            switch self {
            case .rgb: return "DR"
            case .red: return "Red"
            case .green: return "Green"
            case .blue: return "Blue"
            }
        }
        var tint: Color {
            switch self {
            case .rgb: return .primary
            case .red: return .red
            case .green: return .green
            case .blue: return .blue
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            channelPicker
            CurveCanvas(points: pointsBinding, tint: channel.tint, onChange: onChange)
                .frame(height: 188)
            HStack {
                Text("클릭으로 점 추가 · 드래그로 이동 · 더블클릭으로 삭제")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    setPoints([])
                    onChange()
                }
                .font(.caption2)
                .buttonStyle(.borderless)
                .disabled(currentPoints.isEmpty)
            }
        }
    }

    private var channelPicker: some View {
        HStack(spacing: 2) {
            ForEach(Channel.allCases) { ch in
                Button {
                    channel = ch
                } label: {
                    Text(ch.label)
                        .font(.caption.weight(channel == ch ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .foregroundStyle(channel == ch ? ch.tint : Color.secondary)
                        .background(channel == ch ? ch.tint.opacity(0.14) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var currentPoints: [CurvePoint] {
        switch channel {
        case .rgb: return curves.rgb
        case .red: return curves.red
        case .green: return curves.green
        case .blue: return curves.blue
        }
    }

    private func setPoints(_ pts: [CurvePoint]) {
        switch channel {
        case .rgb: curves.rgb = pts
        case .red: curves.red = pts
        case .green: curves.green = pts
        case .blue: curves.blue = pts
        }
    }

    private var pointsBinding: Binding<[CurvePoint]> {
        Binding(get: { currentPoints }, set: { setPoints($0) })
    }
}

/// 커브 플롯 + 드래그 가능한 제어점.
private struct CurveCanvas: View {
    @Binding var points: [CurvePoint]
    let tint: Color
    let onChange: () -> Void
    @State private var dragIndex: Int?

    private let handleR: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size).insetBy(dx: handleR + 2, dy: handleR + 2)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.18))
                grid(in: rect)
                baseline(in: rect)
                curvePath(in: rect)
                    .stroke(tint.opacity(0.95), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                ForEach(Array(effectivePoints.enumerated()), id: \.offset) { idx, p in
                    Circle()
                        .fill(tint)
                        .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
                        .frame(width: handleR * 2, height: handleR * 2)
                        .position(screen(p, in: rect))
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(in: rect))
            .onTapGesture(count: 2) { location in removePoint(near: location, in: rect) }
        }
    }

    /// 빈 배열이면 끝점 두 개의 직선으로 본다.
    private var effectivePoints: [CurvePoint] {
        points.isEmpty ? [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)] : points.sorted { $0.x < $1.x }
    }

    private func grid(in rect: CGRect) -> some View {
        Path { p in
            for i in 1..<4 {
                let fx = rect.minX + rect.width * CGFloat(i) / 4
                p.move(to: CGPoint(x: fx, y: rect.minY)); p.addLine(to: CGPoint(x: fx, y: rect.maxY))
                let fy = rect.minY + rect.height * CGFloat(i) / 4
                p.move(to: CGPoint(x: rect.minX, y: fy)); p.addLine(to: CGPoint(x: rect.maxX, y: fy))
            }
        }
        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
    }

    private func baseline(in rect: CGRect) -> some View {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func curvePath(in rect: CGRect) -> Path {
        let lut = CurveLUT.build(effectivePoints, size: 96)
        return Path { p in
            for i in 0..<lut.count {
                let x = Double(i) / Double(lut.count - 1)
                let pt = screen(CurvePoint(x: x, y: Double(lut[i])), in: rect)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }

    private func screen(_ p: CurvePoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(p.x) * rect.width,
                y: rect.maxY - CGFloat(p.y) * rect.height)
    }

    private func unit(_ location: CGPoint, in rect: CGRect) -> CurvePoint {
        let x = (location.x - rect.minX) / rect.width
        let y = (rect.maxY - location.y) / rect.height
        return CurvePoint(x: Double(min(max(x, 0), 1)), y: Double(min(max(y, 0), 1)))
    }

    private func dragGesture(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                ensureEditable()
                if dragIndex == nil {
                    // 기존 점 근처면 그 점을, 빈 곳이면 새 점을 추가해 곧바로 드래그.
                    if let near = nearestIndex(to: value.startLocation, in: rect) {
                        dragIndex = near
                    } else {
                        dragIndex = insertPoint(at: value.startLocation, in: rect)
                    }
                }
                guard let i = dragIndex, points.indices.contains(i) else { return }
                let u = unit(value.location, in: rect)
                var newX = u.x
                // 끝점은 x 고정, 내부 점은 이웃 사이로 제한.
                if i == 0 { newX = 0 } else if i == points.count - 1 { newX = 1 }
                else {
                    let lo = points[i - 1].x + 0.01
                    let hi = points[i + 1].x - 0.01
                    newX = min(max(u.x, lo), hi)
                }
                points[i] = CurvePoint(x: newX, y: u.y)
                onChange()
            }
            .onEnded { _ in dragIndex = nil }
    }

    private func ensureEditable() {
        if points.isEmpty {
            points = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]
        }
    }

    private func nearestIndex(to location: CGPoint, in rect: CGRect) -> Int? {
        var best: Int?
        var bestD = CGFloat.greatestFiniteMagnitude
        for (i, p) in points.enumerated() {
            let d = hypot(screen(p, in: rect).x - location.x, screen(p, in: rect).y - location.y)
            if d < bestD { bestD = d; best = i }
        }
        return bestD <= 18 ? best : nil
    }

    /// 새 점을 삽입하고 정렬 후 그 인덱스를 돌려준다(드래그 대상으로 사용).
    private func insertPoint(at location: CGPoint, in rect: CGRect) -> Int {
        let u = unit(location, in: rect)
        var pts = points
        pts.append(u)
        pts.sort { $0.x < $1.x }
        points = pts
        onChange()
        return pts.firstIndex(where: { abs($0.x - u.x) < 1e-9 && abs($0.y - u.y) < 1e-9 }) ?? pts.count - 1
    }

    private func removePoint(near location: CGPoint, in rect: CGRect) {
        guard let i = nearestIndex(to: location, in: rect) else { return }
        // 끝점은 유지.
        guard i != 0, i != points.count - 1 else { return }
        points.remove(at: i)
        onChange()
    }
}
