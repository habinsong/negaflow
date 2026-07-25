import Foundation
import CoreGraphics
import CoreImage

// MARK: - 복제 도장 (사용자 지정 소스 오프셋 복제)
//
// 브러시 결함 제거(검출·복원)와 달리 아무것도 추정하지 않는다: 사용자가 ⌥클릭으로 지정한 소스 지점의
// "실제 픽셀"을 고정 오프셋으로 그대로 복제한다. 결과 = 소스 픽셀 × 브러시 알파 + 원본 × (1−알파).
// 스트로크는 브러시와 같은 규약(변형 전 raw 정규좌표, y-down)으로 저장해 회전/플립/크롭/미세회전
// 후에도 같은 위치에 재적용된다.

/// 복제 도장 스트로크 1획. 좌표·오프셋은 변형 전 raw 정규(0..1, y-down).
struct CloneStampStroke {
    var points: [CGPoint]    // 대상 경로
    var offset: CGVector     // 소스 − 대상 (정규, y-down)
    var diameter: CGFloat    // 브러시 지름(raw 픽셀)
    var hardness: CGFloat    // 경도 0~1. 1 = 단단한 가장자리(안티앨리어스 1px만), 0 = 중심부터 페더
}

enum CloneStampBrush {
    /// 도장 간격(지름 대비). 표준 라운드 브러시 기본값 — 스탬프가 src-over 로 누적되면
    /// 경로 중심은 불투명, 가장자리는 경도 페더가 유지된다.
    static let stampSpacingFraction: CGFloat = 0.25
    /// 경도 1.0에서도 유지하는 안티앨리어스 폭(픽셀).
    static let antialiasPixels: CGFloat = 1.0

    /// 도장 1개의 알파. t = 중심 거리/반경(0..1+), h 안쪽은 1, 바깥은 smoothstep 으로 0.
    /// 경도가 1이어도 가장자리 ~1px 은 부드럽게 남긴다(계단 현상 방지).
    static func stampAlpha(normalizedDistance t: CGFloat, hardness: CGFloat, radius: CGFloat) -> CGFloat {
        guard t < 1 else { return 0 }
        let h = min(max(hardness, 0), max(0, 1 - antialiasPixels / max(radius, 1)))
        guard t > h else { return 1 }
        let u = (t - h) / max(1 - h, 1e-6)
        return (1 - u) * (1 - u) * (1 + 2 * u)   // smoothstep(1→0)
    }

    /// 강도 1.0 결과 패치 계산(스트로크당 1개). 반환 nil = 취소, 빈 배열 = 변경 없음.
    /// 스트로크는 순차 적용된다 — 뒤 스트로크가 앞 스트로크의 결과 위를 소스로 삼을 수 있다.
    static func patches(over original: CIImage,
                        pixelWidth pxW: Int, pixelHeight pxH: Int,
                        strokes: [CloneStampStroke],
                        shouldCancel: @escaping @Sendable () -> Bool = { false }) -> [DefectPatch]? {
        guard pxW > 0, pxH > 0, !strokes.isEmpty else { return [] }
        var working = original
        var out: [DefectPatch] = []
        for stroke in strokes {
            if shouldCancel() { return nil }
            guard let patch = patch(over: working, pxW: pxW, pxH: pxH,
                                    stroke: stroke, shouldCancel: shouldCancel) else {
                if shouldCancel() { return nil }
                continue   // 소스 전부 범위 밖 등 — 이 스트로크는 변경 없음
            }
            out.append(patch)
            working = CIImage(cgImage: patch.image, options: [.colorSpace: linearColorSpace])
                .transformed(by: CGAffineTransform(translationX: patch.rect.minX, y: patch.rect.minY))
                .composited(over: working)
        }
        return out
    }

    // MARK: 스트로크 1획 → 패치

