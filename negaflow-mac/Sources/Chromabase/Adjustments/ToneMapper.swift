import Foundation
import CoreImage

// MARK: - ToneMapper (plan §8.7)
//
// density / highlight roll-off / black softness / contrast를 다룬다.
// 필름 스캔에서 중요한 건 density, roll-off, black softness다 (plan §8.7).
public enum ToneMapper {
    /// 노출(stops) 보정. −는 선형 광량에 2^stops 를 곱하고, +는 확산 화이트 아래를 2^stops 로
    /// 정확히 올리되 명부를 숄더로 접는다(ExposureShoulder).
    public static func applyExposure(to image: CIImage, stops: Double,
                                     filmType: FilmType = .colorNegative) -> CIImage {
        guard stops.isFinite, abs(stops) > 1e-3 else { return image }
        // +1 stop = ×2 선형 = gamma 0.5 근사가 아님; 선형 곱이 정확.
        let factor = pow(2.0, stops)
        guard factor.isFinite, factor > 0 else { return image }
        if let shouldered = ExposureShoulder.apply(to: image, gain: factor, stops: stops, filmType: filmType) {
            return shouldered
        }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(factor), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(factor), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(factor), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])
    }

    /// 톤 커브: density / highlight roll-off / shadow softness.
    public static func applyToneCurves(to image: CIImage, params: DevelopParameters,
                                       region: AnalysisRegion? = nil) -> CIImage {
        var img = image
        let extent = image.extent

        if hasBasicToneChange(params) {
            img = applyBasicTone(to: img, params: params)
        }

        img = applyParametricCurve(to: img, params: params, region: region)
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

    private static func applyParametricCurve(to image: CIImage, params: DevelopParameters,
                                             region: AnalysisRegion?) -> CIImage {
        let values = [
            params.curveHighlights, params.curveLights,
            params.curveDarks, params.curveShadows,
        ]
        guard values.contains(where: { abs($0) > 1e-3 }) else {
            return image
        }

        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "parametricToneCurve") else { return image }
        let curve = ParametricToneCurve(
            percentiles: sampleLumaPercentiles(from: AnalysisRegion.measurementImage(image, region: region)),
            highlights: params.curveHighlights, lights: params.curveLights,
            darks: params.curveDarks, shadows: params.curveShadows)
        let x: [CGFloat] = curve.x.map { (v: Double) -> CGFloat in CGFloat(v) }
        let y: [CGFloat] = curve.y.map { (v: Double) -> CGFloat in CGFloat(v) }
        let m: [CGFloat] = curve.tangent.map { (v: Double) -> CGFloat in CGFloat(v) }
        return kernel.apply(extent: image.extent, arguments: [
            image,
            CIVector(x: x[1], y: x[2], z: x[3], w: x[4]),
            CIVector(x: y[1], y: y[2], z: y[3], w: y[4]),
            CIVector(x: m[0], y: m[1], z: m[2]),
            CIVector(x: m[3], y: m[4], z: m[5]),
        ])?.cropped(to: image.extent) ?? image
    }

    static func sampleLumaPercentiles(from image: CIImage) -> [Double]? {
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
