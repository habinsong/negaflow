import Foundation
import CoreImage

// MARK: - ToneMapper (plan §8.7)
//
// density / highlight roll-off / black softness / contrast를 다룬다.
// 필름 스캔에서 중요한 건 density, roll-off, black softness다 (plan §8.7).
public enum ToneMapper {
    /// 노출(stops) 보정. gamma로 근사.
    public static func applyExposure(to image: CIImage, stops: Double) -> CIImage {
        guard abs(stops) > 1e-3 else { return image }
        // +1 stop = ×2 선형 = gamma 0.5 근사가 아님; 선형 곱이 정확.
        let factor = pow(2.0, stops)
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(factor), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(factor), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(factor), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])
    }

    /// 톤 커브: density / highlight roll-off / shadow softness.
    public static func applyToneCurves(to image: CIImage, params: DevelopParameters) -> CIImage {
        var img = image
        let extent = image.extent

        if hasBasicToneChange(params) {
            img = applyBasicTone(to: img, params: params)
        }

        img = applyParametricCurve(to: img, params: params)
        return img.cropped(to: extent)
    }

    private static func hasBasicToneChange(_ params: DevelopParameters) -> Bool {
        [
            params.contrast,
            params.density,
            params.highlight,
            params.shadow,
            params.whites,
            params.blacks,
        ].contains { abs($0) > 1e-3 }
    }

    private static func applyBasicTone(to image: CIImage, params: DevelopParameters) -> CIImage {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "basicTone") else { return image }
        return kernel.apply(extent: image.extent, arguments: [
            image,
            Float(params.contrast),
            Float(params.density),
            Float(params.highlight),
            Float(params.shadow),
            Float(params.whites),
            Float(params.blacks),
        ])?.cropped(to: image.extent) ?? image
    }

    private static func applyParametricCurve(to image: CIImage, params: DevelopParameters) -> CIImage {
        let values = [
            params.curveHighlights, params.curveLights,
            params.curveDarks, params.curveShadows,
        ]
        guard values.contains(where: { abs($0) > 1e-3 }) else {
            return image
        }

        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "parametricToneCurve") else { return image }
        let bands = parametricCurveBands(for: image)
        return kernel.apply(extent: image.extent, arguments: [
            image,
            Float(params.curveHighlights),
            Float(params.curveLights),
            Float(params.curveDarks),
            Float(params.curveShadows),
            Float(bands.shadowLow),
            Float(bands.shadowHigh),
            Float(bands.darkLow),
            Float(bands.darkHigh),
            Float(bands.lightLow),
            Float(bands.lightHigh),
            Float(bands.highlightLow),
            Float(bands.highlightHigh),
        ])?.cropped(to: image.extent) ?? image
    }

    private struct ParametricCurveBands {
        let shadowLow: Double
        let shadowHigh: Double
        let darkLow: Double
        let darkHigh: Double
        let lightLow: Double
        let lightHigh: Double
        let highlightLow: Double
        let highlightHigh: Double
    }

    private static func parametricCurveBands(for image: CIImage) -> ParametricCurveBands {
        guard let sampled = sampleLumaPercentiles(from: image) else {
            return ParametricCurveBands(
                shadowLow: 0.05,
                shadowHigh: 0.24,
                darkLow: 0.18,
                darkHigh: 0.36,
                lightLow: 0.34,
                lightHigh: 0.68,
                highlightLow: 0.36,
                highlightHigh: 0.50
            )
        }
        let p10 = sampled[0]
        let p35 = max(sampled[1], p10 + 0.025)
        let p65 = max(sampled[2], p35 + 0.025)
        let p90 = max(sampled[3], p65 + 0.025)
        return ParametricCurveBands(
            shadowLow: max(0.0, p10 - 0.020),
            shadowHigh: p35,
            darkLow: p35,
            darkHigh: p65,
            lightLow: p65,
            lightHigh: p90,
            highlightLow: p65,
            highlightHigh: min(1.0, p90 + 0.030)
        )
    }

    private static func sampleLumaPercentiles(from image: CIImage) -> [Double]? {
        let extent = image.extent.integral
        guard extent.width > 8, extent.height > 8,
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        let targetW = max(64, min(256, Int(extent.width)))
        let scale = Double(targetW) / Double(extent.width)
        let targetH = max(1, Int(Double(extent.height) * scale))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var bitmap = [Float](repeating: 0, count: targetW * targetH * 4)
        SamplingContextPool.context(workingColorSpace: linear).render(
            scaled,
            toBitmap: &bitmap,
            rowBytes: targetW * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
            format: .RGBAf,
            colorSpace: linear
        )
        let insetX = max(1, Int(Double(targetW) * 0.04))
        let insetY = max(1, Int(Double(targetH) * 0.04))
        var luma = [Double]()
        luma.reserveCapacity(targetW * targetH)
        for y in insetY..<max(insetY + 1, targetH - insetY) {
            for x in insetX..<max(insetX + 1, targetW - insetX) {
                let i = (y * targetW + x) * 4
                luma.append(Double(bitmap[i]) * 0.2126 + Double(bitmap[i + 1]) * 0.7152 + Double(bitmap[i + 2]) * 0.0722)
            }
        }
        guard luma.count >= 64 else { return nil }
        luma.sort()
        func pct(_ fraction: Double) -> Double {
            let index = max(0, min(luma.count - 1, Int(Double(luma.count - 1) * fraction)))
            return min(max(luma[index], 0.0), 1.0)
        }
        return [pct(0.10), pct(0.35), pct(0.65), pct(0.90)]
    }

}
