import Foundation
import CoreImage
import CoreGraphics

// MARK: - NeutralBalance (scene-adaptive 미드톤 화이트밸런스)
//
// 컬러 네거티브 반전은 채널별 정규화(dmaxNorm)로 오렌지 마스크를 제거하지만, 그 추정이
// 채널마다 어긋나면 중간톤에 캐스트가 남는다(실측: Portra/Ektar/Vision3에서 빨강이 부족한
// 시안/틸 캐스트). 끝점(흑/백)은 AutoLevels가 이미 채널별로 맞추므로, 여기서는 **채널별
// 감마**로 중간톤만 중립으로 당긴다. 감마는 0→0, 1→1을 보존하므로 명부/암부에 새 캐스트를
// 만들지 않고 중간톤 색만 교정한다.
//
// 하드코딩이 아니라 장면에서 채널 median을 측정해 적용하는 scene-adaptive 방식이고,
// strength와 감마 클램프로 채도 높은 장면을 과교정하지 않게 제한한다.
public enum NeutralBalance {
    public static func apply(to image: CIImage,
                             sampleColorSpace: CGColorSpace? = nil,
                             strength: Double = 0.8) -> CIImage {
        guard let median = sampleMedian(image, sampleColorSpace: sampleColorSpace) else {
            return image
        }
        // 너무 어둡거나 밝은 median은 신뢰도가 낮아 건너뛴다(감마 교정이 불안정).
        let m = median
        guard m.x > 0.04, m.y > 0.04, m.z > 0.04,
              m.x < 0.96, m.y < 0.96, m.z < 0.96 else { return image }

        // 채널별 감마로 중립화. 감마는 0→0, 1→1을 보존하므로 흑/백 끝점을 건드리지 않고(새 캐스트
        // 없이) 중간톤~명부의 채널 균형만 잡는다. 게인(곱셈)보다 안전하고 일반화가 잘 된다.
        // 목표 = 세 채널 median의 기하평균(휘도 보존, 중립으로 수렴).
        // clamp [0.72, 1.4]: 베이스 오추정으로 생긴 큰 캐스트도 이 단계에서 충분히 보정할 수 있게.
        // (너무 좁히면 green dominance/염료 분리가 손상됨 — 테스트로 검증됨.)
        let target = pow(m.x * m.y * m.z, 1.0 / 3.0)
        func gamma(_ channelMedian: Double) -> Double {
            let raw = Foundation.log(target) / Foundation.log(channelMedian)   // median→target 매핑 감마
            let blended = 1.0 + (raw - 1.0) * strength
            return min(max(blended, 0.72), 1.4)
        }
        let gR = gamma(m.x), gG = gamma(m.y), gB = gamma(m.z)
        guard abs(gR - 1) > 0.01 || abs(gG - 1) > 0.01 || abs(gB - 1) > 0.01 else { return image }

        return applyPerChannelGamma(to: image, gR: gR, gG: gG, gB: gB)
    }

    /// 채널별 감마를 CIColorCube로 적용(채널 분리 변환이라 정확).
    private static func applyPerChannelGamma(to image: CIImage,
                                             gR: Double, gG: Double, gB: Double) -> CIImage {
        let dim = 32
        func curve(_ g: Double) -> [Float] {
            (0..<dim).map { Float(pow(Double($0) / Double(dim - 1), g)) }
        }
        let rC = curve(gR), gC = curve(gG), bC = curve(gB)
        var cube = [Float](repeating: 0, count: dim * dim * dim * 4)
        for b in 0..<dim {
            for g in 0..<dim {
                for r in 0..<dim {
                    let o = ((b * dim + g) * dim + r) * 4
                    cube[o] = rC[r]; cube[o + 1] = gC[g]; cube[o + 2] = bC[b]; cube[o + 3] = 1
                }
            }
        }
        return image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": dim,
            "inputCubeData": Data(bytes: cube, count: cube.count * MemoryLayout<Float>.size),
            "inputColorSpace": CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        ]).cropped(to: image.extent)
    }

    /// 작은 축소본을 렌더해 채널별 median을 구한다.
    static func sampleMedian(_ image: CIImage, sampleColorSpace: CGColorSpace?) -> SIMD3<Double>? {
        let extent = image.extent.integral
        guard extent.width > 8, extent.height > 8 else { return nil }
        let targetW = 192
        let scale = Double(targetW) / Double(extent.width)
        let targetH = max(1, Int(Double(extent.height) * scale))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        let cs = sampleColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var bitmap = [Float](repeating: 0, count: targetW * targetH * 4)
        SamplingContextPool.context(workingColorSpace: cs).render(
            scaled, toBitmap: &bitmap,
            rowBytes: targetW * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
            format: .RGBAf, colorSpace: cs)
        let n = targetW * targetH
        guard n >= 64 else { return nil }
        var r = [Double](repeating: 0, count: n), g = r, b = r
        for i in 0..<n { r[i] = Double(bitmap[i*4]); g[i] = Double(bitmap[i*4+1]); b[i] = Double(bitmap[i*4+2]) }
        r.sort(); g.sort(); b.sort()
        let mid = n / 2
        return SIMD3(r[mid], g[mid], b[mid])
    }
}
