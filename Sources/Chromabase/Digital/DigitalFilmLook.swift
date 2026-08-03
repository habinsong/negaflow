import CoreImage
import CoreGraphics

// MARK: - DigitalFilmLook (디지털 소스 전용 필름 룩)
//
// 필름 스캔에서는 좌측 Film 탭이 색 LUT 하나로 충분하다. 스캔본에는 이미 노출 관용도,
// 밀도 응답, 산란, 그레인이 픽셀 안에 들어 있고 룩은 그 위에 색만 얹으면 되기 때문이다.
//
// 디지털 사진에는 그중 어느 것도 없다. 그래서 이 경로는 색을 바꾸는 대신 **필름이 하는 일을
// 순서대로 다시 한다**:
//
//   1. 카메라가 씌운 디스플레이 렌더를 풀어 필름이 받을 노출을 되돌린다
//   2. 선형 광 상태에서 산란·헐레이션을 얹는다(밀도가 생기기 전이어야 한다)
//   3. 가상 현상 — 특성곡선으로 밀도를 만들고, DIR 커플러의 층간 억제를 걸고,
//      네거티브면 RA-4 인화까지, 반전이면 투과율로 읽는다
//   4. 스톡 고유의 색 시그니처를 얹는다(대비는 3에서 이미 만들어졌다)
//   5. 밀도에 따라 그레인을 흔들고, MTF 만큼 엣지를 세운다
//
// 측정으로 확인한 문제를 정면으로 다룬다: 카메라 렌더 입력에 색 LUT 만 얹으면 명부 계조가
// 붕괴하고(스텝 간격 0.0031, 플랫 입력의 1/14) 채도만 남는다. 1 단계가 헤드룸을 되돌리고
// 3 단계가 필름의 2단 곡선으로 그 헤드룸을 소비한다.
//
// **필름 스캔은 이 경로를 지나지 않는다.**
public enum DigitalFilmLook {

    public static func apply(
        to image: CIImage,
        emulation: FilmEmulation,
        intensity: Double,
        grainOverride: Double,
        halationOverride: Double
    ) -> CIImage {
        guard emulation != .none, let physics = DigitalFilmPhysics.of(emulation) else {
            return image
        }
        let strength = min(max(intensity, 0), 1)
        guard strength > 1e-3 else { return image }

        let extent = image.extent
        var img = DigitalSceneReconstruct.apply(to: image)

        // 산란/헐레이션은 밀도가 생기기 전 선형 광 상태에서만 물리적으로 옳다.
        img = DigitalHalation.apply(
            to: img,
            physics: physics,
            strength: resolve(override: halationOverride, default: strength)
        )

        img = DigitalFilmDevelop.apply(to: img, physics: physics)
        img = DigitalFilmColor.apply(to: img, emulation: emulation)
        img = DigitalFilmColorPresetStage.apply(to: img, emulation: emulation)

        // 그레인은 필름 물성이라 필름을 고르면 따라온다.
        img = DigitalFilmGrain.apply(
            to: img,
            physics: physics,
            strength: resolve(override: grainOverride, default: strength)
        )
        img = acutance(img, emulation: emulation, strength: strength, extent: extent)

        return blend(original: image, rendered: img.cropped(to: extent), amount: strength, extent: extent)
    }

    /// Texture 슬라이더와 필름 물성의 관계. 슬라이더가 0 이면 "안 만졌다"는 뜻이라 유제가
    /// 정한 기본 기여를 쓰고, 올려 두었다면 그 값이 강도가 된다. 두 값을 더하지 않는 이유는
    /// 이 조합에서 후처리 텍스처 단계의 같은 축을 비워 두기 때문이다 — 더하면 이중이 된다.
    private static func resolve(override: Double, default fallback: Double) -> Double {
        override > 1e-3 ? min(max(override, 0), 1) : fallback
    }

    /// MTF(선예도). 기존 필름 프로파일의 데이터시트 유도 계수를 그대로 쓴다.
    private static func acutance(
        _ image: CIImage, emulation: FilmEmulation, strength: Double, extent: CGRect
    ) -> CIImage {
        let acutance = FilmEmulationProfile.of(emulation).acutance
        guard acutance.intensity > 1e-3 else { return image }
        return image.applyingFilter("CIUnsharpMask", parameters: [
            "inputRadius": acutance.radius,
            "inputIntensity": acutance.intensity * strength,
        ]).cropped(to: extent)
    }

    /// 강도 블렌드. 물리 체인은 부분 적용이라는 개념이 없으므로, 완성된 결과와 원본 사이를
    /// 섞어 사용자가 정도를 고를 수 있게 한다.
    private static func blend(
        original: CIImage, rendered: CIImage, amount: Double, extent: CGRect
    ) -> CIImage {
        guard amount < 0.999 else { return rendered }
        return CIFilter(name: "CIMix", parameters: [
            kCIInputImageKey: rendered,
            kCIInputBackgroundImageKey: original,
            kCIInputAmountKey: amount,
        ])?.outputImage?.cropped(to: extent) ?? rendered
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
