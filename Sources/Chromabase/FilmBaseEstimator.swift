import Foundation
import CoreImage

// MARK: - FilmBaseEstimator (plan §8.5)
//
// 네거티브 반전의 핵심. 필름 베이스(오렌지 마스크 기저색)를 추정한다.
//
// 자동 방식 (plan §8.5):
//   1. 이미지 가장자리(프레임 밖 필름 베이스 영역)에서 후보 픽셀 수집
//   2. 너무 어둡거나 너무 밝은 영역 제외
//   3. RGB 채널 중앙값 기반 추정 + 이상치 제거
public enum FilmBaseEstimator {
    /// 가장자리 영역에서 필름 베이스를 추정한다.
    public static func estimate(from image: CIImage, edgeFraction: Double = 0.06) -> FilmBase? {
        let extent = image.extent
        guard extent.width > 4, extent.height > 4 else { return nil }

        let edgeSample = sampleBrightOrangeBase(from: image, edgeFraction: edgeFraction)
        let distributedSample = sampleDistributedOrangeBase(from: image)
        if let edgeSample, let distributedSample {
            let edgeLuma = (edgeSample.x + edgeSample.y + edgeSample.z) / 3
            let distributedLuma = (distributedSample.x + distributedSample.y + distributedSample.z) / 3
            if edgeLuma >= distributedLuma * 0.85 {
                return FilmBase(rgb: edgeSample, source: .border)
            }
            return FilmBase(rgb: distributedSample, source: .auto)
        }
        if let edgeSample {
            return FilmBase(rgb: edgeSample, source: .border)
        }
        if let distributedSample {
            return FilmBase(rgb: distributedSample, source: .auto)
        }

        // 가장자리 스트립 영역 정의 (위/아래/좌/우 테두리).
        let ex = edgeFraction
        let top    = image.cropped(to: CGRect(x: extent.minX, y: extent.maxY - extent.height*ex,
                                              width: extent.width, height: extent.height*ex))
        let bottom = image.cropped(to: CGRect(x: extent.minX, y: extent.minY,
                                              width: extent.width, height: extent.height*ex))
        let left   = image.cropped(to: CGRect(x: extent.minX, y: extent.minY,
                                              width: extent.width*ex, height: extent.height))
        let right  = image.cropped(to: CGRect(x: extent.maxX - extent.width*ex, y: extent.minY,
                                              width: extent.width*ex, height: extent.height))

        // 각 채널의 중앙값을 구하기 위해 픽셀을 샘플링한다.
        // Core Image의 CIAreaAverage로 영역 평균을 구한 뒤, 여러 스트립의 중앙값을 취한다.
        let samples = [top, bottom, left, right].compactMap { region -> SIMD3<Double>? in
            averageRGB(of: region)
        }
        guard !samples.isEmpty else { return nil }

        // 이상치(극단적으로 어둡거나 밝은 스트립) 제거.
        let filtered = samples.filter { s in
            let lum = (s.x + s.y + s.z) / 3
            return lum > 0.25 && lum < 0.97   // 필름 베이스는 보통 이 범위
        }
        guard !filtered.isEmpty else { return nil }
        let use = filtered

        // 채널별 중앙값.
        let r = median(use.map(\.x))
        let g = median(use.map(\.y))
        let b = median(use.map(\.z))
        guard r > 0, g > 0, b > 0 else { return nil }
        return FilmBase(rgb: SIMD3(r, g, b), source: .border)
    }

    static func sampleBrightOrangeBase(from image: CIImage, edgeFraction: Double) -> SIMD3<Double>? {
        let extent = image.extent.integral
        let targetW = max(32, min(256, Int(extent.width)))
        let scale = Double(targetW) / Double(extent.width)
        let targetH = max(1, Int(Double(extent.height) * scale))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let cs = CGColorSpace(name: CGColorSpace.genericRGBLinear) ?? CGColorSpaceCreateDeviceRGB()
        var bitmap = [Float](repeating: 0, count: targetW * targetH * 4)
        let ctx = SamplingContextPool.context(workingColorSpace: nil)
        ctx.render(scaled, toBitmap: &bitmap,
                   rowBytes: targetW * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
                   format: .RGBAf, colorSpace: cs)

        let edgeX = max(1, Int(Double(targetW) * edgeFraction))
        let edgeY = max(1, Int(Double(targetH) * edgeFraction))
        var border: [(x: Int, y: Int, r: Double, g: Double, b: Double, luma: Double)] = []
        var all: [(x: Int, y: Int, r: Double, g: Double, b: Double, luma: Double)] = []
        for y in 0..<targetH {
            for x in 0..<targetW {
                let i = (y * targetW + x) * 4
                let r = Double(bitmap[i])
                let g = Double(bitmap[i + 1])
                let b = Double(bitmap[i + 2])
                guard isFilmBaseCandidate(r: r, g: g, b: b) else { continue }
                let sample = (x: x, y: y, r: r, g: g, b: b, luma: (r + g + b) / 3)
                all.append(sample)
                if x < edgeX || x >= targetW - edgeX || y < edgeY || y >= targetH - edgeY {
                    border.append(sample)
                }
            }
        }

        let candidates = border.count >= 16 ? border : all
        guard candidates.count >= 8 else { return nil }
        let lumaCut = percentile(candidates.map(\.luma), 0.95)
        let bright = candidates.filter { $0.luma >= lumaCut }
        guard bright.count >= 4 else { return nil }
        let minimumHorizontalCoverage = Int(Double(targetW) * 0.65)
        let minimumVerticalCoverage = Int(Double(targetH) * 0.65)
        let hasContinuousEdge = (0..<targetH).contains { y in
            (y < edgeY || y >= targetH - edgeY)
                && bright.filter { $0.y == y }.count >= minimumHorizontalCoverage
        } || (0..<targetW).contains { x in
            (x < edgeX || x >= targetW - edgeX)
                && bright.filter { $0.x == x }.count >= minimumVerticalCoverage
        }
        guard hasContinuousEdge else { return nil }

        return SIMD3(
            percentile(bright.map(\.r), 0.95),
            percentile(bright.map(\.g), 0.95),
            percentile(bright.map(\.b), 0.95)
        )
    }

