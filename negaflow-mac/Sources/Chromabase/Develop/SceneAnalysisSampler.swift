import CoreImage
import CoreGraphics
import Foundation

/// Bounded, area-weighted linear samples. Windows uses the same cell boundaries.
enum SceneAnalysisSampler {
    struct Grid {
        let width: Int
        let height: Int
        let pixels: [SIMD3<Double>]
        let clippedFractions: [Double]
    }

    static func sample(_ image: CIImage, longEdge: Int, inset: Double = 0) -> Grid? {
        let e = image.extent.integral
        guard e.width.isFinite, e.height.isFinite, e.width > 0, e.height > 0 else { return nil }
        let scale = min(1, Double(max(1, min(longEdge, 512))) / max(e.width, e.height))
        let w = max(1, Int(e.width * scale)), h = max(1, Int(e.height * scale))
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        guard let kernel = ChromabaseMetalKernels.generalKernel(named: "sceneAreaSamples"),
              let reduced = kernel.apply(extent: bounds, roiCallback: { _, _ in e }, arguments: [
                image, CIVector(cgRect: e), CIVector(x: CGFloat(w), y: CGFloat(h))
              ]) else { return nil }
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        var data = [Float](repeating: 0, count: w * h * 4)
        SamplingContextPool.context(workingColorSpace: linear, fullPrecision: true).render(reduced, toBitmap: &data,
            rowBytes: w * 16, bounds: bounds, format: .RGBAf, colorSpace: linear)
        let ix = min(w / 2, Int(Double(w) * inset)), iy = min(h / 2, Int(Double(h) * inset))
        let xEnd = max(ix + 1, w - ix), yEnd = max(iy + 1, h - iy)
        var pixels: [SIMD3<Double>] = [], clipped: [Double] = []
        pixels.reserveCapacity((xEnd - ix) * (yEnd - iy)); clipped.reserveCapacity(pixels.capacity)
        for y in iy..<yEnd { for x in ix..<xEnd {
            let i = (y * w + x) * 4
            let p = SIMD3(Double(data[i]), Double(data[i + 1]), Double(data[i + 2]))
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { continue }
            pixels.append(p); clipped.append(max(p.x, max(p.y, p.z)) >= 0.995 ? 1 : 0)
        }}
        return pixels.isEmpty ? nil : Grid(width: xEnd - ix, height: yEnd - iy,
                                           pixels: pixels, clippedFractions: clipped)
    }
}
