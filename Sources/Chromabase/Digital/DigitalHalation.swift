import CoreImage
import CoreGraphics

// MARK: - DigitalHalation (디지털 소스 전용)
//
// 필름 스캔에는 이미 들어 있는 광학 현상을 디지털에서는 계산으로 만든다. LUT 는 이웃 픽셀을
// 볼 수 없으므로 색 변환만으로는 절대 나오지 않는 부분이다.
//
// 물리:
//   • 산란(scatter) — 에멀전 내부에서 퍼지는 빛. 반경이 작고 전 채널에 걸린다.
//   • 헐레이션(halation) — 유제를 통과한 빛이 베이스에서 반사되어 되돌아오는 성분. 반경이
//     크고, 되돌아온 빛은 층을 역순으로 때리므로 가장 깊은 적색 층이 먼저 받는다. 그래서
//     헐레이션은 붉거나 주황빛이다(청색은 황색 필터층이 거의 막는다).
//   • 반사는 한 번으로 끝나지 않는다. k 번째 바운스의 퍼짐은 대략 √k 로 커지므로, 반경이
//     √k 로 늘어나는 항을 감쇠 가중해 더하면 단일 가우시안보다 실제의 무거운 꼬리에 가깝다.
//
// 밀도가 만들어지기 **전**, 선형 광 도메인에서 적용해야 한다. 결과 이미지에 덧칠하면
// 명부가 그냥 하얗게 뜬다. 총 광량이 늘지 않도록 원본에서 덜어내 재분배한다.
public enum DigitalHalation {

    /// 반경은 픽셀이 아니라 이미지 크기에 대한 비율로 정의한다 — 해상도가 달라도 같은 그림이
    /// 나와야 하기 때문이다(필름에서 헐레이션 크기는 유제 두께가 정하지 스캔 dpi 가 정하지 않는다).
    public static func apply(
        to image: CIImage,
        physics: DigitalFilmPhysics,
        strength: Double
    ) -> CIImage {
        let amount = min(max(strength, 0), 1)
        guard amount > 1e-3,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "digitalHalation") else {
            return image
        }
        let extent = image.extent
        let reference = min(extent.width, extent.height)
        guard reference > 8 else { return image }

        let farRadius = max(1.0, Double(reference) * physics.halationRadiusRatio)
        let nearRadius = max(0.6, farRadius * 0.28)          // 에멀전 내부 산란은 훨씬 좁다
        let wideRadius = farRadius * 1.414                    // 2차 바운스 √2

        let near = blur(image, radius: nearRadius, extent: extent)
        let far = blur(image, radius: farRadius, extent: extent)
        let wide = blur(image, radius: wideRadius, extent: extent)

        let scatter = physics.scatterStrength * amount
        let halation = physics.halationStrength * amount
        return kernel.apply(
            extent: extent,
            arguments: [image, near, far, wide, vector(scatter), vector(halation)]
        )?.cropped(to: extent) ?? image
    }

    private static func vector(_ v: SIMD3<Double>) -> CIVector {
        CIVector(x: CGFloat(v.x), y: CGFloat(v.y), z: CGFloat(v.z), w: 0)
    }

    /// 가장자리에서 흐림이 안쪽으로 어두운 테를 만들지 않도록 clamp 한 뒤 흐리고 되돌린다.
    private static func blur(_ image: CIImage, radius: Double, extent: CGRect) -> CIImage {
        image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius])
            .cropped(to: extent)
    }
}
