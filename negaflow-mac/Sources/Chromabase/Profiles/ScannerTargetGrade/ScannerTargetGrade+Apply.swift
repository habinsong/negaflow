import CoreImage

extension ScannerTargetGrade {
    // MARK: 적용

    public static func apply(to image: CIImage,
                             target: DevelopTarget,
                             params: DevelopParameters) -> CIImage {
        var anchor: SceneToneAnchor?
        return apply(to: image, target: target, params: params, anchor: &anchor)
    }

    /// 이미 잰 장면 톤 앵커가 있으면 다시 재지 않는 변형. 앵커는 그레이드 **직전** 이미지에서
    /// 나오므로 인스펙터 값과 무관하다 — 슬라이더를 움직이는 동안 재사용해도 결과가 같다.
    static func apply(to image: CIImage,
                      target: DevelopTarget,
                      params: DevelopParameters,
                      anchor cachedAnchor: inout SceneToneAnchor?) -> CIImage {
        let monochrome = params.filmType == .bwNegative || params.filmType == .bwPositive
        let positive = params.filmType == .colorPositive || params.filmType == .bwPositive
        // 톤 전이의 노출 앵커: 실측/문서 톤은 풀레인지 장면(캘리브레이션 corpus 의 developed
        // percentile 지지: FUJI 실측 toneXs p5=0.16~p95=0.86, spread≈0.70)에서 도출됐다.
        // 평탄/흐린 장면은 developed 히스토그램이 좁은 대역(주로 상부)에 몰려 그 지지 밖이고,
        // 절대 코드 기준 리프트가 히스토그램 전체를 우측으로 밀어 노출 과다가 된다(실기는
        // 장면 적응 노출/톤이라 재정규화). 장면 계조 폭이 지지보다 좁을수록, 장면
        // median 의 톤 델타를 상수로 빼서 median 노출을 앵커한다 — 형태(대비)·색 개성은
        // 유지되고 노출 성분만 제거된다. 풀레인지 장면은 가중치 0 = 기존 결과 불변.
        let anchor = cachedAnchor ?? sceneToneAnchor(for: image)
        cachedAnchor = anchor
        var img = image
        // 1. 문서 기반 절대 개성(scanner emulation 이면 항상 적용). MAIN 대비 시각적 구별의 주 동인.
        if let doc = documentedCharacter(target: target, filmType: params.filmType, monochrome: monochrome) {
            img = apply(to: img, signature: sceneAdapted(doc, scene: anchor), target: target,
                        monochrome: monochrome, positive: positive)
        }
        // 2. 실측 상대 차분(roll-label matched pair 존재 시) — 문서 개성 위에 riding 하는 refinement.
        //    없으면 documented 만 적용된다(과거엔 여기서 nil → MAIN 과 동일했다).
        if let diff = resolveSignature(target: target, params: params) {
            img = apply(to: img, signature: sceneAdapted(diff, scene: anchor), target: target,
                        monochrome: monochrome, positive: positive)
        }
        // 3. 문서 근거 장치 질감(현재 NORITSU 샤픈) — 색 큐브 뒤, 최종 스캔 렌더 단계.
        img = applyDocumentedTexture(to: img, target: target)
        return img
    }

    struct SceneToneAnchor: Sendable, Equatable {
        var median: Double   // developed 감마 도메인 luma p50
        var weight: Double   // 0 = 풀레인지(앵커 없음), 1 = 평탄(전면 앵커)
    }

