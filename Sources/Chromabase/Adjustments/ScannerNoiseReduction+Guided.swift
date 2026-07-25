import CoreImage

extension ScannerNoiseReduction {
    static func guidedChroma(
        _ chroma: CIImage,
        guide luma: CIImage,
        radius: Double,
        epsilon: Double,
        fallbackRadius: Double
    ) -> CIImage {
        let extent = chroma.extent
        func fallback() -> CIImage {
            chroma.applyingFilter(
                "CIGaussianBlur",
                parameters: ["inputRadius": fallbackRadius]
            ).cropped(to: extent)
        }
        guard
            let productKernel = ChromabaseMetalKernels.colorKernel(named: "gfProduct"),
            let coefficientAKernel = ChromabaseMetalKernels.colorKernel(named: "gfCoeffA"),
            let coefficientBKernel = ChromabaseMetalKernels.colorKernel(named: "gfCoeffB"),
            let applyKernel = ChromabaseMetalKernels.colorKernel(named: "gfApply")
        else { return fallback() }
        func box(_ image: CIImage) -> CIImage {
            image.clampedToExtent()
                .applyingFilter("CIBoxBlur", parameters: ["inputRadius": radius])
                .cropped(to: extent)
        }
        guard
            let guideProduct = productKernel.apply(extent: extent, arguments: [luma, luma]),
            let crossProduct = productKernel.apply(extent: extent, arguments: [luma, chroma])
        else { return fallback() }
        let meanGuide = box(luma)
        let meanChroma = box(chroma)
        guard
            let coefficientA = coefficientAKernel.apply(
                extent: extent,
                arguments: [box(crossProduct), box(guideProduct), meanGuide, meanChroma, epsilon]
            ),
            let coefficientB = coefficientBKernel.apply(
                extent: extent,
                arguments: [coefficientA, meanGuide, meanChroma]
            ),
            let output = applyKernel.apply(
                extent: extent,
                arguments: [box(coefficientA), box(coefficientB), luma, chroma]
            )
        else { return fallback() }
        return output.cropped(to: extent)
    }

    static func luminance(of image: CIImage) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: image.extent)
    }

    static func chromaImage(from image: CIImage) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1 - 0.2126, y: -0.7152, z: -0.0722, w: 0),
            "inputGVector": CIVector(x: -0.2126, y: 1 - 0.7152, z: -0.0722, w: 0),
            "inputBVector": CIVector(x: -0.2126, y: -0.7152, z: 1 - 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0.5, y: 0.5, z: 0.5, w: 0),
        ]).cropped(to: image.extent)
    }

    static func mask(from image: CIImage, limit: Double) -> CIImage {
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