    static func sampleDistributedOrangeBase(from image: CIImage) -> SIMD3<Double>? {
        let extent = image.extent.integral
        let targetW = max(32, min(256, Int(extent.width)))
        let scale = Double(targetW) / Double(extent.width)
        let targetH = max(1, Int(Double(extent.height) * scale))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let cs = CGColorSpace(name: CGColorSpace.genericRGBLinear) ?? CGColorSpaceCreateDeviceRGB()
        var bitmap = [Float](repeating: 0, count: targetW * targetH * 4)
        let ctx = SamplingContextPool.context(workingColorSpace: nil)
        ctx.render(scaled, toBitmap: &bitmap,
                   rowBytes: targetW * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
                   format: .RGBAf, colorSpace: cs)

        var candidates: [(r: Double, g: Double, b: Double, luma: Double)] = []
        for y in 0..<targetH {
            for x in 0..<targetW {
                let i = (y * targetW + x) * 4
                let r = Double(bitmap[i])
                let g = Double(bitmap[i + 1])
                let b = Double(bitmap[i + 2])
                guard isFilmBaseCandidate(r: r, g: g, b: b) else { continue }
                candidates.append((r, g, b, (r + g + b) / 3))
            }
        }
        guard candidates.count >= 32 else { return nil }

        let lumas = candidates.map(\.luma)
        let lumaCut = percentile(lumas, 0.95)
        let medianLuma = percentile(lumas, 0.50)
        guard lumaCut - medianLuma >= 0.02 else { return nil }

        let bright = candidates.filter { $0.luma >= lumaCut }
        let minimumCount = max(32, Int(Double(candidates.count) * 0.02))
        guard bright.count >= minimumCount else { return nil }

        return SIMD3(
            percentile(bright.map(\.r), 0.90),
            percentile(bright.map(\.g), 0.90),
            percentile(bright.map(\.b), 0.90)
        )
    }

    /// 필름 베이스 후보 판정. 과거엔 `r > g*1.12 && g > b*1.05`로 "진한 주황"만 강제했으나,
    /// 이는 Kodak Portra/Gold 계열만 통과시키고 Fuji 황/옅은 베이스, Vision3(ECN-2), 퇴색 분홍
    /// 베이스를 전부 탈락시켜 fallback (0.9,0.65,0.45) 로 떨어지게 했다(→ 반전 캐스트의 근원).
    ///
    /// 물리적 정의로 교체: 컬러 네거티브 베이스(미노광 + 잔류 염료)는 **항상 R≥G≥B 단조**다.
    /// 오렌지 마스크는 마젠타+황 염료의 조합이므로 R이 가장 높고 B가 가장 낮으며, 그 비율은
    /// 필름/현상마다 다르다(Fuji는 더 황/투명, Kodak은 더 진한 주황, ECN-2는 또 다름).
    /// 따라서 색 강도가 아니라 **R≥G≥B 단조성**만으로 후보를 식별한다. luma 범위는 미노광/염료
    /// 투과율의 합리적 범위로 유지.
    static func isFilmBaseCandidate(r: Double, g: Double, b: Double) -> Bool {
        let luma = (r + g + b) / 3
        // luma 상한: 미노광 베이스는 스캐너에서 중간~밝게 나오지만, 거의 흰(0.90+) 무필름 빈 공간
        // (홀더/마운트 간극)은 베이스가 아니다. 0.85 상한은 Fuji 옅은/황 베이스(최대 ~0.82)까지 커버.
        guard luma >= 0.03, luma <= 0.85 else { return false }
        // R≥G≥B 단조 (허용 오차: 노이즈/베이스 불균일성). 컬러 네거티브 베이스는 항상 R≥G≥B.
        let eps = 0.01
        guard r >= g - eps, g >= b - eps else { return false }
        // R-B 최소 분리: 진짜 베이스(마젠타+황 염료)는 R이 B보다 유의미하게 높다. 필름마다 강도가
        // 다르나(Fuji 옅음, Kodak 진함), 거의 중립 회색에 가까운 무필름 빈 공간(R-B≈0.1)과 구분하기
        // 위해 0.06 하한. Fuji 황 베이스(0.82,0.70,0.56 → R-B=0.26)도 여유 통과.
        return (r - b) >= 0.06
    }

    /// 영역의 평균 RGB를 구한다 (CIAreaAverage).
    static func averageRGB(of image: CIImage) -> SIMD3<Double>? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ])
        guard let out = filter?.outputImage else { return nil }
        var bitmap = [Float](repeating: 0, count: 4)
        let ctx = SamplingContextPool.context(workingColorSpace: nil)
        ctx.render(out, toBitmap: &bitmap,
                   rowBytes: 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
        return SIMD3(Double(bitmap[0]), Double(bitmap[1]), Double(bitmap[2]))
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 0 ? (s[n/2 - 1] + s[n/2]) / 2 : s[n/2]
    }

    static func percentile(_ xs: [Double], _ fraction: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let index = max(0, min(s.count - 1, Int(Double(s.count - 1) * fraction)))
        return s[index]
    }
}
