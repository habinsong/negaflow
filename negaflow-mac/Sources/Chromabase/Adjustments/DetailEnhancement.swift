import CoreImage

// MARK: - DetailEnhancement
//
// 선명도(Sharpness)와 부분 대비(Clarity). 예전 구현의 결함(2026-10-15 검토):
//  - 반경이 픽셀 고정이라 화면 프록시(최대 3600px)와 내보내기 원본(5000~9000px)에서 같은 사진에
//    1.4~3 배 다른 크기로 걸렸다 — 화면에서 본 것과 파일이 달랐다.
//  - linear RGB 채널별 언샤프라 밝은 쪽 헤일로가 크고 채널마다 따로 날카로워져 색 테두리가 생겼다.
//  - 부분 대비 − 는 흐린 사본과 섞는 것이라 국소 대비가 아니라 사진 전체가 뿌옇게 번졌다.
// 지금은 둘 다 감마 휘도에서 디테일을 다루고 휘도 비율로 RGB 에 싣는다(색상·채도 불변). 공간
// 척도는 작업 영상의 긴 변에 비례한다(기준 6000px ≈ 24MP 급 스캔).
public enum DetailEnhancement {
    static let referenceLongSide = 6_000.0

    /// 선명도 가우시안 반경(px). 기준 해상도에서 0.7~1.2px, 아무리 작아도 0.5px.
    static func sharpenRadius(sharpness: Double, extent: CGRect) -> Double {
        max(0.5, (0.7 + 0.5 * sharpness) * max(extent.width, extent.height) / referenceLongSide)
    }
    static func sharpenAmount(_ sharpness: Double) -> Double { 1.6 * sharpness }
    /// 이보다 작은 감마 진폭(≈1.5/255)은 노이즈·그레인 바닥으로 보고 키우지 않는다.
    static let sharpenThreshold = 0.006
    static let sharpenHalo = 0.10

    /// 부분 대비 베이스의 창(가우시안 표준편차) = 긴 변의 0.6%(기준 해상도에서 36px ≈ 상자 반경 62px).
    /// 창은 가우시안 가중이다 — `CIBoxBlur` 의 inputRadius 는 실측상 창 **너비**(반경 8 → 7탭, 2 이하는
    /// 항등)라 반경 의미로 쓸 수 없다(2026-10-15 임펄스 응답 실측).
    static let claritySigmaFraction = 0.006
    /// 감마 휘도 분산 문턱 — 표준편차 0.1 을 넘는 변화는 경계로 보고 베이스에 남긴다. 경계 근처에
    /// 남는 디테일 잔여(가이디드 필터 헤일로)는 커널이 계수 a(경계 지표)로 한 번 더 걷어 낸다.
    static let clarityEpsilon = 0.01
    static let clarityHalo = 0.18
    static func clarityAmount(_ clarity: Double) -> Double { clarity >= 0 ? 0.9 * clarity : 0.8 * clarity }

    public static func sharpen(_ image: CIImage, sharpness: Double) -> CIImage {
        let extent = image.extent
        guard sharpness > 1e-3,
              let lumaKernel = ChromabaseMetalKernels.colorKernel(named: "detailGammaLuma"),
              let kernel = ChromabaseMetalKernels.colorKernel(named: "detailSharpen"),
              let guide = lumaKernel.apply(extent: extent, arguments: [image]) else { return image }
        let blurred = guide.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                "inputRadius": sharpenRadius(sharpness: sharpness, extent: extent),
            ])
            .cropped(to: extent)
        return kernel.apply(extent: extent, arguments: [
            image, blurred, sharpenAmount(sharpness), sharpenThreshold, sharpenHalo,
        ])?.cropped(to: extent) ?? image
    }

    /// 경계 보존 베이스는 자기 안내(self-guided) 가이디드 필터다. 계수는 창 표준편차의 1/3 로 줄인
    /// 해상도에서 구해 올린다(He & Sun 2015 고속 가이디드 필터) — 계수는 창 평균이라 원래 매끈하고,
    /// 화면 프록시에서도 큰 창의 흐림을 원본 해상도로 돌리지 않는다.
    public static func localContrast(_ image: CIImage, clarity: Double) -> CIImage {
        let extent = image.extent
        guard abs(clarity) > 1e-3,
              let lumaKernel = ChromabaseMetalKernels.colorKernel(named: "detailGammaLuma"),
              let product = ChromabaseMetalKernels.colorKernel(named: "gfProduct"),
              let coefficientA = ChromabaseMetalKernels.colorKernel(named: "gfCoeffA"),
              let coefficientB = ChromabaseMetalKernels.colorKernel(named: "gfCoeffB"),
              let kernel = ChromabaseMetalKernels.colorKernel(named: "detailLocalContrast"),
              let guide = lumaKernel.apply(extent: extent, arguments: [image]) else { return image }
        let sigma = max(1.5, claritySigmaFraction * max(extent.width, extent.height))
        let factor = max(1.0, (sigma / 3).rounded(.down))
        let lowGuide = factor > 1
            ? guide.clampedToExtent()
                .applyingFilter("CILanczosScaleTransform", parameters: [
                    "inputScale": 1 / factor, "inputAspectRatio": 1,
                ])
                .cropped(to: CGRect(x: extent.minX / factor, y: extent.minY / factor,
                                    width: extent.width / factor, height: extent.height / factor).integral)
            : guide
        let low = lowGuide.extent
        func box(_ input: CIImage) -> CIImage {
            input.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": sigma / factor])
                .cropped(to: low)
        }
        guard let squared = product.apply(extent: low, arguments: [lowGuide, lowGuide]) else { return image }
        let meanGuide = box(lowGuide)
        let meanSquared = box(squared)
        guard let a = coefficientA.apply(extent: low, arguments: [
                  meanSquared, meanSquared, meanGuide, meanGuide, clarityEpsilon,
              ]),
              let b = coefficientB.apply(extent: low, arguments: [a, meanGuide, meanGuide]) else { return image }
        func upsampled(_ coefficient: CIImage) -> CIImage {
            guard factor > 1 else { return coefficient }
            return coefficient.clampedToExtent().samplingLinear()
                .transformed(by: CGAffineTransform(scaleX: factor, y: factor))
                .cropped(to: extent)
        }
        return kernel.apply(extent: extent, arguments: [
            image, upsampled(box(a)), upsampled(box(b)), clarityAmount(clarity), clarityHalo,
        ])?.cropped(to: extent) ?? image
    }
}
