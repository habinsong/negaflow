import CoreImage

// MARK: - ScannerNoiseReduction
//
// 필름 스캔 노이즈는 두 종류다.
//   • 컬러 노이즈(chroma): 색 반점. 특히 암부에서 붉은/녹색 얼룩으로 나타난다.
//   • 휘도 노이즈(luma):   밝기 입자. 필름 그레인과 섞여 있어 과하게 지우면 디테일이 죽는다.
//
// 검증된 접근(Lightroom/Capture One 계열과 동일한 원리):
//   휘도(luma)는 보존하고 chroma만 부드럽게 한다. 색차 성분만 블러하면
//   디테일(엣지/그레인)은 유지되면서 색 얼룩만 사라진다. 암부일수록 더 강하게.
//
// 이전 구현의 `apply`는 중심 가중치가 큰 커널(샤픈)이라 노이즈를 증폭했다 — 제거했다.
enum ScannerNoiseReduction {
    /// 라이트 톤의 컬러 노이즈 제거(약). 반전 후 positive에 적용한다.
    static func apply(to image: CIImage) -> CIImage {
        reduceColorNoise(in: image, chromaRadius: 2.0, lumaRadius: 0.8, shadowBias: false)
    }

    /// 암부 컬러 노이즈를 더 강하게 정리하고, 암부 휘도 노이즈도 약하게 평활한다.
    static func reduceShadowChroma(in image: CIImage) -> CIImage {
        let base = reduceColorNoise(in: image, chromaRadius: 2.8, lumaRadius: 0, shadowBias: false)
        let shadows = reduceColorNoise(in: base, chromaRadius: 5.2, lumaRadius: 1.2, shadowBias: true)
        return reduceMidtoneChroma(in: neutralizeLowSaturationMagenta(in: shadows))
    }

    // MARK: 구현

    /// chroma(색차)는 강하게, luma(휘도)는 약하게 블러한다. shadowBias면 암부에 한정해 적용.
    private static func reduceColorNoise(in image: CIImage,
                                         chromaRadius: Double,
                                         lumaRadius: Double,
                                         shadowBias: Bool) -> CIImage {
        let extent = image.extent
        let luma = luminance(of: image)

        // 색차 = 원본 - luma. CIColorMatrix로 직접 만들고 0.5 bias로 음수를 보존한다.
        // chroma_biased = (R-Y, G-Y, B-Y) + 0.5
        let chroma = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1 - 0.2126, y: -0.7152, z: -0.0722, w: 0),
            "inputGVector": CIVector(x: -0.2126, y: 1 - 0.7152, z: -0.0722, w: 0),
            "inputBVector": CIVector(x: -0.2126, y: -0.7152, z: 1 - 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0.5, y: 0.5, z: 0.5, w: 0),
        ]).cropped(to: extent)
        // chroma를 강하게 블러(색 얼룩 평활).
        let blurredChroma = chroma.applyingFilter("CIGaussianBlur", parameters: [
            "inputRadius": chromaRadius,
        ]).cropped(to: extent)
        // luma는 약하게만 블러(휘도 노이즈 살짝 줄이되 엣지 디테일 유지).
        let smoothedLuma = lumaRadius > 1e-3
            ? luma.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": lumaRadius]).cropped(to: extent)
            : luma
        // 재결합: smoothedLuma + (blurredChroma - 0.5)
        let denoised = CIFilter(name: "CIAdditionCompositing", parameters: [
            kCIInputImageKey: smoothedLuma,
            kCIInputBackgroundImageKey: blurredChroma.applyingFilter("CIColorMatrix", parameters: [
                "inputBiasVector": CIVector(x: -0.5, y: -0.5, z: -0.5, w: 0),
            ]),
        ])?.outputImage?.cropped(to: extent) ?? image

        guard shadowBias else { return denoised }

        // 암부 마스크: luma < 0.30 영역에만 적용(밝은 영역은 원본 유지).
        let scaledDeepChroma = CIFilter(name: "CIAdditionCompositing", parameters: [
            kCIInputImageKey: smoothedLuma,
            kCIInputBackgroundImageKey: blurredChroma.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.34, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.34, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.34, w: 0),
                "inputBiasVector": CIVector(x: -0.17, y: -0.17, z: -0.17, w: 0),
            ]),
        ])?.outputImage?.cropped(to: extent) ?? denoised
        let deepShadowMask = mask(from: luma, limit: 0.18)
        let neutralizedDeepShadow = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: scaledDeepChroma,
            kCIInputBackgroundImageKey: denoised,
            "inputMaskImage": deepShadowMask,
        ])?.outputImage?.cropped(to: extent) ?? denoised
        let shadowMask = mask(from: luma, limit: 0.32)
        return CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: neutralizedDeepShadow,
            kCIInputBackgroundImageKey: image,
            "inputMaskImage": shadowMask,
        ])?.outputImage?.cropped(to: extent) ?? neutralizedDeepShadow
    }

    private static func neutralizeLowSaturationMagenta(in image: CIImage) -> CIImage {
        let extent = image.extent
        let blurred = image.applyingFilter("CIGaussianBlur", parameters: [
            "inputRadius": 2.4,
        ]).cropped(to: extent)
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "scannerLowSatChroma") else { return image }
        return kernel.apply(extent: extent, arguments: [image, blurred])?.cropped(to: extent) ?? image
    }

    private static func reduceMidtoneChroma(in image: CIImage) -> CIImage {
        let extent = image.extent
        let luma = luminance(of: image)
        let chroma = chromaImage(from: image).cropped(to: extent)
        let guidedChroma = CIFilter(name: "CIGuidedFilter", parameters: [
            kCIInputImageKey: chroma,
            "inputGuideImage": luma,
            "inputRadius": 7.0,
            "inputEpsilon": 0.0018,
        ])?.outputImage?.cropped(to: extent)
            ?? chroma.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 5.4]).cropped(to: extent)
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "scannerMidtoneChroma") else { return image }
        return kernel.apply(extent: extent, arguments: [image, guidedChroma])?.cropped(to: extent) ?? image
    }

    private static func luminance(of image: CIImage) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: image.extent)
    }

    private static func chromaImage(from image: CIImage) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1 - 0.2126, y: -0.7152, z: -0.0722, w: 0),
            "inputGVector": CIVector(x: -0.2126, y: 1 - 0.7152, z: -0.0722, w: 0),
            "inputBVector": CIVector(x: -0.2126, y: -0.7152, z: 1 - 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0.5, y: 0.5, z: 0.5, w: 0),
        ]).cropped(to: image.extent)
    }

    /// luma < limit 영역을 1로, 그 위는 0으로 가는 부드러운 암부 마스크.
    private static func mask(from image: CIImage, limit: Double) -> CIImage {
        let scale = -1.0 / limit
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ]).cropped(to: image.extent)
    }
}
