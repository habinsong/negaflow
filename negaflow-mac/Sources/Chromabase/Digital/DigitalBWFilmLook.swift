import CoreImage
import CoreGraphics

// MARK: - DigitalBWFilmLook (디지털 소스 전용 흑백 필름 룩)
//
// 컬러 경로(`DigitalFilmLook`)와 같은 뼈대를 쓴다. 순서가 곧 물리이기 때문이다.
//
//   헐레이션 → 유제 응답 → acutance → 그레인
//
// 헐레이션은 유제가 밀도를 만들기 **전**의 광 번짐이므로 응답보다 먼저 와야 하고, 그레인은
// 밀도가 정해진 **뒤**에 그 밀도를 흔드는 것이므로 맨 뒤에 와야 한다. 순서를 바꾸면 번짐이
// 그냥 덧칠한 빛으로 보이고, 그레인은 밝기와 무관한 균일 노이즈가 된다.
//
// 컬러와 다른 것은 딱 세 가지다.
//   • 되돌아온 빛이 층으로 갈리지 않으므로 헐레이션에 색이 없다
//   • 색이 사라지는 자리가 여기다 — 분광 가중치로 그레이를 합성한다
//   • 은염은 층이 하나라 그레인이 채널을 함께 흔든다(chroma 성분 0)
//
// **필름 스캔 경로는 이 파일을 지나지 않는다.** 스캔본은 이미 그 유제를 통과했다.
public enum DigitalBWFilmLook {

    public static func apply(
        to image: CIImage,
        emulation: FilmEmulation,
        intensity: Double,
        grainOverride: Double,
        halationOverride: Double
    ) -> CIImage {
        guard let profile = BWFilmProfile.of(emulation) else { return image }
        let strength = min(max(intensity, 0), 1)
        guard strength > 1e-3 else { return image }

        let extent = image.extent
        var img = image

        // 흑백 유제도 같은 광학을 겪는다. 안티할레이션이 약한 투명 베이스(Rollei 계열)와
        // 백킹이 있는 유제의 차이가 여기서 갈린다.
        img = DigitalHalation.apply(
            to: img,
            scatter: SIMD3(repeating: profile.scatterStrength),
            halation: SIMD3(repeating: profile.halationStrength),
            radiusRatio: profile.halationRadiusRatio,
            strength: resolve(override: halationOverride, default: strength)
        )

        img = emulsionResponse(img, profile: profile, intensity: strength, extent: extent)

        // MTF acutance. 컬러 경로와 같은 근사이고, 계수만 흑백 데이터시트에서 온다.
        let acutance = profile.acutance
        if acutance.intensity > 1e-3 {
            img = img.applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius": acutance.radius,
                "inputIntensity": acutance.intensity * strength,
            ]).cropped(to: extent)
        }

        // 은염 그레인. 컬러와 같은 밀도 의존 커널을 쓰되 chroma 성분을 0 으로 둔다 —
        // 층이 하나뿐인 유제에서 채널이 따로 흔들릴 이유가 없다.
        img = DigitalFilmGrain.apply(
            to: img,
            amplitude: profile.grainAmplitude,
            chromaRatio: 0,
            size: profile.grainSize,
            strength: resolve(override: grainOverride, default: strength)
        )

        return img.cropped(to: extent)
    }

    /// 분광 합성 + 특성곡선. 색이 사라지는 지점이다.
    private static func emulsionResponse(
        _ image: CIImage,
        profile: BWFilmProfile,
        intensity: Double,
        extent: CGRect
    ) -> CIImage {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "digitalBWFilm") else {
            return image
        }
        let r = BWFilmResponse(profile: profile, intensity: intensity)
        return kernel.apply(
            extent: extent,
            arguments: [
                image,
                CIVector(x: CGFloat(r.weights.x), y: CGFloat(r.weights.y),
                         z: CGFloat(r.weights.z), w: CGFloat(intensity)),
                CIVector(x: CGFloat(r.contrast), y: CGFloat(r.toe),
                         z: CGFloat(r.shoulder), w: CGFloat(r.deepen)),
                CIVector(x: CGFloat(r.black), y: CGFloat(r.white), z: 0, w: 0),
            ]
        )?.cropped(to: extent) ?? image
    }

    /// Texture 슬라이더와 유제 물성의 관계는 컬러 경로와 같다 — 0 이면 유제가 정한 기본
    /// 기여를 쓰고, 올려 두었다면 그 값이 강도가 된다.
    private static func resolve(override: Double, default fallback: Double) -> Double {
        override > 1e-3 ? min(max(override, 0), 1) : fallback
    }
}
