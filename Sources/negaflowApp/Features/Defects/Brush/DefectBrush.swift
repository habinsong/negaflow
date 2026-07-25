import SwiftUI
import AppKit
import CoreImage
import Chromabase

// MARK: - 결함 브러시 (사용자 마스킹 기반 결함 제거)
//
// 완전 자동 검출은 구조물 많은 장면에서 한계가 크다. 대신 사용자가 결함(먼지/스크래치)
// 위를 반투명 빨강으로 대충 칠하면, 그 영역 안에서만 결함 제거가 실제 결함을 정밀 검출·복원한다.
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

    /// 현상된 이미지의 브러시 영역에 결함 제거 적용 → 새 NSImage. strokes는 이 이미지와 같은 좌표계(0..1).
    static func removeDefects(in developed: NSImage, strokes: [DefectStroke],
                              parameters: SoftwareDefectParameters) -> NSImage? {
        guard let cg = developed.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let out = removeDefects(in: cg, strokes: strokes, parameters: parameters) else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
    }

    /// CGImage 버전. strokes는 이 이미지와 같은 정규좌표(0..1, y 위→아래)여야 한다.
    /// raw 스캔(변형 전, 풀해상도)에 직접 적용하므로 이후 모든 현상/변형/export에서 유지된다.
    /// - linear16: raw(16bit linear) 도메인에 적용할 때 true. 평탄화/출력 정밀도와 색공간을 보존한다.
    ///
    /// 내부는 강도 1.0 패치 계산(removeDefectsPatches) + 강도 블렌드 합성으로 나뉜다 —
    /// 강도만 바뀌면 호출측이 패치를 캐시해 재계산 없이 합성만 할 수 있다(레이어 UI 즉시 반응).
    static func removeDefects(in cg: CGImage, strokes: [DefectStroke],
                              parameters: SoftwareDefectParameters,
                              linear16: Bool = false,
                              shouldCancel: @escaping @Sendable () -> Bool = { false }) -> CGImage? {
        guard !strokes.isEmpty else { return cg }
        guard let patches = removeDefectsPatches(in: cg, strokes: strokes, parameters: parameters,
                                                 linear16: linear16, shouldCancel: shouldCancel) else { return nil }
        guard !patches.isEmpty else { return cg }
        let colorSpace = linear16
            ? CGColorSpace(name: CGColorSpace.linearSRGB)!
            : CGColorSpace(name: CGColorSpace.sRGB)!
        var working = CIImage(cgImage: cg, options: [.colorSpace: colorSpace])
        for p in patches {
            working = p.composited(over: working, strength: parameters.strength, colorSpace: colorSpace)
        }
        let context = linear16 ? DefectContext.renderLinear : DefectContext.render
        return context.createCGImage(working, from: working.extent,
                                     format: linear16 ? .RGBA16 : .RGBA8, colorSpace: colorSpace)
    }

    /// 강도 1.0 결과 패치(그룹 dirty rect 단위) 계산. 합성/강도 블렌드는 호출측 몫이다.
    /// 반환 nil = 취소/실패, 빈 배열 = 변경 없음.
    static func removeDefectsPatches(in cg: CGImage, strokes: [DefectStroke],
                                     parameters: SoftwareDefectParameters,
                                     linear16: Bool = false,
                                     shouldCancel: @escaping @Sendable () -> Bool = { false }) -> [DefectPatch]? {
        removeDefectsPatches(over: CIImage(cgImage: cg),
                             pixelWidth: cg.width, pixelHeight: cg.height,
                             strokes: strokes, parameters: parameters,
                             linear16: linear16, shouldCancel: shouldCancel)
    }

    /// CIImage 체인 버전 — 빌드 경로가 레이어마다 베이스 전체를 flatten 하지 않고 체인을 그대로
    /// 넘긴다. 여기서는 어차피 그룹 dirty rect(국소 창)만 렌더하므로 체인이어도 비용은 창 크기
    /// 비례다. pixelWidth/Height 는 스트로크 정규좌표(0..1)를 픽셀로 환산하는 원본 raw 크기다.
    static func removeDefectsPatches(over original: CIImage,
                                     pixelWidth pxW: Int, pixelHeight pxH: Int,
                                     strokes: [DefectStroke],
                                     parameters: SoftwareDefectParameters,
                                     linear16: Bool = false,
                                     shouldCancel: @escaping @Sendable () -> Bool = { false }) -> [DefectPatch]? {
        guard !strokes.isEmpty else { return [] }
        guard pxW > 0, pxH > 0 else { return [] }
        var fullStrength = parameters
        fullStrength.strength = 1.0
        let parameters = fullStrength
        let context = linear16 ? DefectContext.renderLinear : DefectContext.render
        let outFormat: CIFormat = linear16 ? .RGBA16 : .RGBA8
        let outColorSpace = linear16
            ? CGColorSpace(name: CGColorSpace.linearSRGB)!
            : CGColorSpace(name: CGColorSpace.sRGB)!
        @Sendable func flatten(_ image: CIImage, from rect: CGRect) -> CGImage? {
            context.createCGImage(image, from: rect, format: outFormat, colorSpace: outColorSpace)
        }
        let fullExtent = original.extent

        // 스트로크를 청크로 쪼개 처리한다 — roi 를 작게 유지해 풀 해상도로 검출(얇은 스크래치를
        // 놓치지 않고, 마스크 업스케일 번짐도 없음)하고 복원 비용도 제한한다.
        let chunks = strokes
            .flatMap { repairChunks(for: $0, pixelWidth: pxW, pixelHeight: pxH) }
            .filter { !$0.points.isEmpty }
        guard !chunks.isEmpty else { return [] }
        let extents = chunks.map { repairBounds(for: [$0], pixelWidth: pxW, pixelHeight: pxH) }

        // 겹치는 청크끼리 그룹으로 묶는다(union-find). 서로 분리된 그룹(떨어진 여러 브러시 칠,
        // 흩어진 먼지)은 메모리가 겹치지 않으므로 병렬 처리해도 안전하고 캐시 경합이 없다.
        let groups = clusterByOverlap(extents)

        // 그룹별로 독립 처리 → dirty 패치. concurrentPerform 으로 그룹을 코어에 분산한다
        // (per-region 단위 — per-pixel 분산은 오버헤드가 커 금물).
        let patches = DefectPatchResultStore(count: groups.count)
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
                let angle = strokeAngle(stroke, pixelWidth: pxW, pixelHeight: pxH)
                // 1순위: Heal(소스 복제+톤매칭 모델) — 칠한 영역을 이웃의 "실제 픽셀"로 복제 + 톤 매칭.
                // 검출에 의존하지 않아 실제 그레인 위에서도 밀림/블러가 원리적으로 불가능하다.
                // 유효 소스가 없으면(이미지 가장자리 등) 검출 기반 SoftwareDefectRemoval 로 폴백.
                working = DefectHealBrush.heal(to: working, brush: mask, repairExtent: extents[ci],
                                            preferredAngle: angle, strength: parameters.strength)
                    ?? SoftwareDefectRemoval.apply(to: working, parameters: parameters, brush: mask,
                                         repairExtent: extents[ci], preferredAngle: angle)
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
            patches.set((groupDirty, patch), at: gi)
        }
        if shouldCancel() { return nil }

        // 그룹 dirty rect 패치 목록(서로 분리 영역이라 합성 순서 무관).
        return patches.snapshot().compactMap { $0 }.map {
            DefectPatch(rect: $0.rect, image: $0.image)
        }
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
    /// 칠에만 값을 주고(점·둥근 칠은 nil → 전 방향 검출), 결함 제거가 그 방향의 스크래치만
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
        // halo 는 heal 소스 패치(직교 변위 최대 ~2.8×(두께+6))가 ROI 안에 들어오도록 스트로크
        // 폭에도 비례시킨다 — 부족하면 heal 이 항상 폴백(검출 기반)으로 빠진다.
        let maxLineWidth = strokes.map { max(1, $0.thickness * minDim) }.max() ?? 1
        let halo = max(96, max(minDim * 0.025, maxLineWidth * 3.2))
        return bounds.insetBy(dx: -halo, dy: -halo).integral.intersection(imageBounds)
    }

}

// MARK: - 페인팅 오버레이
