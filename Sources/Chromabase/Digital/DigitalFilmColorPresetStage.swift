import CoreImage
import CoreGraphics

// MARK: - DigitalFilmColorPresetStage (디지털 소스 전용)
//
// 스톡 색 프리셋을 실제로 태우는 자리다. 그레이딩·믹서·캘리브레이션 세 스테이지는 이 저장소가
// 이미 쓰고 검증한 것을 그대로 재사용하고, 여기서는 도메인만 맞춰 준다.
//
// 세 스테이지 모두 표시 도메인 0…1 을 전제로 만들어졌다(내부에서 clamp 한다). 입력은 선형
// working image이므로 감마를 씌워 들어갔다가 되돌린다. 색 시그니처는 감마 도메인에서
// 적용해야 한다는 이 저장소의 기존 원칙과 같다. intensity는 이 보조 색 프리셋만 블렌드한다.
enum DigitalFilmColorPresetStage {

    static func apply(to image: CIImage, emulation: FilmEmulation, intensity: Double) -> CIImage {
        guard let preset = DigitalFilmColorPreset.of(emulation), !preset.isIdentity else {
            return image
        }
        let strength = min(max(intensity, 0), 1)
        guard strength > 1e-3 else { return image }
        let extent = image.extent
        guard let toDisplay = ChromabaseMetalKernels.colorKernel(named: "digitalToDisplayGamma"),
              let toLinear = ChromabaseMetalKernels.colorKernel(named: "digitalToLinearLight"),
              var img = toDisplay.apply(extent: extent, arguments: [image])?.cropped(to: extent) else {
            return image
        }

        img = ColorMixerStage.apply(to: img, mixer: preset.mixer)
        img = ColorGradingStage.apply(to: img, grading: preset.grading)
        img = CalibrationStage.apply(to: img, calibration: preset.calibration)

        guard let rendered = toLinear.apply(extent: extent, arguments: [img])?.cropped(to: extent) else {
            return image
        }
        guard strength < 0.999 else { return rendered }
        return CIFilter(name: "CIMix", parameters: [
            kCIInputImageKey: rendered,
            kCIInputBackgroundImageKey: image,
            kCIInputAmountKey: strength,
        ])?.outputImage?.cropped(to: extent) ?? rendered
    }
}
