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

        if let sampled = sampleBrightOrangeBase(from: image, edgeFraction: edgeFraction) {
            return FilmBase(rgb: sampled, source: .border)
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
        let use = filtered.isEmpty ? samples : filtered

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
        var bitmap = [UInt8](repeating: 0, count: targetW * targetH * 4)
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        ctx.render(scaled, toBitmap: &bitmap, rowBytes: targetW * 4,
                   bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
                   format: .RGBA8, colorSpace: cs)

        let edgeX = max(1, Int(Double(targetW) * edgeFraction))
        let edgeY = max(1, Int(Double(targetH) * edgeFraction))
        var border: [(r: Int, g: Int, b: Int, luma: Int)] = []
        var all: [(r: Int, g: Int, b: Int, luma: Int)] = []
        for y in 0..<targetH {
            for x in 0..<targetW {
                let i = (y * targetW + x) * 4
                let r = Int(bitmap[i])
                let g = Int(bitmap[i + 1])
                let b = Int(bitmap[i + 2])
                guard r > 12, r > g, g >= b else { continue }
                let sample = (r: r, g: g, b: b, luma: (r + g + b) / 3)
                all.append(sample)
                if x < edgeX || x >= targetW - edgeX || y < edgeY || y >= targetH - edgeY {
                    border.append(sample)
                }
            }
        }

        let candidates = border.count >= 16 ? border : all
        guard candidates.count >= 8 else { return nil }
        let lumaCut = percentile(candidates.map(\.luma), 0.90)
        let bright = candidates.filter { $0.luma >= lumaCut }
        guard bright.count >= 4 else { return nil }

        return SIMD3(
            Double(percentile(bright.map(\.r), 0.95)) / 255.0,
            Double(percentile(bright.map(\.g), 0.95)) / 255.0,
            Double(percentile(bright.map(\.b), 0.95)) / 255.0
        )
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
        var bitmap = [UInt8](repeating: 0, count: 4)
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        ctx.render(out, toBitmap: &bitmap, rowBytes: 4,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return SIMD3(Double(bitmap[0])/255.0,
                     Double(bitmap[1])/255.0,
                     Double(bitmap[2])/255.0)
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 0 ? (s[n/2 - 1] + s[n/2]) / 2 : s[n/2]
    }

    static func percentile(_ xs: [Int], _ fraction: Double) -> Int {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let index = max(0, min(s.count - 1, Int(Double(s.count - 1) * fraction)))
        return s[index]
    }
}
