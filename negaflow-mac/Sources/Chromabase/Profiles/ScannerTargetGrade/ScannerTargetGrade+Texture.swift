import CoreImage

extension ScannerTargetGrade {
    // MARK: HS 장치 질감(샤픈)
    //
    // 이 계열 스캐너는 기본 샤프닝을 끌 수 없어 그레인이 또렷하게 보인다(랩 서술 다수). 반경은
    // 실기 출력 해상도 기준이다: HS-1800 의 35mm 출력은 3089×2048(실기 412컷 실측)이고, 그
    // 해상도에서 σ 0.9px 이다. 다른 해상도에서는 같은 필름 면적에 같은 반경이 걸리도록 긴 변
    // 비율로 키우거나 줄인다 — 프리뷰·원본·내보내기에서 질감이 같다. 강도는 실측이 없어
    // 보수적인 값이며 그레인은 합성하지 않는다.
    //
    // 구현: noritsuTexture 커널(감마 도메인 luminance USM). CISharpenLuminance 는 linear
    // 작업공간에서 동작해 암부 0 크러시·명부 unit range 이탈을 만들었다. 커널은 undershoot
    // 플로어·유닛 상한·extended 통과·hue 보존 가드를 내장한다.

    /// 실기 출력 해상도(35mm 긴 변)에서의 가우시안 저역 시그마(px).
    static let noritsuSharpenRadius = 0.9
    /// σ 를 정한 실기 출력의 긴 변(px).
    static let noritsuReferenceLongEdge = 3089.0
    /// 감마 도메인 USM 게인.
    static let noritsuSharpenAmount = 0.6

    static func noritsuSharpenSigma(for extent: CGRect) -> Double {
        noritsuSharpenRadius * Double(max(extent.width, extent.height)) / noritsuReferenceLongEdge
    }

    static func applyDocumentedTexture(to image: CIImage, target: DevelopTarget) -> CIImage {
        guard target == .noritsu,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "noritsuTexture") else {
            return image
        }
        let extent = image.extent
        let sigma = noritsuSharpenSigma(for: extent)
        // 너무 작은 프리뷰에서는 저역이 원본과 같아져 효과가 0 이 된다 — 그 경우 건너뛴다.
        guard sigma >= 0.05 else { return image }
        let blurred = image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: sigma,
            ])
            .cropped(to: extent)
        return kernel.apply(
            extent: extent,
            arguments: [image, blurred, Float(noritsuSharpenAmount)]
        )?.cropped(to: extent) ?? image
    }
}
