import CoreImage

// MARK: - ChromaDenoise (사용자 토글 노이즈 제거 — selective despeckle)
//
// **블러로 뭉개지 않는다.** 노이즈 픽셀(국소 median에서 벗어난 고립 outlier)만 골라 교체하고,
// 정상 픽셀·엣지·텍스처는 그대로 둔다. impulse/salt-pepper 제거 계열(median 기반)이라
// 디테일을 보존하면서 grain/색 speckle 픽셀만 직접 제거한다.
//
//   • lumaMed = 3x3 median → 암부 grain 픽셀 검출/교체.
//   • chromaMed = 더 큰 median(median을 두 번) → 컬러 speckle 픽셀 검출/교체.
//   • broadChroma = 넓은 chroma 기준 → 중간톤 컬러 얼룩만 분리해 감쇠.
public enum ChromaDenoise {
    /// - strength: 0...1 (0 = off). 검출 임계를 넓혀 강할수록 더 많은 노이즈 픽셀을 잡는다.
    public static func apply(to image: CIImage, strength: Double) -> CIImage {
        guard strength > 1e-3 else { return image }
        let extent = image.extent
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "despeckle") else { return image }
        // develop은 linear 공간이라 암부 노이즈 진폭이 압축돼 임계 아래로 떨어진다. 감마로 암부를
        // 들어올린 도메인에서 검출/교체해야 암부 grain·색 speckle이 잡힌다(ICE 검출과 같은 이유).
        let s = min(max(strength, 0), 1)
        let effectiveStrength = min(1.0, s * 1.28)
        let p = 0.45
        let lifted = image.applyingFilter("CIGammaAdjust", parameters: ["inputPower": p]).cropped(to: extent)
        // median은 엣지를 보존하면서 grain을 제거한다(중앙값 특성 — 평균 blur와 달리 step edge가 안 번짐).
        // 3x3 median(grain 작은 입자)과 그것을 한 번 더(≈5x5, 큰 입자/색 speckle) — 두 스케일.
        let med3 = median(lifted)
        let med5 = median(med3)
        let med7 = median(med5)   // ≈7x7 — 더 매끈한 타깃(큰 grain까지). median이라 엣지는 그대로.
        let luma = luminance(of: lifted)
        let lumaField = luma.applyingFilter("CIGaussianBlur", parameters: [
            "inputRadius": 1.6 + effectiveStrength * 2.2,
        ]).cropped(to: extent)
        let broadChroma = lifted.applyingFilter("CIGaussianBlur", parameters: [
            "inputRadius": 7.0 + effectiveStrength * 6.0,
        ]).cropped(to: extent)
        let despeckled = kernel.apply(extent: extent, arguments: [
            lifted, med5, med7, broadChroma, lumaField, effectiveStrength,
        ])?.cropped(to: extent) ?? lifted
        // 역감마로 원 도메인 복원.
        return despeckled.applyingFilter("CIGammaAdjust", parameters: ["inputPower": 1.0 / p]).cropped(to: extent)
    }

    /// 3x3 median(CIMedianFilter). impulse 노이즈를 제거하되 엣지는 보존한다.
    private static func median(_ image: CIImage) -> CIImage {
        let extent = image.extent
        if let f = CIFilter(name: "CIMedianFilter") {
            f.setValue(image, forKey: kCIInputImageKey)
            if let out = f.outputImage { return out.cropped(to: extent) }
        }
        return image
    }

    private static func luminance(of image: CIImage) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: image.extent)
    }

}
