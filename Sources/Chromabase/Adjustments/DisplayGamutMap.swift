import CoreImage

// MARK: - DisplayGamutMap
//
// 작업/내보내기 파이프라인은 확장범위(음수·1 초과) 값을 보존한다 — MAIN 플랫 마스터의 명부
// 관용도와 유채색을 비가역적으로 잃지 않기 위해서다(ChromabaseEngine+PostPipeline 참고).
// 대신 디스플레이/썸네일 8bit 출력 경계에서만, per-channel 하드 클립 대신 luma 보존 hue-safe
// soft-clip(gamutSoftClip 커널 = toneSafeUnitRGB)으로 out-of-gamut 값을 [0,1] 안으로 접는다.
//
// 반드시 soft-proof **이전**에 적용해야 한다: soft-proof(종이+블랙잉크)는 `input*scale + black`
// 형태의 선형 재매핑이라 [0,1] 입력만 종이 화이트(<1)로 압축한다. 확장 입력을 그대로 넣으면
// 확장값이 유지돼 8bit createCGImage 에서 하드 클립(전부 흰색)되고, 프루프가 원본과 구별되지
// 않는다. in-gamut([0,1]) 픽셀에 대해서는 toneSafeUnitRGB 가 항등이므로 일반 이미지는 불변이다.
public enum DisplayGamutMap {
    public static func apply(to image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "gamutSoftClip")
        else { return image }
        return kernel.apply(extent: extent, arguments: [image])?.cropped(to: extent) ?? image
    }
}
