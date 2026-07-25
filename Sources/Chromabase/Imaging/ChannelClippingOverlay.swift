import CoreImage

/// 현상 결과의 실제 RGB 채널 경계(0 이하 / 1 이상)를 표시하는 프리뷰 전용 오버레이입니다.
/// 투명 레이어만 반환하므로 원본·현상 결과·export 픽셀은 수정하지 않습니다.
public enum ChannelClippingOverlay {
    public static let opacity: Float = 0.62
    public static let shadowColor = SIMD3<Float>(0.055, 0.24, 0.82)
    public static let highlightColor = SIMD3<Float>(0.90, 0.07, 0.055)
    public static let mixedColor = SIMD3<Float>(0.64, 0.10, 0.70)

    public static func makeOverlay(for image: CIImage) -> CIImage? {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isNull, !extent.isEmpty,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "channelClippingOverlay")
        else { return nil }
        return kernel.apply(extent: extent, arguments: [image])?.cropped(to: extent)
    }
}
