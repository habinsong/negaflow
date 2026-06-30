import SwiftUI
import AppKit
import CoreImage
import Chromabase

// MARK: - 결함 브러시 (사용자 마스킹 기반 ICE)
//
// 완전 자동 검출은 구조물 많은 장면에서 한계가 크다. 대신 사용자가 결함(먼지/스크래치)
// 위를 반투명 빨강으로 대충 칠하면, 그 영역 안에서만 ICE가 실제 결함을 정밀 검출·복원한다.
// 스트로크는 이미지 단위 좌표(0..1, y는 위에서)로 저장해 줌/해상도와 무관하게 정렬된다.

struct DefectStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]   // 이미지 단위 좌표 (0..1, y 위→아래)
    var thickness: CGFloat  // 짧은 변 대비 비율
}

enum DefectBrush {
    /// 스트로크들을 픽셀 마스크(흰 선 on 검정)로 래스터화 → CIImage.
    static func rasterMask(strokes: [DefectStroke], pixelWidth: Int, pixelHeight: Int) -> CIImage? {
        rasterMask(
            strokes: strokes,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            extent: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        )
    }

    private static func rasterMask(strokes: [DefectStroke], pixelWidth: Int, pixelHeight: Int,
                                   extent: CGRect) -> CIImage? {
        guard pixelWidth > 0, pixelHeight > 0, !strokes.isEmpty else { return nil }
        let maskWidth = Int(extent.width.rounded())
        let maskHeight = Int(extent.height.rounded())
        guard maskWidth > 0, maskHeight > 0 else { return nil }
        let gray = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: maskWidth, height: maskHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: gray,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: maskWidth, height: maskHeight))
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let minDim = CGFloat(min(pixelWidth, pixelHeight))
        // 단위(y 위) → 픽셀(CGContext y 아래) 변환.
        func px(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: p.x * CGFloat(pixelWidth) - extent.origin.x,
                y: (1 - p.y) * CGFloat(pixelHeight) - extent.origin.y
            )
        }
        for stroke in strokes where !stroke.points.isEmpty {
            let lineWidth = max(1, stroke.thickness * minDim)
            if stroke.points.count == 1 {
                let c = px(stroke.points[0]); let r = lineWidth / 2
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                continue
            }
            ctx.setLineWidth(lineWidth)
            let path = CGMutablePath()
            path.move(to: px(stroke.points[0]))
            for p in stroke.points.dropFirst() { path.addLine(to: px(p)) }
            ctx.addPath(path); ctx.strokePath()
        }
        return ctx.makeImage().map {
            CIImage(cgImage: $0)
                .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
        }
    }

    /// 현상된 이미지의 브러시 영역에 ICE 적용 → 새 NSImage. strokes는 이 이미지와 같은 좌표계(0..1).
    static func removeDefects(in developed: NSImage, strokes: [DefectStroke],
                              parameters: SoftwareICEParameters) -> NSImage? {
        guard let cg = developed.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let out = removeDefects(in: cg, strokes: strokes, parameters: parameters) else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
    }

    /// CGImage 버전. strokes는 이 이미지와 같은 정규좌표(0..1, y 위→아래)여야 한다.
    /// raw 스캔(변형 전, 풀해상도)에 직접 적용하므로 이후 모든 현상/변형/export에서 유지된다.
    /// - linear16: raw(16bit linear) 도메인에 적용할 때 true. 평탄화/출력 정밀도와 색공간을 보존한다.
    static func removeDefects(in cg: CGImage, strokes: [DefectStroke],
                              parameters: SoftwareICEParameters,
                              linear16: Bool = false,
                              shouldCancel: @escaping @Sendable () -> Bool = { false }) -> CGImage? {
        guard !strokes.isEmpty else { return cg }
        let context = linear16 ? ICEContext.renderLinear : ICEContext.render
        let outFormat: CIFormat = linear16 ? .RGBA16 : .RGBA8
        let outColorSpace = linear16
            ? CGColorSpace(name: CGColorSpace.linearSRGB)!
            : CGColorSpace(name: CGColorSpace.sRGB)!
        func flatten(_ image: CIImage, from rect: CGRect) -> CGImage? {
            context.createCGImage(image, from: rect, format: outFormat, colorSpace: outColorSpace)
        }
        let fullExtent = CIImage(cgImage: cg).extent

        // 스트로크를 청크로 쪼개 처리한다 — roi 를 작게 유지해 풀 해상도로 검출(얇은 스크래치를
        // 놓치지 않고, 마스크 업스케일 번짐도 없음)하고 복원 비용도 제한한다.
        let pxW = cg.width, pxH = cg.height
        let chunks = strokes
            .flatMap { repairChunks(for: $0, pixelWidth: pxW, pixelHeight: pxH) }
            .filter { !$0.points.isEmpty }
        guard !chunks.isEmpty else { return cg }
        let extents = chunks.map { repairBounds(for: [$0], pixelWidth: pxW, pixelHeight: pxH) }

        // 겹치는 청크끼리 그룹으로 묶는다(union-find). 서로 분리된 그룹(떨어진 여러 브러시 칠,
        // 흩어진 먼지)은 메모리가 겹치지 않으므로 병렬 처리해도 안전하고 캐시 경합이 없다.
        let groups = clusterByOverlap(extents)
        let original = CIImage(cgImage: cg)

        // 그룹별로 독립 처리 → dirty 패치. concurrentPerform 으로 그룹을 코어에 분산한다
        // (per-region 단위 — per-pixel 분산은 오버헤드가 커 금물).
        var patches = [(rect: CGRect, image: CGImage)?](repeating: nil, count: groups.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: groups.count) { gi in
            if shouldCancel() { return }
            var groupDirty = CGRect.null
            for ci in groups[gi] { groupDirty = groupDirty.union(extents[ci]) }
            groupDirty = groupDirty.integral.intersection(fullExtent)
            guard !groupDirty.isNull, groupDirty.width >= 1, groupDirty.height >= 1 else { return }

            // 그룹 내 청크는 겹칠 수 있으므로 순차 누적(이전 복구 위에 얹어 되살아남 방지).
            var working = original
            var sinceFlush = 0
            for ci in groups[gi] {
                if shouldCancel() { return }
                let stroke = chunks[ci]
                guard let mask = rasterMask(strokes: [stroke], pixelWidth: pxW, pixelHeight: pxH,
                                            extent: extents[ci]) else { continue }
                working = SoftwareICE.apply(to: working, parameters: parameters, brush: mask,
                                            repairExtent: extents[ci],
                                            preferredAngle: strokeAngle(stroke, pixelWidth: pxW, pixelHeight: pxH))
                sinceFlush += 1
                if sinceFlush >= 4 {
                    guard let flat = flatten(working, from: groupDirty) else { return }
                    working = CIImage(cgImage: flat)
                        .transformed(by: CGAffineTransform(translationX: groupDirty.minX, y: groupDirty.minY))
                        .composited(over: original)
                    sinceFlush = 0
                }
            }
            guard let patch = flatten(working, from: groupDirty) else { return }
            lock.lock(); patches[gi] = (groupDirty, patch); lock.unlock()
        }
        if shouldCancel() { return nil }

        // 그룹 패치들을 원본 위에 합성(분리 영역이라 순서 무관).
        var result = original
        var any = false
        for case let gp? in patches {
            result = CIImage(cgImage: gp.image)
                .transformed(by: CGAffineTransform(translationX: gp.rect.minX, y: gp.rect.minY))
                .composited(over: result)
            any = true
        }
        guard any else { return cg }
        guard let outCG = flatten(result, from: fullExtent) else { return nil }
        return outCG
    }

    /// 겹치는(교차하는) 청크 사각형 인덱스끼리 그룹으로 묶는다(union-find). 분리된 그룹은
    /// 메모리가 겹치지 않아 병렬 처리해도 안전하다. O(n²) 교차 검사 — 청크 수는 보통 수십.
    private static func clusterByOverlap(_ extents: [CGRect]) -> [[Int]] {
        let n = extents.count
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }
            return r
        }
        for i in 0..<n {
            for j in (i + 1)..<n where extents[i].intersects(extents[j]) {
                let ri = find(i), rj = find(j)
                if ri != rj { parent[ri] = rj }
            }
        }
        var buckets = [Int: [Int]]()
        for i in 0..<n { buckets[find(i), default: []].append(i) }
        return Array(buckets.values)
    }

    /// 긴 스트로크를 maxLength 픽셀 단위 청크로 쪼갠다(roi 를 작게 유지).
    private static func repairChunks(for stroke: DefectStroke, pixelWidth: Int, pixelHeight: Int) -> [DefectStroke] {
        guard stroke.points.count > 1 else { return stroke.points.isEmpty ? [] : [stroke] }
        let minDim = CGFloat(min(pixelWidth, pixelHeight))
        let maxLength = max(240, min(minDim * 0.16, 640))
        var chunks: [DefectStroke] = []
        var current = [stroke.points[0]]
        var currentLength: CGFloat = 0

        var start = stroke.points[0]
        for target in stroke.points.dropFirst() {
            var segmentStart = start
            var remaining = distance(segmentStart, target, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
            while currentLength + remaining > maxLength, remaining > 1e-3 {
                let take = max(1, maxLength - currentLength)
                let t = min(1, take / remaining)
                let split = CGPoint(
                    x: segmentStart.x + (target.x - segmentStart.x) * t,
                    y: segmentStart.y + (target.y - segmentStart.y) * t
                )
                current.append(split)
                chunks.append(DefectStroke(points: current, thickness: stroke.thickness))
                current = [split]
                currentLength = 0
                segmentStart = split
                remaining = distance(segmentStart, target, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
            }
            current.append(target)
            currentLength += remaining
            start = target
        }
        if current.count > 1 {
            chunks.append(DefectStroke(points: current, thickness: stroke.thickness))
        }
        return chunks
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint, pixelWidth: Int, pixelHeight: Int) -> CGFloat {
        let dx = (a.x - b.x) * CGFloat(pixelWidth)
        let dy = (a.y - b.y) * CGFloat(pixelHeight)
        return sqrt(dx * dx + dy * dy)
    }

    /// 스트로크 주축 방향(도, 0~180). PCA 로 추정한다. 충분히 길고 한 방향으로 뻗은
    /// 칠에만 값을 주고(점·둥근 칠은 nil → 전 방향 검출), ICE 가 그 방향의 스크래치만
    /// 잡고 그것을 가로지르는 구조선은 보존하도록 한다.
    private static func strokeAngle(_ stroke: DefectStroke, pixelWidth: Int, pixelHeight: Int) -> Double? {
        let pts = stroke.points
        guard pts.count >= 2 else { return nil }
        let n = Double(pts.count)
        var mx = 0.0, my = 0.0
        for p in pts { mx += Double(p.x) * Double(pixelWidth); my += Double(p.y) * Double(pixelHeight) }
        mx /= n; my /= n
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in pts {
            let dx = Double(p.x) * Double(pixelWidth) - mx
            let dy = Double(p.y) * Double(pixelHeight) - my
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        let rms = ((sxx + syy) / n).squareRoot()
        guard rms >= Double(min(pixelWidth, pixelHeight)) * 0.01 else { return nil }   // 점 같은 칠 제외
        let aniso = (((sxx - syy) * (sxx - syy) + 4 * sxy * sxy).squareRoot()) / max(1e-6, sxx + syy)
        guard aniso > 0.3 else { return nil }                                          // 둥근 칠 제외
        var deg = 0.5 * atan2(2 * sxy, sxx - syy) * 180 / .pi
        if deg < 0 { deg += 180 }
        if deg >= 180 { deg -= 180 }
        return deg
    }

    private static func repairBounds(for strokes: [DefectStroke], pixelWidth: Int, pixelHeight: Int) -> CGRect {
        let imageBounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        let minDim = CGFloat(min(pixelWidth, pixelHeight))
        var bounds = CGRect.null

        func px(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * CGFloat(pixelWidth), y: (1 - p.y) * CGFloat(pixelHeight))
        }

        for stroke in strokes where !stroke.points.isEmpty {
            let lineWidth = max(1, stroke.thickness * minDim)
            for point in stroke.points {
                let center = px(point)
                bounds = bounds.union(CGRect(
                    x: center.x - lineWidth / 2,
                    y: center.y - lineWidth / 2,
                    width: lineWidth,
                    height: lineWidth
                ))
            }
        }

        guard !bounds.isNull else { return imageBounds }
        let halo = max(96, minDim * 0.025)
        return bounds.insetBy(dx: -halo, dy: -halo).integral.intersection(imageBounds)
    }

}

// MARK: - 페인팅 오버레이

struct BrushOverlay: View {
    @Binding var strokes: [DefectStroke]
    @Binding var current: [CGPoint]
    let thickness: CGFloat
    let imageFrame: CGRect

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

struct BrushControlBar: View {
    @Binding var thickness: CGFloat
    let hasStrokes: Bool
    let hasAppliedDefects: Bool
    let isBusy: Bool
    let onApply: () -> Void
    let onUndo: () -> Void
    let onClear: () -> Void
    let onResetAll: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "paintbrush.pointed.fill").foregroundStyle(.red)
            HStack(spacing: 6) {
                Image(systemName: "lineweight").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $thickness, in: 0.004...0.06).frame(width: 110)
            }
            Divider().frame(height: 16)
            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                .help("마지막 스트로크 취소").disabled(!hasStrokes || isBusy)
            Button(action: onClear) { Image(systemName: "trash") }
                .help("칠한 스트로크 지우기").disabled(!hasStrokes || isBusy)
            Button(action: onResetAll) { Image(systemName: "arrow.counterclockwise") }
                .help("적용된 결함 제거 전체 초기화").disabled(!hasAppliedDefects || isBusy)
            Button(action: onApply) {
                if isBusy { ProgressView().controlSize(.small) }
                else { Label("결함 제거", systemImage: "wand.and.stars") }
            }
            .buttonStyle(.borderedProminent).disabled(!hasStrokes || isBusy)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
