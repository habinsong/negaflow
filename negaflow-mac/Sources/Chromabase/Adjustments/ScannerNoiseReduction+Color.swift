import CoreImage

extension ScannerNoiseReduction {
    static func reduceColorNoise(
        in image: CIImage,
        chromaRadius: Double,
        lumaRadius: Double,
        shadowBias: Bool
    ) -> CIImage {
        let extent = image.extent
        let luma = luminance(of: image)
        let chroma = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1 - 0.2126, y: -0.7152, z: -0.0722, w: 0),
            "inputGVector": CIVector(x: -0.2126, y: 1 - 0.7152, z: -0.0722, w: 0),
            "inputBVector": CIVector(x: -0.2126, y: -0.7152, z: 1 - 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0.5, y: 0.5, z: 0.5, w: 0),
        ]).cropped(to: extent)
        let blurredChroma = chroma.applyingFilter("CIGaussianBlur", parameters: [
            "inputRadius": chromaRadius,
        ]).cropped(to: extent)
        let smoothedLuma = lumaRadius > 1e-3
            ? luma.applyingFilter(
                "CIGaussianBlur",
                parameters: ["inputRadius": lumaRadius]
            ).cropped(to: extent)
            : luma
        let denoised = CIFilter(name: "CILinearDodgeBlendMode", parameters: [
            kCIInputImageKey: smoothedLuma,
            kCIInputBackgroundImageKey: blurredChroma.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputBiasVector": CIVector(x: -0.5, y: -0.5, z: -0.5, w: 0),
                ]
            ),
        ])?.outputImage?.cropped(to: extent) ?? image
        guard shadowBias else { return denoised }

        let scaledDeepChroma = CIFilter(name: "CILinearDodgeBlendMode", parameters: [
            kCIInputImageKey: smoothedLuma,
            kCIInputBackgroundImageKey: blurredChroma.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.34, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.34, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.34, w: 0),
                "inputBiasVector": CIVector(x: -0.17, y: -0.17, z: -0.17, w: 0),
            ]),
        ])?.outputImage?.cropped(to: extent) ?? denoised
        let neutralizedDeepShadow = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: scaledDeepChroma,
            kCIInputBackgroundImageKey: denoised,
            "inputMaskImage": mask(from: luma, limit: 0.18),
        ])?.outputImage?.cropped(to: extent) ?? denoised
        return CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: neutralizedDeepShadow,
            kCIInputBackgroundImageKey: image,
            "inputMaskImage": mask(from: luma, limit: 0.32),
        ])?.outputImage?.cropped(to: extent) ?? neutralizedDeepShadow
    }

    static func neutralizeLowSaturationMagenta(in image: CIImage) -> CIImage {
        let extent = image.extent
        let blurred = image.applyingFilter("CIGaussianBlur", parameters: [
            "inputRadius": 2.4,
        ]).cropped(to: extent)
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "scannerLowSatChroma") else {
            return image
        }
        return kernel.apply(
            extent: extent,
            arguments: [image, blurred]
        )?.cropped(to: extent) ?? image
    }
}
