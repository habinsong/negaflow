import CoreImage
import CoreGraphics

// MARK: - DigitalFilmDevelop (디지털 소스 전용 — 가상 현상)
//
// 추정된 노출을 필름 화학으로 통과시킨다. 색 LUT 한 장으로는 만들 수 없는 부분이 여기다.
//
//   네거티브(C-41)  노출 → 네거티브 밀도 → 층간 억제 → 인화 노출 → RA-4 인화지 밀도 → 반사율
//   반전(E-6)       노출 → 포지티브 밀도 → 층간 억제 → 투과율
//
// 네거티브가 필름다운 이유는 2단 구조에 있다. 카메라 네거티브의 감마는 0.5~0.6 으로 낮아
// 넓은 장면을 얇게 담고, 인화지의 감마 1.6~1.8 이 그 대비를 되살린다. 총 감마는 1 근처가
// 되지만, 양 끝은 **네거티브 곡선과 인화지 곡선 두 번**을 지나며 눕는다. 디지털의 한 번짜리
// 숄더와 결정적으로 다른 지점이고, 명부가 "날아가지 않고 눕는" 느낌의 정체다.
//
// 반전은 필름 자체가 최종물이라 인화 단계가 없다. 감마가 높고 밝은 쪽 여유가 1~1.5 스톱뿐이라
// 과노출이 빨리 날아간다 — 슬라이드의 좁은 관용도가 곡선에서 자연히 따라 나온다.
public enum DigitalFilmDevelop {

    // MARK: RA-4 인화지 (매체 상수 — 필름별이 아니다)

    /// 인화지 감마. 공개 문헌이 전하는 chromogenic RA-4 인화지의 역사적 값 1.6~1.8 의 중앙.
    static let paperGamma = 1.70
    /// 인화지가 낼 수 있는 최대 밀도(중간 회색 기준 상대).
    ///
    /// 인화물 자체의 Dmax 는 2.2 대지만, 여기서 재현하는 것은 인화물이 아니라 **그것을 담아
    /// 본 이미지**다. 필름을 거친 이미지에는 진짜 검정이 없다 — 베이스와 카브리가 밀도 바닥을
    /// 만들고, 스캔은 클리핑을 피하려 여백을 남긴다. 그 바닥을 그대로 두는 것이 디지털의
    /// 쨍한 검정과 갈리는 지점이라, 밑을 눌러 붙이지 않고 들어 둔다.
    static let paperDmax = 1.52
    /// 인화지 흰색. 반사율 상한이 있으므로 명부는 여기서 멈춘다 — 네거티브 관용도가 아무리
    /// 넓어도 인화에서 명부가 2~3 스톱쯤에서 눕는 실제 거동이 이 한계에서 나온다.
    /// 순백까지 가지 않는 것도 같은 이유다.
    static let paperDmin = 0.790
    /// 인화지 곡선의 급격함. 대비가 높은 매체라 필름보다 빠르게 한계로 붙는다.
    static let paperKnee = 2.4

    /// 반전 필름의 최대 밀도(중간 회색 기준 상대). 슬라이드는 인화물보다 검정이 깊지만,
    /// 스캔해 화면에서 볼 때는 역시 바닥이 0 으로 붙지 않는다.
    static let reversalDmax = 1.78
    /// 반전 필름의 최소 밀도(밝은 쪽 한계). 투과광이라 인화지보다 밝은 쪽 여유가 크다.
    static let reversalDmin = 0.845

    public static func apply(to image: CIImage, physics: DigitalFilmPhysics) -> CIImage {
        let extent = image.extent
        var img = exposeDensity(image, physics: physics, extent: extent)
        img = interImage(img, physics: physics, extent: extent)
        return physics.isReversal
            ? transmit(img, extent: extent)
            : printOnPaper(img, extent: extent)
    }

    // MARK: 단계