    /// 현상된(그레이드 직전) 이미지의 감마 도메인 luma percentile 로 장면 계조 폭과 median 을
    /// 잰다. 임계는 발명값이 아니라 톤 전이의 지지 분포에서 온다: FUJI 실측 toneXs 의
    /// p5~p95 spread ≈ 0.70(design 앵커도 ≈ 0.73) → 0.66 부터 게이트를 열고 0.45 이하는
    /// 전면 앵커.
    ///
    /// 프레임 경계(필름 홀더/베이스)는 이중 인셋 + 다크 셸프 판별로 제외한다(2026-07-23):
    /// 6% 인셋(sampleStats 와 동일)과 15% 인셋을 각각 재고, **rebate 링의 시그니처**가 보일
    /// 때만 내부(15%) 측정을 채택한다 — 시그니처 = 명부 쪽은 동일(내·외 p95 차 < 0.05)한데
    /// 암부 쪽만 바깥에서 근흑으로 급락(내 p05 − 외 p05 > 0.30 — 평탄 장면 밴드 vs 베이스
    /// 링의 실측 격차 ≈ 0.5, 정상 장면의 가장자리 섀도 격차는 그보다 훨씬 작다). 과거 6%
    /// 단일 인셋은 그보다 넓은 rebate/스트립 갭의 근흑 링이 spread 를 넓혀 평탄 감지를
    /// 무력화했고(평탄 장면 노출 이동 재발 — 실측 SP +0.33 스탑), 값 기반 흑색 제외는
    /// rebate 와 진짜 장면 근흑(차트 black patch)을 구분 못 해 금지, 무조건 min(두 spread)
    /// 채택은 계조 극단이 가장자리에 있는 정상 장면(하늘/광원/앵커 블록이 프레임 끝)을
    /// 평탄으로 오판했다. 판별자가 애매하면 항상 기존(6%) 측정을 유지한다(무회귀 우선).
    static func sceneToneAnchor(for image: CIImage) -> SceneToneAnchor {
        let extent = image.extent.integral
        guard extent.width > 8, extent.height > 8,
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else {
            return SceneToneAnchor(median: 0.5, weight: 0.0)
        }
        let targetW = max(32, min(160, Int(extent.width)))
        let scale = Double(targetW) / Double(extent.width)
        let targetH = max(1, Int(Double(extent.height) * scale))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        var bitmap = [Float](repeating: 0, count: targetW * targetH * 4)
        SamplingContextPool.context(workingColorSpace: linear).render(
            scaled, toBitmap: &bitmap,
            rowBytes: targetW * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
            format: .RGBAf, colorSpace: linear
        )
        struct InsetStats {
            var median: Double
            var p05: Double
            var p95: Double
            var spread: Double { p95 - p05 }
        }
        func measure(insetFraction: Double) -> InsetStats? {
            let insetX = max(1, Int(Double(targetW) * insetFraction))
            let insetY = max(1, Int(Double(targetH) * insetFraction))
            var lumas: [Double] = []
            lumas.reserveCapacity(targetW * targetH)
            for y in insetY..<max(insetY + 1, targetH - insetY) {
                for x in insetX..<max(insetX + 1, targetW - insetX) {
                    let i = (y * targetW + x) * 4
                    // cube 톤과 같은 좌표계: 감마 인코딩된 채널의 Rec.709 luma.
                    let r = srgbEncode(clamp(Double(bitmap[i]), 0.0, 1.0))
                    let g = srgbEncode(clamp(Double(bitmap[i + 1]), 0.0, 1.0))
                    let b = srgbEncode(clamp(Double(bitmap[i + 2]), 0.0, 1.0))
                    lumas.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
                }
            }
            guard lumas.count >= 64 else { return nil }
            lumas.sort()
            func pct(_ f: Double) -> Double {
                lumas[max(0, min(lumas.count - 1, Int(Double(lumas.count - 1) * f)))]
            }
            return InsetStats(median: pct(0.5), p05: pct(0.05), p95: pct(0.95))
        }
        guard let outer = measure(insetFraction: 0.06) else {
            return SceneToneAnchor(median: 0.5, weight: 0.0)
        }
        // rebate 링 판별: 내부로 들어가도 명부는 그대로인데 암부 하단만 사라지면(근흑 셸프가
        // 경계에만 존재) 내부 측정이 장면을 대표한다. 그 외에는 6% 측정 유지(무회귀 우선).
        var chosen = outer
        if let inner = measure(insetFraction: 0.15),
           outer.p95 - inner.p95 < 0.05,
           inner.p05 - outer.p05 > 0.30 {
            chosen = inner
        }
        let weight = 1.0 - smoothstep(0.45, 0.66, chosen.spread)
        return SceneToneAnchor(median: chosen.median, weight: weight)
    }

    /// 장면 적응 시그니처: 톤(노출)과 채도(개성)를 같은 flat-scene 가중치로 함께 게이트한다.
    /// 톤은 median 노출 앵커(exposureAnchored), 채도는 개성 수축(flatSceneChromaGated)이며
    /// 둘 다 scene.weight(0=풀레인지 → 불변, 1=평탄 → 게이트)로 구동된다.
    private static func sceneAdapted(_ sig: Signature, scene: SceneToneAnchor) -> Signature {
        exposureAnchored(flatSceneChromaGated(sig, weight: scene.weight), scene: scene)
    }

    /// 흐린/평탄(계조 지지 밖) 장면에서 스캐너의 **채도 개성**을 부분 수축한다.
    ///
    /// 근거(톤 게이트와 동형): 스캐너 chroma 대역·hue 채도 게인은 풀레인지 corpus(FUJI 실측
    /// 6쌍, toneXs p5~p95 spread≈0.70)에서 도출됐다. 계조가 그 지지보다 좁은 흐린 풍경에서는
    /// (1) 픽셀이 명부 대역(가장 극단적 gain: FUJI 1.60)에 몰리고, (2) base vibrance 가
    /// 저채도 장면을 이미 끌어올려, 두 배율이 겹쳐 과채도/과뮤트로 발산했다. 톤은
    /// sceneToneAnchor 로 지지 밖을 게이트하므로(exposureAnchored), 같은 weight 로 채도도
    /// 항등 쪽으로 당긴다. weight=0(풀레인지)이면 시그니처가 그대로라 결과 바이트 불변.
    ///
    /// **개성 플로어(2026-07-23 QA)**: 과거엔 weight=1 에서 완전 항등이라 평탄 장면에서
    /// 타겟들이 MAIN 으로 수렴해 구분 불가였다(사용자 QA). 수축 weight 를
    /// flatSceneChromaGateCeiling 으로 캡해 완전 평탄에서도 log-gain 의 일정 비율이
    /// 남는다(FUJI 1.60 → ≈1.18 — 원래 발산 크기의 절반 이하로 bounded, 과채도 재발 방지).
    /// **노출 앵커는 캡 없이 유지**한다 — 평탄 장면 노출 이동은 개성이 아니라 결함이다.
    /// hue **회전**·**중립축 드리프트**는 채도가 아니므로 건드리지 않는다(각자 taper/gate 소유).
    /// log 도메인 수축(pow(gain, keep))이라 두 스캐너의 역수 대칭(reciprocal cube)이 보존된다.
    static let flatSceneChromaGateCeiling = 0.65

