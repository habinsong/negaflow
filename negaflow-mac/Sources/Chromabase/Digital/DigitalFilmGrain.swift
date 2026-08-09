import CoreImage
import CoreGraphics

// MARK: - DigitalFilmGrain (디지털 소스 전용)
//
// 디지털 노이즈와 필름 그레인은 반대로 분포한다. 디지털 노이즈는 약한 신호를 증폭하는
// 암부에서 가장 크고, 필름 그레인은 은입자가 실제로 뭉치는 중간 밀도에서 가장 눈에 띈다.
// 그래서 균일한 노이즈 오버레이는 필름이 아니라 고감도 디지털처럼 읽힌다.
//
// 두 가지 밀도 의존을 모두 반영한다:
//   • 물리 granularity 는 밀도의 제곱근을 따라 커진다(Selwyn 의 관계).
//   • 지각되는 거칠기는 밀도 1.0 부근에서 최대이고 양 끝에서 떨어진다 — 물리 곡선과
//     지각 곡선이 어긋난다는 것은 사진과학에서 반복 확인된 사실이다.
//
// 노이즈는 밀도 도메인에서 더한다. 필름 그레인은 밝기에 더해지는 것이 아니라 밀도를 흔드는
// 것이므로, 결과적으로 반사율에는 곱셈으로 실린다.
//
// 컬러 필름의 그레인은 층마다 따로 뭉치므로 무채색이 아니다. chromaRatio 로 채널 독립 성분을
// 섞는다.
public enum DigitalFilmGrain {

    public static func apply(
        to image: CIImage,
        physics: DigitalFilmPhysics,
        strength: Double
    ) -> CIImage {
        apply(
            to: image,
            amplitude: physics.grain.amplitude,
            chromaRatio: physics.grain.chromaRatio,
            size: physics.grain.size,
            strength: strength
        )
    }

    /// 은염 흑백 그레인도 같은 밀도 의존을 따른다. 다른 것은 층이 하나뿐이라 채널이 함께
    /// 흔들린다는 점(chromaRatio = 0)이므로, 계수만 받는 진입점을 따로 연다.
    public static func apply(
        to image: CIImage,
        amplitude: Double,
        chromaRatio: Double,
        size: Double,
        strength: Double
    ) -> CIImage {
        let amount = min(max(strength, 0), 1)
        guard amount > 1e-3,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "digitalFilmGrainDensity"),
              let noise = noiseField(size: size, extent: image.extent) else {
            return image
        }
        let extent = image.extent
        return kernel.apply(
            extent: extent,
            arguments: [
                image, noise,
                CIVector(x: CGFloat(amplitude * amount),
                         y: CGFloat(chromaRatio), z: 0, w: 0),
            ]
        )?.cropped(to: extent) ?? image
    }

    /// 입자 크기를 반영한 난수장. CIRandomGenerator 는 픽셀 단위 백색 잡음이라 그대로 쓰면
    /// 스캔 해상도에 따라 입자가 달라진다. 크기만큼 축소했다 되키워 입자를 만든다.
    private static func noiseField(size rawSize: Double, extent: CGRect) -> CIImage? {
        guard let base = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        let size = max(1.0, rawSize)
        guard size > 1.01 else { return base.cropped(to: extent) }
        return base
            .transformed(by: CGAffineTransform(scaleX: size, y: size))
            .cropped(to: extent)
    }
}
