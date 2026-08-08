import SwiftUI
import Chromabase

extension DefectClass {
    /// 오버레이/범례 색. 분류가 한눈에 구분되게 종류별 고정색을 쓴다.
    var overlayColor: Color {
        switch self {
        case .dust: return .orange
        case .pinhole: return .yellow
        case .scratchHorizontal: return .red
        case .scratchVertical: return .pink
        case .scratchDiagonal: return .purple
        case .emulsionDamage: return .cyan
        case .microSpeck: return .mint
        }
    }
}

// Defect Layer 마스크 오버레이. 선택된 레이어(frame.defectMaskPreviewID)의 검출 위치를
// 분류색으로 캔버스 위에 그린다 — region 은 저장된 미리보기 점, 브러시는 스트로크 경로.
// 좌표는 base 정규로 보관돼 있어 회전/플립/크롭이 바뀌어도 baseUnitToDisplay 로 정합한다.
struct DefectMaskOverlay: View {
    @ObservedObject var frame: ScanFrame
    let imageFrame: CGRect

    var body: some View {
        Canvas { ctx, _ in
            guard let id = frame.defectMaskPreviewID,
                  let item = frame.defectEdits.first(where: { $0.id == id }) else { return }
            if item.isBrush {
                drawBrush(item, in: &ctx)
            } else if item.isClone {
                drawClone(item, in: &ctx)
            } else {
                drawRegion(item, in: &ctx)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawRegion(_ item: DefectEditItem, in ctx: inout GraphicsContext) {
        for comp in item.preview {
            // confidence 를 불투명도로 표시 — 확신 높은 결함일수록 진하게 보인다.
            let color = comp.classification.overlayColor.opacity(0.35 + 0.5 * comp.confidence)
            for pt in comp.points {
                let d = displayPoint(pt, baseSize: item.baseSize)
                guard imageFrame.contains(d) else { continue }
                ctx.fill(Path(CGRect(x: d.x - 1.5, y: d.y - 1.5, width: 3, height: 3)), with: .color(color))
            }
        }
    }

    private func drawBrush(_ item: DefectEditItem, in ctx: inout GraphicsContext) {
        let width = min(imageFrame.width, imageFrame.height)
        for stroke in item.brushStrokes {
            let pts = stroke.points.map { displayPoint($0, baseSize: nil) }
            guard let first = pts.first else { continue }
            let lineWidth = max(1, stroke.thickness * width)
            if pts.count == 1 {
                let r = lineWidth / 2
                ctx.fill(Path(ellipseIn: CGRect(x: first.x - r, y: first.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.orange.opacity(0.4)))
                continue
            }
            var path = Path()
            path.move(to: first)
            for p in pts.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(.orange.opacity(0.4)),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    /// 복제 도장 레이어: 대상 스트로크 경로(지름 = raw 픽셀 → 화면 배율) + 소스 오프셋 십자.
    private func drawClone(_ item: DefectEditItem, in ctx: inout GraphicsContext) {
        let scale = pixelToScreenScale(baseSize: item.baseSize)
        for stroke in item.cloneStrokes {
            let pts = stroke.points.map { displayPoint($0, baseSize: item.baseSize) }
            guard let first = pts.first else { continue }
            let lineWidth = max(1, stroke.diameter * scale)
            if pts.count == 1 {
                let r = lineWidth / 2
                ctx.fill(Path(ellipseIn: CGRect(x: first.x - r, y: first.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.orange.opacity(0.4)))
            } else {
                var path = Path()
                path.move(to: first)
                for p in pts.dropFirst() { path.addLine(to: p) }
                ctx.stroke(path, with: .color(.orange.opacity(0.4)),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
            // 소스 위치 표시(첫 점 + 오프셋).
            guard let sourcePoint = stroke.points.first.map({
                CGPoint(x: $0.x + stroke.offset.dx, y: $0.y + stroke.offset.dy)
            }) else { continue }
            let s = displayPoint(sourcePoint, baseSize: item.baseSize)
            var cross = Path()
            cross.move(to: CGPoint(x: s.x - 6, y: s.y)); cross.addLine(to: CGPoint(x: s.x + 6, y: s.y))
            cross.move(to: CGPoint(x: s.x, y: s.y - 6)); cross.addLine(to: CGPoint(x: s.x, y: s.y + 6))
            ctx.stroke(cross, with: .color(.orange.opacity(0.8)), lineWidth: 1.5)
        }
    }

    /// raw 픽셀 → 화면 포인트 배율(표시 픽셀 크기 기준, 크롭/줌 정합).
    private func pixelToScreenScale(baseSize: CGSize?) -> CGFloat {
        if let displayPixels = frame.displayPixelSize, displayPixels.width > 0 {
            return imageFrame.width / displayPixels.width
        }
        guard let baseSize, baseSize.width > 0, baseSize.height > 0 else { return 1 }
        let width: CGFloat
        switch frame.imageTransform.rotation {
        case .deg90, .deg270: width = baseSize.height
        default: width = baseSize.width
        }
        return imageFrame.width / max(width, 1)
    }

    /// base 정규(0..1, y-down) → 화면 픽셀. 브러시 스트로크는 baseSize 없이 저장되므로 nil 매핑.
    private func displayPoint(_ base: CGPoint, baseSize: CGSize?) -> CGPoint {
        let d = frame.imageTransform.baseUnitToDisplay(base, baseSize: baseSize)
        return CGPoint(x: imageFrame.minX + d.x * imageFrame.width,
                       y: imageFrame.minY + d.y * imageFrame.height)
    }
}
