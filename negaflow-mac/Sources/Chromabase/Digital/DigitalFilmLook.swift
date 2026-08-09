import CoreImage
import CoreGraphics

// MARK: - DigitalFilmLook (디지털 소스 전용 필름 룩)
//
// 좌측 Film 탭의 입력은 RAW 센서값이나 필름 노출이 아니라, 사용자의 색·톤 보정까지 끝난
// positive 이미지다. 이 값을 다시 장면 노출로 추정한 뒤 네거티브/슬라이드 현상에 통과시키면
// 같은 톤을 두 번 현상하게 된다. 실제 사진에서 네거티브 룩의 암부가 0.15 부근까지 뜨고
// p1...p99 범위가 약 20% 줄어든 원인이 그 중복 변환이었다.
//
// 따라서 디지털 전용 경로는 positive 도메인용 필름 LUT로 톤·색을 한 번만 변환하고,
// 디지털 원본에 없는 헐레이션과 그레인만 별도로 보탠다. LUT는 스톡별 특성곡선과 색 응답을
// 함께 담고 있으며 강도 블렌드도 자체적으로 처리한다.
//
// **필름 스캔은 이 경로를 지나지 않는다.** 필름 룩은 디지털 소스 전용이다 — 스캔본에는
// 이미 유제를 통과한 신호가 들어 있어서, 그 위에 또 유제 응답을 얹으면 두 번 현상이 된다.
public enum DigitalFilmLook {

    /// 이 조합에서 룩이 실제로 적용되는가. 흑백 프로세스에는 흑백 유제만, 컬러 프로세스에는
    /// 컬러 유제만 걸린다. 프로세스를 바꿔도 선택은 보존되므로(사용자가 되돌리면 살아 돌아온다)
    /// 목록에 없는 필름이 파라미터에 남아 있을 수 있고, 그때 엉뚱한 룩이 걸리면 안 된다.
    public static func appliesLook(emulation: FilmEmulation, monochrome: Bool) -> Bool {
        guard let kind = emulation.kind else { return false }
        switch kind {
        case .bwNegative, .bwReversal: return monochrome
        case .slide, .negative, .motionPicture: return !monochrome
        }
    }

    public static func apply(
        to image: CIImage,
        emulation: FilmEmulation,
        intensity: Double,
        grainOverride: Double,
        halationOverride: Double,
        monochrome: Bool
    ) -> CIImage {
        guard appliesLook(emulation: emulation, monochrome: monochrome) else { return image }
        let strength = min(max(intensity, 0), 1)
        guard strength > 1e-3 else { return image }

        // 흑백 유제는 축이 달라 자료형도 경로도 따로 간다.
        if emulation.kind == .bwNegative || emulation.kind == .bwReversal {
            return DigitalBWFilmLook.apply(
                to: image,
                emulation: emulation,
                intensity: strength,
                grainOverride: grainOverride,
                halationOverride: halationOverride
            )
        }

        guard let physics = DigitalFilmPhysics.of(emulation) else {
            return image
        }
        let extent = image.extent
        var img = image

        // 헐레이션은 필름 응답 전의 광 번짐이므로 LUT보다 먼저 적용한다.
        img = DigitalHalation.apply(
            to: img,
            physics: physics,
            strength: resolve(override: halationOverride, default: strength)
        )

        img = FilmEmulationStage.apply(to: img, emulation: emulation, intensity: strength)
        // LUT가 이미 스톡 색을 포함하므로 보조 프리셋은 절반만 더해 중립축 과염색을 막는다.
        img = DigitalFilmColorPresetStage.apply(to: img, emulation: emulation, intensity: strength * 0.5)

        // 그레인은 필름 물성이라 필름을 고르면 따라온다.
        img = DigitalFilmGrain.apply(
            to: img,
            physics: physics,
            strength: resolve(override: grainOverride, default: strength)
        )

        return img.cropped(to: extent)
    }

    /// Texture 슬라이더와 필름 물성의 관계. 슬라이더가 0 이면 "안 만졌다"는 뜻이라 유제가
    /// 정한 기본 기여를 쓰고, 올려 두었다면 그 값이 강도가 된다. 두 값을 더하지 않는 이유는
    /// 이 조합에서 후처리 텍스처 단계의 같은 축을 비워 두기 때문이다 — 더하면 이중이 된다.
    private static func resolve(override: Double, default fallback: Double) -> Double {
        override > 1e-3 ? min(max(override, 0), 1) : fallback
    }

}

// MARK: - 스톡 색 시그니처

/// 필름 스톡 고유의 색만 적용한다. 대비/계조는 가상 현상이 이미 만들었으므로 특성곡선의
/// 대비 성분은 쓰지 않고, 색 매트릭스·밝기대별 크로스오버·inter-image 채도만 가져온다.
/// 계수는 기존 필름 프로파일에서 **읽기만** 한다 — 필름 스캔 경로가 쓰는 값과 같은 출처다.
enum DigitalFilmColor {

    static func apply(to image: CIImage, emulation: FilmEmulation) -> CIImage {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "digitalFilmColor") else {
            return image
        }
        let extent = image.extent
        let p = FilmEmulationProfile.of(emulation)
        let hue = p.iieHue.count == 6 ? p.iieHue : [0, 0, 0, 0, 0, 0]
        return kernel.apply(
            extent: extent,
            arguments: [
                image,
                row(p.mR, lift: p.toneR.lift),
                row(p.mG, lift: p.toneG.lift),
                row(p.mB, lift: p.toneB.lift),
                vector(p.shadowTint),
                vector(p.highlightTint),
                CIVector(x: CGFloat(hue[0]), y: CGFloat(hue[1]),
                         z: CGFloat(hue[2]), w: CGFloat(hue[3])),
                CIVector(x: CGFloat(hue[4]), y: CGFloat(hue[5]),
                         z: CGFloat(p.iie), w: 0),
            ]
        )?.cropped(to: extent) ?? image
    }

    private static func row(_ v: SIMD3<Double>, lift: Double) -> CIVector {
        CIVector(x: CGFloat(v.x), y: CGFloat(v.y), z: CGFloat(v.z), w: CGFloat(lift))
    }

    private static func vector(_ v: SIMD3<Double>) -> CIVector {
        CIVector(x: CGFloat(v.x), y: CGFloat(v.y), z: CGFloat(v.z), w: 0)
    }
}
