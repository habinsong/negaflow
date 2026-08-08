import SwiftUI
import AppKit
import CoreImage
import Chromabase

struct BrushOverlay: View {
    @Binding var strokes: [DefectStroke]
    let thickness: CGFloat
    let imageFrame: CGRect

    // 진행 중 스트로크는 이 뷰의 로컬 상태다 — 부모(캔버스 전체 body)가 매 마우스 틱마다
    // 재평가되지 않는다. 스트로크가 끝날 때만 바인딩(strokes)에 1회 반영한다(드로잉 렉 방지).
    @State private var current: [CGPoint] = []

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                for stroke in strokes { paint(stroke.points, stroke.thickness, in: &ctx) }
                if !current.isEmpty { paint(current, thickness, in: &ctx) }
            }
            .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
                        .onChanged { current.append(unit($0.location)) }
                        .onEnded { _ in
                            if !current.isEmpty {
                                strokes.append(DefectStroke(points: current, thickness: thickness))
                                current = []
                            }
                        }
                )
        }
    }

    private func unit(_ p: CGPoint) -> CGPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return .zero }
        return CGPoint(
            x: min(max((p.x - imageFrame.minX) / imageFrame.width, 0), 1),
            y: min(max((p.y - imageFrame.minY) / imageFrame.height, 0), 1)
        )
    }

    private func canvasPoint(_ u: CGPoint) -> CGPoint {
        CGPoint(x: imageFrame.minX + u.x * imageFrame.width,
                y: imageFrame.minY + u.y * imageFrame.height)
    }

    private func paint(_ points: [CGPoint], _ thickness: CGFloat, in ctx: inout GraphicsContext) {
        guard let first = points.first else { return }
        let width = max(1, thickness * min(imageFrame.width, imageFrame.height))
        let red = Color.red.opacity(0.45)
        if points.count == 1 {
            let c = canvasPoint(first); let r = width / 2
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(red))
            return
        }
        var path = Path()
        path.move(to: canvasPoint(first))
        for p in points.dropFirst() { path.addLine(to: canvasPoint(p)) }
        ctx.stroke(path, with: .color(red), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - 브러시 컨트롤 바
