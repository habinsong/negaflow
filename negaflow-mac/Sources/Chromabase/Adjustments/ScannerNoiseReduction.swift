import CoreImage

// MARK: - ScannerNoiseReduction
//
// 필름 스캔 노이즈는 두 종류다.
//   • 컬러 노이즈(chroma): 색 반점. 특히 암부에서 붉은/녹색 얼룩으로 나타난다.
//   • 휘도 노이즈(luma):   밝기 입자. 필름 그레인과 섞여 있어 과하게 지우면 디테일이 죽는다.
//
// 색차 기반 노이즈 제거의 표준 원리:
//   휘도(luma)는 보존하고 chroma만 부드럽게 한다. 색차 성분만 블러하면
//   디테일(엣지/그레인)은 유지되면서 색 얼룩만 사라진다. 암부일수록 더 강하게.
//
// 이전 구현의 `apply`는 중심 가중치가 큰 커널(샤픈)이라 노이즈를 증폭했다 — 제거했다.
enum ScannerNoiseReduction {
    private enum ChromaProfile {
        case shadow
        case main
        case postGrade

        func smallRadius(tuning: ScannerNoiseReductionTuning) -> Double {
            switch self {
            case .shadow: return 3.2 * tuning.chromaRadiusScale
            case .main: return 3.8 * tuning.chromaRadiusScale
            case .postGrade: return 3.2 * tuning.chromaRadiusScale
            }
        }

        func largeRadius(tuning: ScannerNoiseReductionTuning) -> Double {
            switch self {
            case .shadow: return 12.0 * tuning.shadowRadiusScale
            case .main: return 18.0 * tuning.shadowRadiusScale
            case .postGrade: return 9.0 * tuning.shadowRadiusScale
            }
        }

        func strength(tuning: ScannerNoiseReductionTuning) -> Double {
            switch self {
            case .shadow: return 0.78 * tuning.strengthScale
            case .main: return 1.0 * tuning.strengthScale
            case .postGrade: return 0.95 * tuning.strengthScale
            }
        }
    }

    /// 라이트 톤의 컬러 노이즈 제거(약). 반전 후 positive에 적용한다.
    static func apply(to image: CIImage) -> CIImage {
        reduceColorNoise(in: image, chromaRadius: 2.0, lumaRadius: 0.8, shadowBias: false)
    }

    /// 암부 컬러 노이즈를 정리하되, 미드톤의 실제 색 채도는 보존한다.
    /// 전역 chroma 블러를 약하게 둬(반경↓) 중간톤 채색 디테일이 뭉개져 탈색되지 않게 한다.
    static func reduceShadowChroma(in image: CIImage) -> CIImage {
        let base = reduceColorNoise(in: image, chromaRadius: 1.6, lumaRadius: 0, shadowBias: false)
        let shadows = reduceColorNoise(in: base, chromaRadius: 4.4, lumaRadius: 1.0, shadowBias: true)
        return reduceMidtoneChroma(
            in: neutralizeLowSaturationMagenta(in: shadows),
            profile: .shadow,
            tuning: .generic
        )
    }

    static func reduceMainTargetChroma(in image: CIImage) -> CIImage {
        reduceMainTargetChroma(in: image, noiseProfile: nil)
    }

    static func reduceMainTargetChroma(
        in image: CIImage,
        noiseProfile: ScannerNoiseProfile?
    ) -> CIImage {
        let tuning = tuning(for: noiseProfile)
        let base = reduceColorNoise(
            in: image,
            chromaRadius: 2.4 * tuning.chromaRadiusScale,
            lumaRadius: 0,
            shadowBias: false
        )
        let shadows = reduceColorNoise(
            in: base,
            chromaRadius: 4.4 * tuning.shadowRadiusScale,
            lumaRadius: 0.55 * tuning.lumaRadiusScale,
            shadowBias: true
        )
        return reduceMidtoneChroma(
            in: neutralizeLowSaturationMagenta(in: shadows),
            profile: .main,
            tuning: tuning
        )
    }

    static func reducePostGradeChroma(in image: CIImage) -> CIImage {
        reducePostGradeChroma(in: image, noiseProfile: nil)
    }

    static func reducePostGradeChroma(
        in image: CIImage,
        noiseProfile: ScannerNoiseProfile?
    ) -> CIImage {
        reduceMidtoneChroma(
            in: image,
            profile: .postGrade,
            tuning: tuning(for: noiseProfile)
        )
    }

    static func tuning(for profile: ScannerNoiseProfile?) -> ScannerNoiseReductionTuning {
        guard let profile, profile.allowsAutomaticUse else { return .generic }
        return profile.tuning
    }

    private static func reduceMidtoneChroma(
        in image: CIImage,
        profile: ChromaProfile,
        tuning: ScannerNoiseReductionTuning
    ) -> CIImage {
        let extent = image.extent
        let luma = luminance(of: image)
        let chroma = chromaImage(from: image).cropped(to: extent)
        let smallRadius = profile.smallRadius(tuning: tuning)
        let largeRadius = profile.largeRadius(tuning: tuning)
        let smallChroma = profile == .postGrade
            ? chroma.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": smallRadius]).cropped(to: extent)
            : guidedChroma(
                chroma,
                guide: luma,
                radius: smallRadius,
                epsilon: 0.0012,
                fallbackRadius: smallRadius * 1.25
            )
        let largeChroma = guidedChroma(
            chroma,
            guide: luma,
            radius: largeRadius,
            epsilon: 0.0045,
            fallbackRadius: largeRadius * 0.85
        )
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "scannerMidtoneChroma") else { return image }
        return kernel.apply(extent: extent, arguments: [
            image,
            smallChroma,
            largeChroma,
            profile.strength(tuning: tuning),
        ])?.cropped(to: extent) ?? image
    }

}