    /// 노출 → 채널별 밀도. 중간 회색에서 밀도 0.
    private static func exposeDensity(
        _ image: CIImage, physics: DigitalFilmPhysics, extent: CGRect
    ) -> CIImage {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "digitalFilmDensity") else {
            return image
        }
        let limits = densityLimits(for: physics)
        let polarity: Double = physics.isReversal ? -1 : 1
        return kernel.apply(
            extent: extent,
            arguments: [
                image,
                CIVector(x: CGFloat(physics.gamma.x), y: CGFloat(physics.gamma.y),
                         z: CGFloat(physics.gamma.z), w: CGFloat(polarity)),
                CIVector(x: CGFloat(limits.high), y: CGFloat(limits.low),
                         z: CGFloat(limits.shoulderKnee), w: CGFloat(limits.toeKnee)),
                Float(exposureScale(for: physics)),
                CIVector(x: CGFloat(physics.layerSpeed.x), y: CGFloat(physics.layerSpeed.y),
                         z: CGFloat(physics.layerSpeed.z), w: 0),
                CIVector(x: CGFloat(physics.layerDmax.x), y: CGFloat(physics.layerDmax.y),
                         z: CGFloat(physics.layerDmax.z), w: 0),
            ]
        )?.cropped(to: extent) ?? image
    }

    /// DIR 커플러의 층간 억제. 중립은 보존되고 유채색만 벌어진다.
    private static func interImage(
        _ image: CIImage, physics: DigitalFilmPhysics, extent: CGRect
    ) -> CIImage {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "digitalInterImage") else {
            return image
        }
        let k = physics.interImage
        return kernel.apply(
            extent: extent,
            arguments: [image, CIVector(x: CGFloat(k.x), y: CGFloat(k.y), z: CGFloat(k.z), w: 0)]
        )?.cropped(to: extent) ?? image
    }

    private static func printOnPaper(_ image: CIImage, extent: CGRect) -> CIImage {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "digitalPrintPaper") else {
            return image
        }
        return kernel.apply(
            extent: extent,
            arguments: [image, CIVector(x: CGFloat(paperGamma), y: CGFloat(paperDmax),
                                        z: CGFloat(paperDmin), w: CGFloat(paperKnee))]
        )?.cropped(to: extent) ?? image
    }

    private static func transmit(_ image: CIImage, extent: CGRect) -> CIImage {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "digitalReversalTransmit") else {
            return image
        }
        // 밀도 단계에서 이미 유제의 한계까지 눕혔으므로 여기서는 살짝 여유를 두어
        // 같은 한계를 두 번 적용하지 않는다.
        return kernel.apply(
            extent: extent,
            arguments: [image, CIVector(x: CGFloat(reversalDmax * 1.2),
                                        y: CGFloat(reversalDmin * 1.15),
                                        z: 3.0, w: 0)]
        )?.cropped(to: extent) ?? image
    }

    // MARK: 곡선 한계

    struct DensityLimits {
        var high: Double        // 밀도 상한(네거티브: 명부, 반전: 암부)
        var low: Double         // 밀도 하한
        var shoulderKnee: Double
        var toeKnee: Double
    }

    /// 유제의 밀도 범위. 네거티브는 관용도와 감마가 함께 정하고, 반전은 유제의 Dmax/Dmin 이
    /// 직접 한계가 된다(반전은 필름이 곧 최종물이라 뒤에서 잡아 줄 인화지가 없다).
    static func densityLimits(for physics: DigitalFilmPhysics) -> DensityLimits {
        // knee: 부드러움 0…1 을 곡선 지수로.
        //
        // 지수가 1 에 가까우면 한계에 부드럽게 다가가지만 곡선 중간까지 함께 눌려 톤 전체가
        // 뭉갠다(측정: 지수 1.1 에서 실효 감마가 0.95 여야 할 자리에 0.47). 반대로 너무 크면
        // 한계 부근이 급히 끊겨 계조가 사라진다. 중간 구간의 기울기를 지키면서 끝에서만 눕도록
        // 그 사이를 쓰고, 한계값 자체를 넉넉히 잡아 실제 신호가 끊기는 지점까지 가지 않게 한다.
        let shoulderKnee = 1.0 + (1.0 - physics.shoulderSoftness) * 2.2
        let toeKnee = 1.0 + (1.0 - physics.toeSoftness) * 2.2
        if physics.isReversal {
            return DensityLimits(high: reversalDmax, low: reversalDmin,
                                 shoulderKnee: shoulderKnee, toeKnee: toeKnee)
        }
        let gammaMean = mean(physics.gamma)
        let halfRange = gammaMean * 0.30103 * physics.latitudeStops * 0.5
        return DensityLimits(high: halfRange, low: halfRange,
                             shoulderKnee: shoulderKnee, toeKnee: toeKnee)
    }

    // MARK: 노출 스케일

    /// 기준 조합(Portra 400 + RA-4)의 실효 감마. 표준 인화가 장면을 거의 1:1 로 재현한다는
    /// 사실을 앵커로 쓴다.
    static let referenceGammaEffective = 0.952
    /// 그 기준 조합이 목표로 하는 최종 감마.
    static let referenceFinalGamma = 1.0
    /// 필름 간 대비 차이를 얼마나 남길지(1 = 원래 차이 그대로, 0 = 전부 같게). 유제 고유의
    /// 대비 서열은 남기되, 반전 필름의 극단적인 감마가 그대로 곱해져 명부가 두 계조로
    /// 갈라지는 것은 막는다. 값을 올릴수록 슬라이드 대비가 살지만 명부 계조가 줄어드는
    /// 맞교환이라, 8비트 양자화 두 단계 이상이 남는 선에서 가장 높은 값을 골랐다.
    static let contrastRetention = 0.45

    /// 장면의 노출 범위를 그 유제가 실제로 담을 수 있는 범위로 옮기는 비율.
    ///
    /// 디지털 사진을 필름 노출로 되돌리면 6 스톱이 넘는 범위가 나오는데, 반전 필름은 중간
    /// 회색 위로 1 스톱 남짓이면 이미 흰색이다. 그 범위를 그대로 밀어 넣으면 명부 전체가
    /// 곡선 밖에 놓여 계조가 사라진다(측정으로 확인한 실패 모드다). 관용도가 좁은 필름에서
    /// 촬영자가 노출을 조여 담듯, 유제가 감당하는 범위로 노출 스케일을 좁힌다.
    ///
    /// 유제별로 값이 갈리되 대비 서열은 보존해야 한다. 명부만 보고 스케일을 정하면 슬라이드와
    /// 네거티브의 실효 감마가 같아져 두 매체의 차이가 사라진다.
    static func exposureScale(for physics: DigitalFilmPhysics) -> Double {
        let effective = effectiveGamma(of: physics)
        guard effective > 1e-6 else { return 1 }
        let target = referenceFinalGamma
            * pow(effective / referenceGammaEffective, contrastRetention)
        return min(1.0, max(0.25, target / effective))
    }

    /// 유제 감마에 매체 증폭까지 반영한 실효 감마. 네거티브는 인화지가 대비를 되살린다.
    static func effectiveGamma(of physics: DigitalFilmPhysics) -> Double {
        mean(physics.gamma) * (physics.isReversal ? 1.0 : paperGamma)
    }

    /// 노출 스케일까지 반영한 최종 감마. 필름 간 대비 서열 검증에 쓴다.
    static func finalGamma(of physics: DigitalFilmPhysics) -> Double {
        effectiveGamma(of: physics) * exposureScale(for: physics)
    }

    private static func mean(_ v: SIMD3<Double>) -> Double { (v.x + v.y + v.z) / 3 }
}