    static func flatSceneChromaGated(_ sig: Signature, weight: Double) -> Signature {
        guard weight > 1e-3 else { return sig }
        // weight=1(평탄) → keep=0.35 → gain^0.35(부분 보존). 완전 항등 수렴 금지.
        let keep = 1.0 - min(weight, flatSceneChromaGateCeiling)
        var s = sig
        s.chromaBands = sig.chromaBands.map {
            ChromaBand(luma: $0.luma, gain: pow($0.gain, keep))
        }
        s.hueAnchors = sig.hueAnchors.map {
            HueAnchor(hueDegrees: $0.hueDegrees,
                      chromaGain: pow($0.chromaGain, keep),
                      rotateDegrees: $0.rotateDegrees)
        }
        return s
    }

    /// 장면 median 의 톤 델타 × 가중치를 상수로 빼서 노출을 앵커한다(색 성분 불변).
    /// 0.004(≈1/255) 단계 양자화는 cube 캐시 변형 수를 유한하게 묶는 결정적 경계다.
    private static func exposureAnchored(_ sig: Signature, scene: SceneToneAnchor) -> Signature {
        guard scene.weight > 1e-3,
              let firstX = sig.toneXs.first, let lastX = sig.toneXs.last else { return sig }
        // knot 범위 밖 median 은 가장 가까운 knot 의 델타를 쓴다(relativeToneValue 는 범위
        // 밖에서 endpoint 절대값을 돌려주므로 clamp 없이 쓰면 델타가 왜곡된다).
        let median = clamp(scene.median, firstX, lastX)
        let mappedMedian = relativeToneValue(at: median, xs: sig.toneXs, ys: sig.tone)
        let offset = ((mappedMedian - median) * scene.weight / 0.004).rounded() * 0.004
        guard abs(offset) > 1e-9 else { return sig }
        var s = sig
        // 섀도 테이퍼: 균일 오프셋이 paper-black 토우 영역까지 끌어내리면 저키 장면에서
        // 0 끝 빈이 폭발한다(히스토그램 양끝 계약). 토우 위(≥0.25)만 온전히 앵커하고
        // 0.05 아래는 identity 로 되돌린다 — 평탄/흐린 장면의 median(밝은 대역)은 영향 없다.
        s.tone = zip(sig.toneXs, sig.tone).map { x, y in
            clamp(y - offset * smoothstep(0.05, 0.25, x), 0.002, 0.998)
        }
        return s
    }

    static func apply(
        to image: CIImage,
        signature sig: Signature,
        target _: DevelopTarget,
        monochrome: Bool = false,
        positive _: Bool = false
    ) -> CIImage {
        let extent = image.extent

        // ── 0. 흑백은 먼저 luma 로 붕괴한다(입력의 잔여 색 노이즈/베이스 틴트 제거).
        //    실기 틴트(neutralBins)는 여기서 적용하지 않는다 — 흑백은 그레인 색 얼룩 때문에
        //    PostPipeline 이 마지막에 강제 중립화하므로, 틴트는 그 뒤 applyMonochromeTint 가
        //    얹는다(여기서 적용하면 이중 비용 + 어차피 중립화로 소실).
        var img = image
        var cubeSig = sig
        if monochrome {
            let luma = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": luma,
                "inputGVector": luma,
                "inputBVector": luma,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]).cropped(to: extent)
            cubeSig.neutralBins = []
        }

        // ── 1. 시그니처 3D LUT(감마 도메인): 톤 커브 + 중립축 드리프트 + hue 시그니처.
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

        // 공개된 장치 설명은 scene-adaptive proprietary 처리의 존재만 보여 주며, 현재 번들
        // 프로파일에는 로컬 knee/강도나 출력 통계→필터 반경/강도 캘리브레이션이 없다.
        // 따라서 장치 이름만으로 장면 적응 톤·샤프닝·그레인 필터를 추가하지 않는다. 적용되는
        // 캐릭터는 위 LUT의 직접 측정 tone/neutral/hue와 provenance가 확인된 chroma 비뿐이다.
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
