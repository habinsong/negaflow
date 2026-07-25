import CoreImage

// MARK: - OutputDither (HIGHLIGHT_TONE_REDESIGN.md §4.6)
//
// 8bit 양자화 banding 완화 dithering. **출력(8bit createCGImage) 직전에만** 적용한다.
// develop 파이프라인이 아니라 출력 계층에서만 적용하므로 develop 결과는 dithering 없이 불변이다
// (크롭 불변성 보존 — 크롭은 공간 범위만 바꾸고 색을 재계산하지 않는다).
//
// 원리(웹 검증): banding 은 8bit 양자화로 매끄러운 그라디언트의 인접 픽셀이 같은 스텝으로 몰릴 때
// 생긴다. 양자화가 일어나는 색공간(sRGB)에서 ±0.5/255(1스텝 이내) 노이즈를 더하면 경계 픽셀이
// 인접 스텝으로 확률적으로 분산돼 band 가 stipple 로 보이고, 디테일/평균 톤은 보존된다.
// 16bit 출력엔 ±0.5/255 ≈ ±128/65535 로 사실상 무해하므로 분기 없이 공통 적용해도 된다.
public enum OutputDither {
    public static func apply(to image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "ditherAdd"),
              let rnd = CIFilter(name: "CIRandomGenerator")?.outputImage?.cropped(to: extent)
        else { return image }
        // 양자화가 일어나는 sRGB 공간으로 인코딩 → ±0.5/255 노이즈 → 다시 linear 로 복원.
        let srgb = image.applyingFilter("CILinearToSRGBToneCurve").cropped(to: extent)
        let dithered = kernel.apply(extent: extent, arguments: [srgb, rnd])?.cropped(to: extent) ?? srgb
        return dithered.applyingFilter("CISRGBToneCurveToLinear").cropped(to: extent)
    }
}
