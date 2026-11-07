import Chromabase
import SwiftUI

/// 변환 도우미 모드의 안내선. 빈 곳을 끌면 새 안내선(최대 4개), 끝점을 끌면 그 끝을 옮긴다.
///
/// 안내선은 원근 보정 앞 좌표에 저장하고, 손을 뗄 때 한 번만 다시 푼다. 끄는 도중에 풀면 그림이
/// 바뀌면서 손가락 아래 점의 원래 좌표도 바뀌어 끝점이 미끄러진다.
struct PerspectiveGuideOverlay: View {
    @ObservedObject var frame: ScanFrame
    @EnvironmentObject private var model: AppModel
    let imageFrame: CGRect
    @State private var draft: (start: CGPoint, end: CGPoint)?
    @State private var moving: (index: Int, isStart: Bool, point: CGPoint)?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)
                .contentShape(Rectangle())
                .gesture(drawGesture)
            ForEach(Array(guides.enumerated()), id: \.offset) { index, guide in
                let ends = screenEnds(of: guide, index: index)
                guideLine(from: ends.start, to: ends.end)
                endHandle(at: ends.start).gesture(moveGesture(index: index, isStart: true))
                endHandle(at: ends.end).gesture(moveGesture(index: index, isStart: false))
            }
            if let draft {
                guideLine(from: draft.start, to: draft.end)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var guides: [PerspectiveGuide] { frame.imageTransform.perspective.guides }

    private func guideLine(from start: CGPoint, to end: CGPoint) -> some View {
        ZStack {
            Path { p in p.move(to: start); p.addLine(to: end) }
                .stroke(Color.black.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Path { p in p.move(to: start); p.addLine(to: end) }
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .allowsHitTesting(false)
    }

    private func endHandle(at point: CGPoint) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
            .frame(width: 10, height: 10)
            .frame(width: 22, height: 22)
            .contentShape(Circle())
            .position(point)
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                guard guides.count < PerspectiveCorrection.maximumGuides else { return }
                draft = (clamped(value.startLocation), clamped(value.location))
            }
            .onEnded { _ in
                defer { draft = nil }
                guard let draft, hypot(draft.end.x - draft.start.x, draft.end.y - draft.start.y) >= 12 else { return }
                var next = guides
                next.append(PerspectiveGuide(start: oriented(draft.start), end: oriented(draft.end)))
                model.setPerspectiveGuides(frame, guides: next)
            }
    }

    private func moveGesture(index: Int, isStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                moving = (index, isStart, clamped(value.location))
            }
            .onEnded { _ in
                defer { moving = nil }
                guard let moving, guides.indices.contains(moving.index) else { return }
                var next = guides
                if moving.isStart {
                    next[moving.index].start = oriented(moving.point)
                } else {
                    next[moving.index].end = oriented(moving.point)
                }
                model.setPerspectiveGuides(frame, guides: next)
            }
    }

    /// 끌고 있는 끝은 손가락 자리에, 나머지는 저장된 좌표를 지금 화면으로 옮긴 자리에 그린다.
    private func screenEnds(of guide: PerspectiveGuide, index: Int) -> (start: CGPoint, end: CGPoint) {
        var start = screen(guide.start)
        var end = screen(guide.end)
        if let moving, moving.index == index {
            if moving.isStart { start = moving.point } else { end = moving.point }
        }
        return (start, end)
    }

    private func screen(_ oriented: CGPoint) -> CGPoint {
        let display = frame.imageTransform.orientedUnitToDisplay(oriented, baseSize: baseSize)
        return CGPoint(
            x: imageFrame.minX + display.x * imageFrame.width,
            y: imageFrame.minY + display.y * imageFrame.height
        )
    }

    private func oriented(_ screen: CGPoint) -> CGPoint {
        let display = CGPoint(
            x: (screen.x - imageFrame.minX) / max(imageFrame.width, 1),
            y: (screen.y - imageFrame.minY) / max(imageFrame.height, 1)
        )
        return frame.imageTransform.displayUnitToOriented(display, baseSize: baseSize)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, imageFrame.minX), imageFrame.maxX),
            y: min(max(point.y, imageFrame.minY), imageFrame.maxY)
        )
    }

    /// 좌표 변환에 쓰는 원본 크기. 다른 오버레이와 같이 원본 픽셀 크기를 먼저 쓴다.
    private var baseSize: CGSize? {
        if let width = frame.sourcePixelWidth, let height = frame.sourcePixelHeight, width > 0, height > 0 {
            return CGSize(width: width, height: height)
        }
        return frame.cachedDevelopedBase.map { CGSize(width: $0.width, height: $0.height) }
    }
}