    private static func patch(over image: CIImage, pxW: Int, pxH: Int,
                              stroke: CloneStampStroke,
                              shouldCancel: @escaping @Sendable () -> Bool) -> DefectPatch? {
        guard !stroke.points.isEmpty, stroke.diameter > 0 else { return nil }
        // 오프셋은 정수 픽셀로 스냅한다 — 리샘플 없이 원본 그레인을 그대로 복제한다(0.5px 미만 오차).
        let odx = Int((stroke.offset.dx * CGFloat(pxW)).rounded())
        let ody = Int((stroke.offset.dy * CGFloat(pxH)).rounded())
        guard odx != 0 || ody != 0 else { return nil }   // 제자리 복제 = 무변경

        let radius = max(0.5, stroke.diameter / 2)
        let pts = stroke.points.map {
            CGPoint(x: $0.x * CGFloat(pxW), y: $0.y * CGFloat(pxH))   // y-down 픽셀
        }

        // dirty rect(y-down, 이미지 내로 클램프).
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let pad = radius + antialiasPixels + 1
        let dx0 = max(0, Int((minX - pad).rounded(.down)))
        let dy0 = max(0, Int((minY - pad).rounded(.down)))
        let dx1 = min(pxW, Int((maxX + pad).rounded(.up)))
        let dy1 = min(pxH, Int((maxY + pad).rounded(.up)))
        let dw = dx1 - dx0, dh = dy1 - dy0
        guard dw > 0, dh > 0 else { return nil }

        // 브러시 알파 마스크(dirty 로컬, y-down). 도장을 경로 간격대로 src-over 누적.
        var mask = [Float](repeating: 0, count: dw * dh)
        let spacing = max(1, stroke.diameter * stampSpacingFraction)
        for c in stampCenters(along: pts, spacing: spacing) {
            if shouldCancel() { return nil }
            let sx0 = max(dx0, Int((c.x - radius - 1).rounded(.down)))
            let sy0 = max(dy0, Int((c.y - radius - 1).rounded(.down)))
            let sx1 = min(dx1, Int((c.x + radius + 1).rounded(.up)))
            let sy1 = min(dy1, Int((c.y + radius + 1).rounded(.up)))
            guard sx0 < sx1, sy0 < sy1 else { continue }
            for y in sy0..<sy1 {
                let row = (y - dy0) * dw - dx0
                let py = CGFloat(y) + 0.5 - c.y
                for x in sx0..<sx1 {
                    let px = CGFloat(x) + 0.5 - c.x
                    let t = ((px * px + py * py).squareRoot()) / radius
                    let a = Float(stampAlpha(normalizedDistance: t, hardness: stroke.hardness, radius: radius))
                    guard a > 0 else { continue }
                    let i = row + x
                    mask[i] += a * (1 - mask[i])
                }
            }
        }

        // 소스가 이미지 밖으로 나가는 픽셀은 복제하지 않는다(무변경).
        for y in 0..<dh {
            let sy = y + dy0 + ody
            let rowOOB = sy < 0 || sy >= pxH
            let row = y * dw
            for x in 0..<dw where mask[row + x] > 0 {
                let sx = x + dx0 + odx
                if rowOOB || sx < 0 || sx >= pxW { mask[row + x] = 0 }
            }
        }

        // 실제로 변한 영역(bbox)만 렌더한다 — 패치가 결함 크기에 비례한다.
        var bx0 = dw, by0 = dh, bx1 = -1, by1 = -1
        for y in 0..<dh {
            let row = y * dw
            for x in 0..<dw where mask[row + x] > 0 {
                if x < bx0 { bx0 = x }
                if x > bx1 { bx1 = x }
                if y < by0 { by0 = y }
                if y > by1 { by1 = y }
            }
        }
        guard bx1 >= bx0, by1 >= by0 else { return nil }
        let bw = bx1 - bx0 + 1, bh = by1 - by0 + 1
        let gx0 = dx0 + bx0, gy0 = dy0 + by0   // bbox 좌상단(y-down 전역)

        if shouldCancel() { return nil }

        // 대상/소스 창을 같은 크기로 렌더한다(y-up rect). 두 창의 같은 인덱스가 오프셋 관계다.
        let destYup = CGRect(x: CGFloat(gx0), y: CGFloat(pxH - (gy0 + bh)),
                             width: CGFloat(bw), height: CGFloat(bh))
        let srcYup = destYup.offsetBy(dx: CGFloat(odx), dy: CGFloat(-ody))
        let rowBytes = bw * 4 * MemoryLayout<Float>.size
        var dst = [Float](repeating: 0, count: bw * bh * 4)
        var src = [Float](repeating: 0, count: bw * bh * 4)
        cleanedRawContext.render(image, toBitmap: &dst, rowBytes: rowBytes,
                                 bounds: destYup, format: .RGBAf, colorSpace: linearColorSpace)
        cleanedRawContext.render(image, toBitmap: &src, rowBytes: rowBytes,
                                 bounds: srcYup, format: .RGBAf, colorSpace: linearColorSpace)

        // 합성: out = src·α + dst·(1−α). 비트맵 행은 위→아래라 mask(y-down)와 같은 순서다.
        var out16 = [UInt16](repeating: 0, count: bw * bh * 4)
        for y in 0..<bh {
            let maskRow = (y + by0) * dw + bx0
            let bmpRow = y * bw
            for x in 0..<bw {
                let a = mask[maskRow + x]
                let o = (bmpRow + x) * 4
                for ch in 0..<3 {
                    let v = a > 0 ? src[o + ch] * a + dst[o + ch] * (1 - a) : dst[o + ch]
                    out16[o + ch] = UInt16((min(max(v, 0), 1) * 65535).rounded())
                }
                out16[o + 3] = 0xFFFF
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes: out16, count: out16.count * 2) as CFData),
              let cg = CGImage(width: bw, height: bh, bitsPerComponent: 16, bitsPerPixel: 64,
                               bytesPerRow: bw * 8, space: linearColorSpace,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                                   | CGBitmapInfo.byteOrder16Little.rawValue),
                               provider: provider, decode: nil,
                               shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return DefectPatch(rect: destYup, image: cg)
    }

    /// 경로를 따라 spacing(픽셀) 간격의 도장 중심 목록. 첫 점에는 항상 도장을 찍는다.
    static func stampCenters(along points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard let first = points.first else { return [] }
        var centers = [first]
        guard points.count > 1 else { return centers }
        var distSinceStamp: CGFloat = 0
        var prev = first
        for p in points.dropFirst() {
            var segStart = prev
            var remaining = hypot(p.x - segStart.x, p.y - segStart.y)
            while distSinceStamp + remaining >= spacing, remaining > 1e-6 {
                let need = spacing - distSinceStamp
                let t = need / remaining
                let c = CGPoint(x: segStart.x + (p.x - segStart.x) * t,
                                y: segStart.y + (p.y - segStart.y) * t)
                centers.append(c)
                segStart = c
                remaining -= need
                distSinceStamp = 0
            }
            distSinceStamp += remaining
            prev = p
        }
        return centers
    }
}
