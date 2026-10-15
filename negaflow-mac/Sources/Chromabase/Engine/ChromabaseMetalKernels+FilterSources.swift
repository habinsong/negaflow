import CoreImage

// 스캐너 타겟 질감·채도, 노이즈 제거, 가이디드 필터 커널.
// 커널마다 독립 Metal 라이브러리로 컴파일된다(ChromabaseMetalKernels 참고).
extension ChromabaseMetalKernels {
    static let filterKernelSources: [MetalKernelSource] = [
        MetalKernelSource(name: "scannerLowSatChroma", body: """
    [[stitchable]] float4 scannerLowSatChroma(coreimage::sample_t src, coreimage::sample_t blur) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float by = dot(blur.rgb, ycoef);
        float3 chroma = src.rgb - float3(y);
        float3 blurredChroma = blur.rgb - float3(by);
        float c = length(chroma);
        float lowSat = 1.0 - smoothstep(0.035, 0.160, c);
        float midHigh = smoothstep(0.24, 0.58, y);
        float magenta = smoothstep(0.006, 0.080, (src.r + src.b) * 0.5 - src.g);
        float amount = lowSat * midHigh * (0.38 + 0.42 * magenta);
        float3 mixedChroma = mix(chroma, blurredChroma, amount);
        mixedChroma = mix(mixedChroma, mixedChroma * 0.42, lowSat * magenta * 0.48);
        float3 rgb = clamp(float3(y) + mixedChroma, float3(0.0), float3(1.0));
        return float4(rgb, src.a);
    }
    """),
        MetalKernelSource(name: "scannerMidtoneChroma", body: """
    [[stitchable]] float4 scannerMidtoneChroma(
        coreimage::sample_t src,
        coreimage::sample_t smallGuide,
        coreimage::sample_t largeGuide,
        float profileStrength
    ) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float3 chroma = src.rgb - float3(y);
        float3 smallChroma = smallGuide.rgb - float3(0.5);
        smallChroma -= float3(dot(smallChroma, ycoef));
        float3 largeChroma = largeGuide.rgb - float3(0.5);
        largeChroma -= float3(dot(largeChroma, ycoef));

        float shadow = 1.0 - smoothstep(0.10, 0.34, y);
        float midtone = smoothstep(0.25, 0.47, y) * (1.0 - smoothstep(0.82, 0.94, y));
        float toneWeight = clamp(shadow * 1.10 + midtone * 0.78, 0.0, 1.0);
        float saturation = length(chroma);

        float lowMidChroma = smoothstep(0.018, 0.080, saturation) * (1.0 - smoothstep(0.180, 0.330, saturation));
        float vividGuard = 1.0 - smoothstep(0.150, 0.300, saturation);
        float warmPurple = smoothstep(0.015, 0.120, max(src.r - src.g, (src.r + src.b) * 0.5 - src.g));
        float yellowGreen = smoothstep(0.018, 0.110, max(src.g - src.b, (src.r + src.g) * 0.5 - src.b));
        float colorAxis = max(warmPurple, yellowGreen);

        float3 fineResidual = chroma - smallChroma;
        float3 coarseResidual = smallChroma - largeChroma;
        float fineSignal = smoothstep(0.006, 0.052, length(fineResidual));
        float coarseSignal = smoothstep(0.006, 0.044, length(coarseResidual));

        float fineGate = max(lowMidChroma, fineSignal * 0.65);
        float fineAmount = toneWeight * fineGate * vividGuard *
            (0.18 + 0.50 * profileStrength + 0.30 * fineSignal + 0.18 * colorAxis);
        float coarseAmount = toneWeight * vividGuard *
            (0.05 + 0.22 * profileStrength + 0.48 * coarseSignal * max(colorAxis, lowMidChroma));

        float3 mixedChroma = chroma
            - fineResidual * clamp(fineAmount, 0.0, 0.86)
            - coarseResidual * clamp(coarseAmount, 0.0, 0.62);

        float axis = toneWeight * warmPurple * vividGuard * (0.55 + 0.45 * profileStrength);
        mixedChroma.r *= 1.0 - axis * 0.155;
        mixedChroma.b *= 1.0 - axis * 0.190;
        float3 rgb = clamp(float3(y) + mixedChroma, float3(0.0), float3(1.0));
        return float4(rgb, src.a);
    }
    """),
        MetalKernelSource(name: "filmScanShrink", body: """
    // 사용자 노이즈 제거 — 다중 스케일 수축(wavelet-style coring) + median 임펄스 교체.
    // 다중 스케일 웨이블릿 coring + median 임펄스 교체(공개된 신호처리 기법)의 자체 구성.
    //   • 입력은 감마 리프트된 도메인(x^0.45) — 암부 노이즈 진폭이 톤 전체에서 균일해진다.
    //   • luma/chroma 분리 후 가우시안 피라미드 차분(detail band)으로 분해하고,
    //     각 band에서 노이즈 크기 이하의 계수만 0으로 수축(coring). 큰 계수(엣지/디테일)는
    //     그대로 유지하고, base band(저주파 평균 색)는 절대 건드리지 않으므로
    //     평균 채도/색은 구조적으로 보존된다(블러/탈색 없음).
    //   • 고립 임펄스(흰 점·색 점)는 coring이 엣지로 오인해 남기므로 3x3 median 교체로 별도
    //     처리하되, med3≈med5(주변 균질)일 때만 적용해 얇은 실제 구조를 보호한다.
    [[stitchable]] float4 filmScanShrink(
        coreimage::sample_t src,
        coreimage::sample_t med3,   // 3x3 median
        coreimage::sample_t med5,   // median 두 번(≈5x5)
        coreimage::sample_t g1,     // fine blur
        coreimage::sample_t g2,
        coreimage::sample_t g3,     // coarse blur(base). 더 큰 스케일은 base 색 번짐(경계 밖
                                    // 장거리 bleed)이 구조 가드 범위를 벗어나므로 두지 않는다.
        float2 thresholds,          // (lumaT, chromaT) — 감마 도메인 coring 임계(축 반영됨)
        float2 impulse,             // (impLumaT, impChromaT)
        float4 opts,                // (bw, shadowBoost×dtScale, highlightChroma, highlightLumaProtect)
        float4 axes                 // (dtScale, detailScale, grainProtect, 예약)
    ) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y0 = dot(src.rgb, ycoef);
        float ym3 = dot(med3.rgb, ycoef);
        float ym5 = dot(med5.rgb, ycoef);
        float y1 = dot(g1.rgb, ycoef);
        float y2 = dot(g2.rgb, ycoef);
        float y3 = dot(g3.rgb, ycoef);
        float3 c0 = src.rgb - float3(y0);
        float3 cm3 = med3.rgb - float3(ym3);
        float3 c1 = g1.rgb - float3(y1);
        float3 c2 = g2.rgb - float3(y2);
        float3 c3 = g3.rgb - float3(y3);

        // ── 0) 톤 가중치(감마 도메인 base luma 기준). grain 보호 존은 필름 grain 가시성이
        //    최대인 미드톤(RMS 입상성은 미드톤에서 두드러지고, 암부는 스캔 노이즈가 지배,
        //    클리핑부는 자체 보호가 있다) — dark-tone 축과 겹치지 않아 두 축이 직교한다.
        //    dark-tone 대역은 photometric 렌더(적정 미드 = sRGB 0.46) 기준 — 과거 경계
        //    (0.30~0.58)는 옛 밝은 렌더 좌표라 미드가 마스크에 ~35% 새어들었다(2026-07-18).
        float shadow = 1.0 - smoothstep(0.16, 0.42, y3);
        float nearClip = smoothstep(0.88, 0.97, y3);
        float grainZone = smoothstep(0.30, 0.50, y3) * (1.0 - smoothstep(0.75, 0.92, y3));
        float grainW = axes.z * grainZone;

        // ── 1) 임펄스 교체(고립 outlier만). grain 보호 시 luma 임펄스 교체도 같이 완화해
        //    거친 grain 낱알이 median으로 눌리는 것을 막는다(무채색 질감 보존).
        //    chroma 임펄스(색 점)는 grain이 아니므로 유지.
        float consistency = 1.0 - smoothstep(0.015, 0.055, abs(ym3 - ym5));
        float impLumaW = smoothstep(impulse.x, impulse.x * 1.9, abs(y0 - ym3)) * consistency
            * (1.0 - 0.85 * grainW);
        float yFixed = mix(y0, ym3, min(impLumaW, 0.92));
        float impChromaW = smoothstep(impulse.y, impulse.y * 1.9, length(c0 - cm3)) * consistency;
        float3 cFixed = mix(c0, cm3, min(impChromaW, 0.92));

        // ── 2) 톤별 임계: 암부/중간톤 강화(dark-tone 축이 luma·chroma 모두 스케일).
        //    클리핑 직전은 luma 디테일을 보호하되(필름별 protect), 네거티브 계열의
        //    클리핑부 색 얼룩은 chroma 정리를 강화. grain 보호는 미드톤 luma 임계만 축소
        //    — chroma coring은 그대로라 색 반점 제거는 유지된다.
        float lumaT = thresholds.x * (1.0 + opts.y * shadow) * (1.0 - opts.w * nearClip);
        float chromaT = thresholds.y * (1.0 + 0.35 * axes.x * shadow + opts.z * nearClip);
        lumaT *= 1.0 - 0.95 * grainW;
        // detail 축(axes.y = 1.5 − detail): "디테일로 인정할 크기"의 문턱(디테일
        // 대응). luma 임계를 전역 스케일해 detail↑이면 더 작은 질감까지 통과시킨다.
        // chroma는 chroma 축이 담당하므로 여기서는 luma만 조절해 축 간 간섭을 막는다.
        lumaT *= axes.y;

        // ── 2.5) 구조 적응 가드: 가우시안 피라미드는 엣지 비인식이라 강한 경계 근처의
        //    coarse band 계수가 임계 크기와 겹친다 — 그대로 coring하면 엣지 약화·경계 색
        //    번짐·인접 실색 탈색이 생긴다. 대역 제한 gradient(|y1−y3|, |c1−c3|)는 평탄
        //    노이즈에서는 블러로 바닥(≈0.4σ)에 붙고 구조에서만 커지므로, 구조 위에서 임계를
        //    축소해 계수를 통과시킨다(edge-adaptive shrinkage). detail 축(axes.y)이 발동
        //    지점을 조절: 작을수록(detail↑) 더 작은 구조부터 보호한다.
        float lumaStruct = abs(y1 - y3);
        float chromaStruct = length(c1 - c3);
        lumaT *= 1.0 - 0.90 * smoothstep(0.018 * axes.y, 0.055 * axes.y, lumaStruct + 0.5 * chromaStruct);
        chromaT *= 1.0 - 0.93 * smoothstep(0.045 * axes.y, 0.120 * axes.y, chromaStruct + 0.5 * lumaStruct);

        // ── 3) coring: |계수| < 임계 → 0(노이즈), 임계 위(엣지/디테일) → 유지.
        //    soft-threshold와 달리 큰 계수의 크기를 깎지 않아 엣지 대비 손실이 없다.
        //    band 임계는 거친 스케일일수록 축소(백색 노이즈 에너지 감쇠). chroma는 색 얼룩
        //    (mottle)이 중간 주파수까지 상관되므로 luma보다 완만하게 줄인다.
        float dy1 = yFixed - y1;
        float dy2 = y1 - y2;
        float dy3 = y2 - y3;
        // 최상위 luma band는 대부분 실제 구조(넓은 톤 변화)라 아주 약하게만 수축한다.
        float outY = y3
            + dy3 * smoothstep(0.55 * lumaT * 0.10, 1.5 * lumaT * 0.10, abs(dy3))
            + dy2 * smoothstep(0.55 * lumaT * 0.55, 1.5 * lumaT * 0.55, abs(dy2))
            + dy1 * smoothstep(0.55 * lumaT, 1.5 * lumaT, abs(dy1));

        float3 outC;
        if (opts.x > 0.5) {
            // B&W 필름: 파이프라인 끝 그레이스케일 변환이 chroma를 제거하므로 건드리지 않는다.
            outC = c0;
        } else {
            float3 dc1 = cFixed - c1;
            float3 dc2 = c1 - c2;
            float3 dc3 = c2 - c3;
            outC = c3
                + dc3 * smoothstep(0.55 * chromaT * 0.45, 1.5 * chromaT * 0.45, length(dc3))
                + dc2 * smoothstep(0.55 * chromaT * 0.80, 1.5 * chromaT * 0.80, length(dc2))
                + dc1 * smoothstep(0.55 * chromaT, 1.5 * chromaT, length(dc1));
        }

        return float4(clamp(float3(outY) + outC, float3(0.0), float3(1.0)), src.a);
    }
    """),
        MetalKernelSource(name: "gfProduct", body: """
    // ── Guided filter (He et al.) 구성 요소 — FilmScanDenoise의 엣지 인식 coarse base와
    // ScannerNoiseReduction의 guidedChroma가 공유한다.
    // CIGuidedFilter는 guide/epsilon 파라미터가 반영되지 않아(프로브 검증) 직접 구현한다.
    // 창 회귀: a = cov(I,P)/(var(I)+eps), b = mean(P) - a*mean(I), base = mean(a)*I + mean(b).
    // guide I는 단일 채널 gray(rgb 동일값).
    [[stitchable]] float4 gfProduct(coreimage::sample_t a, coreimage::sample_t b) {
        return float4(a.r * b.rgb, 1.0);
    }
    """),
        MetalKernelSource(name: "gfCoeffA", body: """
    [[stitchable]] float4 gfCoeffA(
        coreimage::sample_t mIP,
        coreimage::sample_t mII,
        coreimage::sample_t mI,
        coreimage::sample_t mP,
        float epsilon
    ) {
        float3 cov = mIP.rgb - mI.rgb * mP.rgb;
        float3 var_ = max(mII.rgb - mI.rgb * mI.rgb, float3(0.0));
        return float4(cov / (var_ + float3(epsilon)), 1.0);
    }
    """),
        MetalKernelSource(name: "gfCoeffB", body: """
    [[stitchable]] float4 gfCoeffB(coreimage::sample_t a, coreimage::sample_t mI, coreimage::sample_t mP) {
        return float4(mP.rgb - a.rgb * mI.rgb, 1.0);
    }
    """),
        MetalKernelSource(name: "gfApply", body: """
    [[stitchable]] float4 gfApply(coreimage::sample_t mA, coreimage::sample_t mB, coreimage::sample_t guide, coreimage::sample_t src) {
        return float4(clamp(mA.rgb * guide.rgb + mB.rgb, float3(0.0), float3(1.0)), src.a);
    }
    """),
        MetalKernelSource(name: "noritsuTexture", body: """
    // ScannerTargetGrade의 3D LUT는 측정된 SDR cube domain [0,1] 안에서만 유효하다.
    // 입력이 그 범위를 벗어나면 CIColorCube가 먼저 endpoint로 clamp하므로, 별도 결합 단계에서
    // 원래 extended working value를 복원한다. 경계 2%는 부드럽게 항등으로 테이퍼해 이음선을
    // 만들지 않으며, 측정되지 않은 영역을 장치 특성이라고 외삽하지 않는다.
    // NORITSU 문서 질감: 감마(장치 출력) 도메인 luminance USM. blurred = 가우시안 저역.
    // 가드: (1) 감마 undershoot 플로어(원 luma 의 45%) — 검정 크러시/0-빈 방지,
    // (2) 유닛 상한 — 실기 스캔 파일도 [0,1] 을 넘지 않는다, (3) 측정 큐브 밖(extended)
    // 픽셀은 통과(확장값 보존 계약), (4) 채널이 상한을 넘으면 공통 축소로 hue 를 보존한다.
    [[stitchable]] float4 noritsuTexture(
        coreimage::sample_t src,
        coreimage::sample_t blurred,
        float amount
    ) {
        float3 s = src.rgb;
        float lo = min(s.r, min(s.g, s.b));
        float hi = max(s.r, max(s.g, s.b));
        if (lo < 0.0 || hi > 1.0) { return src; }
        float lumaO = dot(s, float3(0.2126, 0.7152, 0.0722));
        if (lumaO <= 1e-5) { return src; }
        float3 b = clamp(blurred.rgb, float3(0.0), float3(1.0));
        float lumaB = dot(b, float3(0.2126, 0.7152, 0.0722));
        float yO = srgbEncodeLuma(lumaO);
        float yB = srgbEncodeLuma(lumaB);
        // 플로어: 비율(0.45×)만으로는 1~2 코드 픽셀이 0 으로 반올림된다(0 끝 빈 계약 위반).
        // 절대 플로어(≈2/255)를 더해, 이미 그보다 어두운 픽셀은 아예 어두워지지 않게 한다.
        float floorY = max(yO * 0.45, min(yO, 0.008));
        float yN = clamp(yO + amount * (yO - yB), floorY, 1.0);
        float gain = srgbDecodeLuma(yN) / lumaO;
        float3 outRGB = s * gain;
        float mx = max(outRGB.r, max(outRGB.g, outRGB.b));
        if (mx > 1.0) { outRGB *= 1.0 / mx; }
        return float4(outRGB, src.a);
    }
    """),
        MetalKernelSource(name: "boundedRelativeGrade", body: """
    [[stitchable]] float4 boundedRelativeGrade(
        coreimage::sample_t src,
        coreimage::sample_t graded
    ) {
        // src는 Core Image working-linear 좌표지만 LUT와 0.02/0.98 경계는 sRGB code
        // 좌표다. 같은 domain으로 옮긴 뒤 taper해야 linear 0.01(sRGB≈0.10)이 잘못
        // 반감되지 않는다.
        float3 cubeRGB = float3(
            srgbEncodeLuma(src.r),
            srgbEncodeLuma(src.g),
            srgbEncodeLuma(src.b)
        );
        float lo = min(cubeRGB.r, min(cubeRGB.g, cubeRGB.b));
        float hi = max(cubeRGB.r, max(cubeRGB.g, cubeRGB.b));
        float domainWeight = smoothstep(0.0, 0.02, lo)
            * (1.0 - smoothstep(0.98, 1.0, hi));
        return float4(mix(src.rgb, graded.rgb, domainWeight), src.a);
    }
    """),
    ]
}
