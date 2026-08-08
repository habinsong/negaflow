import CoreImage

// MARK: - FilmScanDenoise (사용자 토글 노이즈 제거 — multi-scale shrinkage)
//
// **블러로 뭉개지 않고, 탈색하지 않는다.** 색-분리 웨이블릿 coring + median 임펄스 교체라는
// 공개된 신호처리 기법으로 구성한 자체 구현이다:
//
//   1. 감마 리프트(x^0.45) — 분산 안정화. 암부 노이즈 진폭이 톤 전체에서 균일해져
//      단일 임계로 전 톤의 노이즈를 다룰 수 있다.
//   2. 가우시안 피라미드 차분으로 luma 3-band / chroma 4-band 분해 후, 노이즈 크기 이하의
//      detail 계수만 0으로 수축(coring). 엣지/디테일(큰 계수)은 그대로 유지되고
//      base band(평균 색·채도)는 건드리지 않으므로 탈색이 구조적으로 불가능하다.
//   3. 고립 임펄스(흰 점·색 점)는 coring이 엣지로 오인해 남기므로 3x3 median 교체로 별도 처리.
//
// 필름 타입별 특성(현상 기본값 Film 연동):
//   • 컬러 네거티브: 반전이 명부(=필름 고농도부)의 스캔 노이즈를 증폭 → 클리핑 직전
//     chroma 정리를 강화. 암부/중간톤 기본 강화.
//   • 컬러 슬라이드: 필름 고농도부가 곧 암부 → 암부를 더 강하게, 명부(깨끗하게 클리핑)는 보호.
//   • 흑백 2종: 최종 그레이스케일 변환이 chroma를 제거하므로 luma만 처리(chroma 불변).
//
// 축 분리(Axes): 단일 강도 대신 luma/chroma/dark-tone/detail 축을 사용자에게 노출하는
// 일반적 NR 축 구성이다(휘도·색·디테일 회복을 분리하는 현상 도구들의 관례). grain 보호 축은
// 무채색 grain을 다시 블렌드하고 film grain을 보존(강도=휘도의 함수)하는 원리를 따라,
// grain 가시성이 최대인 미드톤에서 luma coring만 완화한다(chroma 노이즈 제거는 유지 —
// 필름 grain은 무채색 질감이므로 색 반점 정리와 충돌하지 않는다).
public enum FilmScanDenoise {
    /// 사용자 조절 NR 축. 0.5 = 기준(단일 슬라이더 시절과 동일 출력), grainProtect만 0 = 기준.
    public struct Axes: Sendable, Equatable {
        public var luma: Double          // 0...1 — 휘도 노이즈 강도(0 = luma 불변)
        public var chroma: Double        // 0...1 — 색 노이즈 강도(0 = chroma 불변)
        public var darkTone: Double      // 0...1 — 암부 추가 강도(0 = 암부 부스트 없음)
        public var detail: Double        // 0...1 — 디테일 보존(높을수록 구조 가드 민감↑)
        public var grainProtect: Double  // 0...1 — 미드톤 grain 보존(높을수록 luma 질감 유지)

        public init(luma: Double = 0.5, chroma: Double = 0.5, darkTone: Double = 0.5,
                    detail: Double = 0.5, grainProtect: Double = 0) {
            self.luma = luma
            self.chroma = chroma
            self.darkTone = darkTone
            self.detail = detail
            self.grainProtect = grainProtect
        }

        public static let neutral = Axes()

        var clamped: Axes {
            Axes(luma: min(max(luma, 0), 1),
                 chroma: min(max(chroma, 0), 1),
                 darkTone: min(max(darkTone, 0), 1),
                 detail: min(max(detail, 0), 1),
                 grainProtect: min(max(grainProtect, 0), 1))
        }
    }

    private struct Profile {
        var lumaScale: Double
        var chromaScale: Double
        var shadowBoost: Double
        var highlightChroma: Double
        var highlightLumaProtect: Double
        var isMonochrome: Bool
    }

    private static func profile(for filmType: FilmType) -> Profile {
        switch filmType {
        case .colorNegative:
            return Profile(lumaScale: 1.0, chromaScale: 1.0, shadowBoost: 0.6,
                           highlightChroma: 0.8, highlightLumaProtect: 0.45, isMonochrome: false)
        case .colorPositive:
            return Profile(lumaScale: 1.0, chromaScale: 0.9, shadowBoost: 1.1,
                           highlightChroma: 0.25, highlightLumaProtect: 0.65, isMonochrome: false)
        case .bwNegative:
            return Profile(lumaScale: 1.15, chromaScale: 0, shadowBoost: 0.7,
                           highlightChroma: 0, highlightLumaProtect: 0.45, isMonochrome: true)
        case .bwPositive:
            return Profile(lumaScale: 1.15, chromaScale: 0, shadowBoost: 1.1,
                           highlightChroma: 0, highlightLumaProtect: 0.65, isMonochrome: true)
        }
    }

    /// - strength: 0...1 (0 = off). coring 임계를 키워 강할수록 더 큰 노이즈까지 수축한다.
    /// - axes: 축별 밸런스. 기본 .neutral은 축 도입 전과 동일한 출력을 낸다.
    public static func apply(to image: CIImage, strength: Double, filmType: FilmType,
                             axes: Axes = .neutral) -> CIImage {
        guard strength > 1e-3 else { return image }
        let extent = image.extent
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "filmScanShrink") else { return image }

        let s = min(max(strength, 0), 1)
        let p = 0.45
        let lifted = image.applyingFilter("CIGammaAdjust", parameters: ["inputPower": p]).cropped(to: extent)
        // 블러/median이 extent 밖(투명)을 샘플해 가장자리가 어두워지지 않도록 clamp 후 crop.
        let clamped = lifted.clampedToExtent()

