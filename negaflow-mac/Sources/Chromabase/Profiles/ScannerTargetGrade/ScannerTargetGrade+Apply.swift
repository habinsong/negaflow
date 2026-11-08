import CoreImage

extension ScannerTargetGrade {
    // MARK: 적용

    /// 파이프라인의 타깃 자리. 화이트 밸런스·노출·기본 톤·파라메트릭 커브 **뒤**, 포인트 커브·HSL·
    /// 그레이딩 **앞**이다. 랩 스캐너도 오퍼레이터의 농도·색 보정을 스캔 데이터에 먼저 걸고 고정 인화
    /// 곡선으로 출력한다. 예전에는 반전 직후(화이트 밸런스 앞)에 걸어, 흰색을 0.95 근처까지 그린
    /// 인화 출력 위에서 MAIN 의 여유(흰색 0.70, 숄더 무릎 0.70)를 전제로 만든 슬라이더가 다시
    /// 돌았다 — 같은 사진에서 노출 +0.5 의 클리핑이 MAIN 0.1%·SP 28.6%, 흰색 계열 +0.5 는 0%·20.7%
    /// (2026-11-07 실측). 슬라이더가 모두 0 이면 앞 단계가 항등이라 결과는 예전과 같다.
    public static func applyAfterSceneAdjustments(to image: CIImage,
                                                  params: DevelopParameters) -> CIImage {
        guard params.developTarget.isScannerEmulation else { return image }
        return apply(to: image, target: params.developTarget, params: params)
    }

    /// 스캐너 타깃 렌더링. 순서: 고정 렌더링 → 사용자가 고른 필름 프로파일의 실측 상대 차분
    /// (있을 때만) → 장치 질감. 장면을 읽지 않으므로 같은 입력 화소는 사진과 무관하게 같은
    /// 값이 된다 — 프레임별 노출·색 맞춤은 반전과 우측 패널의 자동 레벨·색상·톤·WB 몫이다.
    public static func apply(to image: CIImage,
                             target: DevelopTarget,
                             params: DevelopParameters) -> CIImage {
        guard let rendering = rendering(for: target) else { return image }
        let monochrome = params.filmType == .bwNegative || params.filmType == .bwPositive
        let positive = params.filmType == .colorPositive || params.filmType == .bwPositive
        var img = monochrome ? collapsedToLuma(image) : image
        img = applyRendering(to: img, rendering: rendering, monochrome: monochrome,
                             strength: positive ? renderingPositiveStrength : 1.0)
        if let diff = resolveSignature(target: target, params: params) {
            img = apply(to: img, signature: diff, target: target,
                        monochrome: monochrome, positive: positive)
        }
        return applyDocumentedTexture(to: img, target: target)
    }

    /// 흑백은 렌더링 앞에서 luma 로 붕괴한다(입력의 잔여 색 노이즈/베이스 틴트 제거).
    static func collapsedToLuma(_ image: CIImage) -> CIImage {
        let luma = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": luma,
            "inputGVector": luma,
            "inputBVector": luma,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: image.extent)
    }

    static func apply(
        to image: CIImage,
        signature sig: Signature,
        target _: DevelopTarget,
        monochrome: Bool = false,
        positive _: Bool = false
    ) -> CIImage {
        let extent = image.extent

        // ── 0. 흑백은 luma 로 붕괴한다. 실기 틴트(neutralBins)는 여기서 적용하지 않는다 —
        //    PostPipeline 이 마지막에 강제 중립화하므로 틴트는 그 뒤 applyMonochromeTint 몫이다.
        var img = image
        var cubeSig = sig
        if monochrome {
            img = collapsedToLuma(img)
            cubeSig.neutralBins = []
        }

        // ── 1. 실측 상대 차분 3D LUT(감마 도메인): 톤 + 중립축 드리프트 + hue.
        //    CIColorCubeWithColorSpace(sRGB) 가 working(linear) ↔ sRGB 감마 변환을 담당하므로
        //    큐브 내용은 실측과 같은 좌표계에서 정의된다.
        if let srgb = CGColorSpace(name: CGColorSpace.sRGB) {
            let ungraded = img
            let graded = ungraded.applyingFilter("CIColorCubeWithColorSpace", parameters: [
                "inputCubeDimension": cubeDimension,
                "inputCubeData": cubeData(for: cubeSig),
                "inputColorSpace": srgb,
            ]).cropped(to: extent)
            if let kernel = ChromabaseMetalKernels.colorKernel(named: "boundedRelativeGrade") {
                img = kernel.apply(extent: extent, arguments: [ungraded, graded])?
                    .cropped(to: extent) ?? ungraded
            }
        }

        return img.cropped(to: extent)
    }

    /// 흑백 파이프라인의 마지막 중립화 이후, 측정된 흑백 중립축 시그니처가 있을 때만
    /// 틴트를 적용한다. 현재 번들에는 해당 측정값이 없어 패스스루된다.
    public static func applyMonochromeTint(to image: CIImage,
                                           params: DevelopParameters) -> CIImage {
        guard params.developTarget.isScannerEmulation,
              params.filmType == .bwNegative || params.filmType == .bwPositive,
              let sig = resolveSignature(target: params.developTarget, params: params),
              !sig.neutralBins.isEmpty,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        let extent = image.extent
        let tintOnly = Signature(
            tone: designToneXs,
            neutralBins: sig.neutralBins,
            hueAnchors: []
        )
        return image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": cubeDimension,
            "inputCubeData": cubeData(for: tintOnly),
            "inputColorSpace": srgb,
        ]).cropped(to: extent)
    }
}