        func blur(_ radius: Double) -> CIImage {
            clamped.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius]).cropped(to: extent)
        }
        let fine = blur(1.3)
        // 중간/coarse 레벨은 가우시안 대신 guided filter — 강한 경계를 넘는 색/톤 번짐을
        // 원천 차단해, 경계 인접 영역의 실색·엣지가 coring에 깎이지 않는다(엣지 인식).
        // 두 레벨 모두 엣지 인식이어야 경계 근처 detail band 쌍(dy2≈−dy3)이 임계 차이로
        // 한쪽만 수축돼 블러 스미어가 남는 불일치가 생기지 않는다.
        // 가이드는 사전 블러된 luma 단일 채널: 노이즈(가이드에 없음)는 평균화되고
        // 엣지(가이드의 luma 구조)는 보존된다.
        let guide = luminance(of: fine)
        let midBase = edgeAwareBase(of: lifted, guide: guide, radius: 3.0, extent: extent) ?? blur(3.0)
        let coarseBase = edgeAwareBase(of: lifted, guide: guide, radius: 7.0, extent: extent) ?? blur(7.0)
        let med3 = median(clamped, extent: extent)
        let med5 = median(med3.clampedToExtent(), extent: extent)

        let prof = profile(for: filmType)
        let ax = axes.clamped
        // 축 → 커널 파라미터 매핑. 0.5 = ×1(기존), 0 = ×0(축 끔), 1 = ×2.
        let lumaGate = ax.luma * 2
        let chromaGate = ax.chroma * 2
        let dtScale = ax.darkTone * 2
        // 디테일 축은 구조 가드의 발동 지점을 조절: 1.5 − detail ∈ [0.5, 1.5].
        // detail↑ → 가드가 더 작은 구조에서 발동(보호↑), detail↓ → 질감 위까지 스무딩.
        let detailScale = 1.5 - ax.detail
        // 임계 0은 Metal smoothstep(0,0,x)의 0/0을 만들므로 미세 바닥값으로 pass-through 처리.
        let lumaT = max(0.065 * pow(s, 1.25) * prof.lumaScale * lumaGate, 1e-6)
        let chromaT = max(0.14 * pow(s, 1.1) * prof.chromaScale * chromaGate, 1e-6)
        // 임펄스 교체 강도도 해당 축을 따른다(축 0 = 교체 안 함 → 임계를 사실상 무한대로).
        let impLumaT = lumaGate > 1e-3 ? (0.10 - 0.055 * s) / min(lumaGate, 1) : 10
        let impChromaT = chromaGate > 1e-3 ? (0.09 - 0.05 * s) / min(chromaGate, 1) : 10

        let shrunk = kernel.apply(extent: extent, arguments: [
            lifted, med3, med5,
            fine, midBase, coarseBase,
            CIVector(x: lumaT, y: chromaT),
            CIVector(x: impLumaT, y: impChromaT),
            CIVector(x: prof.isMonochrome ? 1 : 0,
                     y: prof.shadowBoost * dtScale,
                     z: prof.highlightChroma,
                     w: prof.highlightLumaProtect),
            CIVector(x: dtScale, y: detailScale, z: ax.grainProtect, w: 0),
        ])?.cropped(to: extent) ?? lifted

        return shrunk.applyingFilter("CIGammaAdjust", parameters: ["inputPower": 1.0 / p]).cropped(to: extent)
    }

    /// Guided filter(He et al.) — 창 회귀 기반 엣지 인식 스무딩. CIGuidedFilter가
    /// guide/epsilon을 반영하지 않아(프로브 검증) box blur + Metal 커널로 직접 구현한다.
    /// 평탄한 노이즈(가이드와 무상관)는 창 평균으로, luma 구조는 가이드를 따라 보존된다.
    private static func edgeAwareBase(of image: CIImage, guide: CIImage, radius: Double, extent: CGRect) -> CIImage? {
        guard
            let productK = ChromabaseMetalKernels.colorKernel(named: "gfProduct"),
            let coeffAK = ChromabaseMetalKernels.colorKernel(named: "gfCoeffA"),
            let coeffBK = ChromabaseMetalKernels.colorKernel(named: "gfCoeffB"),
            let applyK = ChromabaseMetalKernels.colorKernel(named: "gfApply")
        else { return nil }
        func box(_ img: CIImage) -> CIImage {
            img.clampedToExtent()
                .applyingFilter("CIBoxBlur", parameters: ["inputRadius": radius])
                .cropped(to: extent)
        }
        guard
            let ii = productK.apply(extent: extent, arguments: [guide, guide]),
            let ip = productK.apply(extent: extent, arguments: [guide, image])
        else { return nil }
        let mI = box(guide)
        let mP = box(image)
        guard let a = coeffAK.apply(extent: extent, arguments: [box(ip), box(ii), mI, mP, 0.001]),
              let b = coeffBK.apply(extent: extent, arguments: [a, mI, mP])
        else { return nil }
        return applyK.apply(extent: extent, arguments: [box(a), box(b), guide, image])?.cropped(to: extent)
    }

    /// 3x3 median(CIMedianFilter). 임펄스를 제거하되 엣지는 보존한다.
    private static func median(_ image: CIImage, extent: CGRect) -> CIImage {
        guard let f = CIFilter(name: "CIMedianFilter") else { return image.cropped(to: extent) }
        f.setValue(image, forKey: kCIInputImageKey)
        return f.outputImage?.cropped(to: extent) ?? image.cropped(to: extent)
    }

    private static func luminance(of image: CIImage) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: image.extent)
    }
}
