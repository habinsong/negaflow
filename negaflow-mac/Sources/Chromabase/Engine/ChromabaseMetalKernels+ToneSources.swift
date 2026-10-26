import CoreImage

// 톤·색 조정, 반전, 표시 경계 커널.
// 커널마다 독립 Metal 라이브러리로 컴파일된다(ChromabaseMetalKernels 참고).
extension ChromabaseMetalKernels {
    static let toneKernelSources: [MetalKernelSource] = [
        MetalKernelSource(name: "negativeLinear", body: """
    [[stitchable]] float4 negativeLinear(coreimage::sample_t src, float3 base,
                                        float3 scale, float grayDensity, float toeDensity, float knee) {
        float3 density = log10(base / max(src.rgb, 1e-5)) * scale;
        float3 straight = 0.18 * pow(10.0, density - grayDensity);
        float3 toe = sign(density) * knee * pow(max(abs(density) / toeDensity, 1e-12), toeDensity * log(10.0));
        return float4(select(straight, toe, density < float3(toeDensity)), src.a);
    }
    """),
        MetalKernelSource(name: "negativeOutputTone", body: """
    [[stitchable]] float4 negativeOutputTone(coreimage::sample_t src, float gain,
                                            float shadowKnee, float highlightKnee, float black) {
        float3 rgb = max(src.rgb * gain, float3(0.0));
        float3 distance = 1.0 - rgb / shadowKnee;
        float3 toe = rgb + black * distance * distance;
        float room = 1.0 - highlightKnee;
        float3 delta = max(rgb - highlightKnee, float3(0.0));
        float3 shoulder = highlightKnee + room * delta / (delta + room);
        float3 mapped = select(rgb, toe, rgb < float3(shadowKnee));
        mapped = select(mapped, shoulder, rgb > float3(highlightKnee));
        return float4(mapped, src.a);
    }
    """),
        MetalKernelSource(name: "colorMixerHSL", body: """
    // Color Mixer (HSL) — 8색 각각 hue/sat/lum. hueA/B = 빨강~자홍 8밴드를 float4 2개로 묶음.
    [[stitchable]] float4 colorMixerHSL(
        coreimage::sample_t src,
        float4 hueA, float4 hueB, float4 satA, float4 satB, float4 lumA, float4 lumB
    ) {
        float3 hsl = rgb2hsl(clamp(src.rgb, 0.0, 1.0));
        float centers[8] = {0.0, 0.083333, 0.166667, 0.333333, 0.5, 0.666667, 0.75, 0.833333};
        float hueAdj[8] = {hueA.x, hueA.y, hueA.z, hueA.w, hueB.x, hueB.y, hueB.z, hueB.w};
        float satAdj[8] = {satA.x, satA.y, satA.z, satA.w, satB.x, satB.y, satB.z, satB.w};
        float lumAdj[8] = {lumA.x, lumA.y, lumA.z, lumA.w, lumB.x, lumB.y, lumB.z, lumB.w};
        float bw = 0.14;
        float wsum = 0.0, hueShift = 0.0, satF = 0.0, lumF = 0.0;
        for (int i = 0; i < 8; i++) {
            float dd = abs(hsl.x - centers[i]);
            dd = min(dd, 1.0 - dd);
            float w = max(0.0, 1.0 - dd / bw);
            wsum += w; hueShift += w * hueAdj[i]; satF += w * satAdj[i]; lumF += w * lumAdj[i];
        }
        if (wsum > 1e-4) { hueShift /= wsum; satF /= wsum; lumF /= wsum; }
        float gate = smoothstep(0.04, 0.18, hsl.y);   // 무채색(회색)은 hue 미정 → 보호
        hsl.x = fract(hsl.x + hueShift * 0.0833 * gate + 1.0);  // ±30°
        hsl.y = clamp(hsl.y * (1.0 + satF * gate), 0.0, 1.0);
        hsl.z = clamp(hsl.z + lumF * 0.16 * gate, 0.0, 1.0);
        return float4(clamp(hsl2rgb(hsl), 0.0, 1.0), src.a);
    }
    """),
        MetalKernelSource(name: "colorGrade", body: """
    // Color Grading — 어두운/중간/밝은 영역에 색조(chroma 주입)+광도. shadow.rgb=hueColor*sat,
    // shadow.a=lum. bb=(blending, balance).
    [[stitchable]] float4 colorGrade(
        coreimage::sample_t src,
        float4 shadow, float4 mid, float4 high, float2 bb
    ) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float blending = bb.x, balance = bb.y;
        float pivot = clamp(0.5 + balance * 0.30, 0.15, 0.85);
        float wdt = mix(0.10, 0.50, blending);
        float sh = 1.0 - smoothstep(pivot - wdt, pivot + wdt, y);
        float hi = smoothstep(pivot - wdt, pivot + wdt, y);
        float md = clamp(1.0 - abs(y - pivot) / max(wdt, 0.001), 0.0, 1.0);
        float3 shc = shadow.rgb - dot(shadow.rgb, ycoef);
        float3 mdc = mid.rgb - dot(mid.rgb, ycoef);
        float3 hic = high.rgb - dot(high.rgb, ycoef);
        float3 rgb = src.rgb;
        rgb += sh * (shc * 0.75 + shadow.a * 0.22);
        rgb += md * (mdc * 0.75 + mid.a * 0.22);
        rgb += hi * (hic * 0.75 + high.a * 0.22);
        return float4(clamp(rgb, 0.0, 1.0), src.a);
    }
    """),
        MetalKernelSource(name: "bwToning", body: """
    [[stitchable]] float4 bwToning(coreimage::sample_t src, float3 shadowTint, float3 highlightTint, float2 control) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = clamp(dot(src.rgb, ycoef), 0.0, 1.0);
        float strength = clamp(control.x, 0.0, 1.0);
        float mode = control.y;

        float shadowReach = mix(0.68, 0.92, mode);
        float highlightReach = mix(0.38, 0.76, mode);
        float shadowWeight = (1.0 - smoothstep(0.18, shadowReach, y));
        float highlightWeight = smoothstep(1.0 - highlightReach, 0.98, y);
        float crossover = smoothstep(0.22, 0.86, y);
        float3 tint = mix(shadowTint, highlightTint, crossover);

        float tintY = max(dot(tint, ycoef), 0.001);
        float3 toned = y * (tint / tintY);
        float toneMask = clamp(shadowWeight * mix(0.95, 0.68, mode) + highlightWeight * mix(0.30, 0.72, mode), 0.0, 1.0);
        float amount = strength * mix(0.18, 0.36, mode) * toneMask;

        float density = mix(
            1.0 - 0.060 * strength * shadowWeight,
            1.0 - 0.026 * strength * smoothstep(0.36, 0.92, y),
            mode
        );
        float3 rgb = mix(float3(y), toned, amount) * density;
        return float4(clamp(rgb, 0.0, 1.0), src.a);
    }
    """),
        MetalKernelSource(name: "calibrationPrimaries", body: """
    // Calibration — R(0°)/G(120°)/B(240°) primary 의 hue 회전 + saturation 스케일(넓은 밴드).
    [[stitchable]] float4 calibrationPrimaries(coreimage::sample_t src, float3 hue, float3 sat) {
        float3 hsl = rgb2hsl(clamp(src.rgb, 0.0, 1.0));
        float centers[3] = {0.0, 0.333333, 0.666667};
        float hueAdj[3] = {hue.x, hue.y, hue.z};
        float satAdj[3] = {sat.x, sat.y, sat.z};
        float bw = 0.22;
        float wsum = 0.0, hs = 0.0, sf = 0.0;
        for (int i = 0; i < 3; i++) {
            float dd = abs(hsl.x - centers[i]);
            dd = min(dd, 1.0 - dd);
            float w = max(0.0, 1.0 - dd / bw);
            wsum += w; hs += w * hueAdj[i]; sf += w * satAdj[i];
        }
        if (wsum > 1e-4) { hs /= wsum; sf /= wsum; }
        float gate = smoothstep(0.03, 0.16, hsl.y);
        hsl.x = fract(hsl.x + hs * 0.08 * gate + 1.0);
        hsl.y = clamp(hsl.y * (1.0 + sf * gate), 0.0, 1.0);
        return float4(clamp(hsl2rgb(hsl), 0.0, 1.0), src.a);
    }
    """),
        MetalKernelSource(name: "channelPowerGain", body: """
    // 채널별 거듭제곱·게인(자동 색상). c' = gain·c^exponent — 중립축 적합(ln c = α + β·ln Ȳ)을
    // 정확히 뒤집는다. 0 이하 값은 그대로 둔다(거듭제곱이 정의되지 않는다).
    [[stitchable]] float4 channelPowerGain(coreimage::sample_t src, float3 exponent, float3 gain) {
        float3 c = max(src.rgb, float3(0.0));
        float3 corrected = gain * pow(c, exponent);
        return float4(select(src.rgb, corrected, src.rgb > float3(0.0)), src.a);
    }
    """),
        MetalKernelSource(name: "exposureShoulder", body: """
    // 노출 EV>0. 확산 화이트(knee) 아래는 정확히 gain 배, 그 위 휘도는 1.0 에 점근하는 지수
    // 숄더로 접는다(C1 연속). blend 는 0(EV 0, 항등)에서 1(마스터 헤드룸 소진)로 오른다.
    // 휘도 비로 RGB 를 함께 늘려 색비(화이트밸런스)를 유지하고, gamut 초과 채도는 출력 경계의
    // hue 보존 soft-clip 이 맡는다. EV<=0 은 이 커널을 쓰지 않는다(순수 선형 곱).
    [[stitchable]] float4 exposureShoulder(coreimage::sample_t src, float gain, float knee, float blend) {
        float3 rgb = src.rgb * gain;
        float y = dot(rgb, float3(0.2126, 0.7152, 0.0722));
        if (y <= knee) { return float4(rgb, src.a); }
        float room = 1.0 - knee;
        float shoulder = 1.0 - room * exp(-(y - knee) / room);
        return float4(rgb * (mix(y, shoulder, blend) / y), src.a);
    }
    """),
        MetalKernelSource(name: "basicTone", body: """
    // Basic Tone — photometric 렌더(적정 미드 = linear 0.18 = sRGB 0.46) 기준.
    // 마스크·델타·대비 피벗은 **sRGB 감마 도메인**(지각 균등)에서 정의하고, 목표 luma 를
    // linear 로 되돌려 `withLuma` 로 싣는다(밝힘은 additive, 어둡힘은 채널비 보존).
    // 2026-07-18 재캘리브레이션: 과거 마스크는 옛 로그-직결 렌더(미드 linear 0.5~0.6)의
    // linear 좌표라, photometric 미드(0.18)에서 Shadows 마스크 = 1.0, Blacks = 0.65 로
    // 미드를 통째로 침범하고 Contrast 피벗(linear 0.5 = sRGB 0.74)이 미드를 일방적으로
    // 눌렀다. AutoAdjust.autoTone 의 역산은 이 마스크·계수와 반드시 동기 유지.
    [[stitchable]] float4 basicTone(
        coreimage::sample_t src,
        float contrastAmount,
        float densityAmount,
        float highlightAmount,
        float shadowAmount,
        float whitesAmount,
        float blacksAmount
    ) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float3 sourceRGB = toneSafeUnitRGB(src.rgb);
        float y = dot(sourceRGB, ycoef);
        float gy = srgbEncodeLuma(clamp(y, 0.0, 1.0));
        float target = gy;

        // Contrast: photometric 미드(sRGB 0.46) 피벗의 파워 대비 — 끝점(0/1)·피벗 고정.
        // 양수 지수 2^(c·0.9)(최대 1.87), 음수 2^(c·0.7)(최소 0.62 — 소프트). 음수는 지수<1 이
        // 검정 부근을 들어올리므로 저역 가드(smoothstep 0.12~0.30)로 절대 검정~딥섀도를
        // 원본에 앵커한다(계약: Contrast −1 이 절대 검정을 회색으로 띄우면 안 된다).
        float contrast = clamp(contrastAmount, -1.0, 1.0);
        if (abs(contrast) > 1e-4) {
            float pivot = 0.46;
            float e = pow(2.0, contrast * (contrast > 0.0 ? 0.9 : 0.7));
            float curved = target < pivot
                ? pivot * pow(target / pivot, e)
                : 1.0 - (1.0 - pivot) * pow((1.0 - target) / (1.0 - pivot), e);
            float blend = contrast > 0.0 ? 1.0 : smoothstep(0.12, 0.30, target);
            target = mix(target, curved, blend);
        }

        // Density: 미드톤 농도(+ 가 어둡게) — 미드(0.46) 중심 대역(full 0.36~0.58).
        float midMask = smoothstep(0.18, 0.36, gy) * (1.0 - smoothstep(0.58, 0.76, gy));
        target -= densityAmount * 0.10 * midMask;

        // Highlights: 일반 현상 도구 규약 — 값을 올리면 명부가 밝아진다(내리면 recovery).
        float highlightMask = smoothstep(0.55, 0.80, gy);
        target += highlightAmount * 0.10 * highlightMask;

        // Shadows: 가시 암부(sRGB 0.08~0.32 full)를 들어올리되 절대 검정(<0.02)은 앵커,
        // 미드(0.46)에는 도달 전에 0 으로 테이퍼 — 미드 침범 금지.
        float shadowMask = smoothstep(0.02, 0.08, gy) * (1.0 - smoothstep(0.32, 0.46, gy));
        target += shadowAmount * 0.10 * shadowMask;

        // Whites: 최상단 백점 영역. 범위는 DevelopToneRange.whites(±2) — 계수/마스크는 그대로라
        // ±1 구간 결과가 이전과 동일하고, 확장 구간만 같은 기울기로 이어진다.
        float whiteMask = smoothstep(0.68, 0.92, gy);
        target += clamp(whitesAmount, -2.0, 2.0) * 0.12 * whiteMask;

        // Blacks: 흑점 제어 — 순검정 바로 위 띠(full 0.03~0.14), y=0 앵커. 범위 ±2.
        float blackMask = smoothstep(0.0, 0.03, gy) * (1.0 - smoothstep(0.14, 0.30, gy));
        target += clamp(blacksAmount, -2.0, 2.0) * 0.06 * blackMask;

        float newY = srgbDecodeLuma(clamp(target, 0.0, 1.0));
        float3 rgb = withLuma(sourceRGB, y, newY);
        return float4(clamp(rgb, float3(0.0), float3(1.0)), src.a);
    }
    """),
        MetalKernelSource(name: "parametricToneCurve", body: """
    [[stitchable]] float4 parametricToneCurve(
        coreimage::sample_t src,
        float highlightsAmount,
        float lightsAmount,
        float darksAmount,
        float shadowsAmount,
        float shadowLow,
        float shadowHigh,
        float darkLow,
        float darkHigh,
        float lightLow,
        float lightHigh,
        float highlightLow,
        float highlightHigh
    ) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float3 sourceRGB = toneSafeUnitRGB(src.rgb);
        float y = dot(sourceRGB, ycoef);

        // 절대 검정(y≈0)은 앵커로 고정해, Shadows를 올릴 때 바닥 전체가 회색으로 뜨는("붕 뜸")
        // 현상을 막는다. 가시 암부(y>0.045)에만 작용.
        float shadowMask = (1.0 - smoothstep(shadowLow, shadowHigh, y)) * smoothstep(0.0, 0.045, y);
        float darkMask = smoothstep(shadowLow, shadowHigh, y) * (1.0 - smoothstep(darkLow, darkHigh, y));
        float lightMask = smoothstep(darkLow, darkHigh, y) * (1.0 - smoothstep(lightLow, lightHigh, y));
        float highlightMask = smoothstep(highlightLow, highlightHigh, y);

        float delta =
            shadowsAmount * 0.160 * shadowMask +
            darksAmount * 0.155 * darkMask +
            lightsAmount * 0.165 * lightMask +
            highlightsAmount * 0.150 * highlightMask;
        float target = clamp(y + delta, 0.0, 1.0);
        float3 rgb = withLuma(sourceRGB, y, target);
        return float4(clamp(rgb, float3(0.0), float3(1.0)), src.a);
    }
    """),
        MetalKernelSource(name: "filmGrain", body: """
    // 필름 그레인 — zero-mean 휘도가중 노이즈. 기존 LinearDodge 그레인은 DC 바이어스가 있어
    // 암부를 통째로 밝게 띄웠다(사용자: "암부를 하얗게 붕 띄움"). 여기선 noise.r-0.5 로 평균 0을
    // 보장하고, 그레인이 미드톤에서 최대·순검정/순백 부근에서 약해지도록 휘도 가중(w)을 곱한다.
    [[stitchable]] float4 filmGrain(coreimage::sample_t src, coreimage::sample_t noise, float amount) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float w = smoothstep(0.02, 0.16, y) * (1.0 - smoothstep(0.82, 1.0, y));
        float g = (noise.r - 0.5) * amount * w;
        return float4(clamp(src.rgb + float3(g), float3(0.0), float3(1.0)), src.a);
    }
    """),
        MetalKernelSource(name: "gamutSoftClip", body: """
    // Constant-hue gamut soft-clip. 채도/톤 부스트가 채널을 [0,1] 밖으로 밀면, 채널별 하드
    // 클립이 채널 비율을 깨뜨려 hue가 틀어진다(명부 노랑, 암부/미드 보라, 채널별 크러시).
    // 대신 luma는 보존한 채 chroma만 줄여(중립으로 desaturate) gamut 안으로 들인다.
    [[stitchable]] float4 gamutSoftClip(coreimage::sample_t src) {
        return float4(toneSafeUnitRGB(src.rgb), src.a);
    }
    """),
        MetalKernelSource(name: "negativeInvert", body: """
    // NegativeInversion 고정 인화 응답(NegativeInversion.swift CPU 참조와 동일).
    // Dmin 정규화 밀도 d 에 H&D 숄더형 단일 해석 곡선을 적용한다:
    //   log10(P) = yCeil − amplitude·exp(−(rate·d)^shape)
    // 장면 percentile을 읽지 않으므로 같은 필름 밀도는 프레임 내용과 무관하게 항상 같은 값이
    // 된다. 베이스보다 밝은 비필름 입력(백라이트/퍼포레이션, 음의 밀도)은 로그 출력 공간에서
    // 토우 점대칭 연속 y(−|d|) = 2·log10(toe) − y(|d|) — 단조 보존, 토우 아래 유한 양수
    // (정확히 0 픽셀·평탄면이 구조적으로 없다 — 히스토그램 0 벽 방지).
    [[stitchable]] float4 negativeInvert(
        coreimage::sample_t src,
        float4 dmin,       // 채널별 베이스 투과율 (w 미사용)
        float4 dmaxNorm,   // 채널별 측정/프리셋/명목 밀도 범위 (w 미사용)
        float4 response    // x=yCeil, y=amplitude, z=rate, w=shape
    ) {
        float3 t = max(src.rgb, 1e-5);
        float3 d = log10(dmin.xyz / t) / max(dmaxNorm.xyz, float3(1e-6));
        // pow(0, shape) 는 fast-math 에서 NaN 위험 — 하한 1e-12 로 같은 극한값을 보장한다.
        float3 arg = pow(max(response.z * abs(d), float3(1e-12)), float3(response.w));
        float3 y = float3(response.x) - response.y * exp(-arg);
        float3 toeY = float3(response.x - response.y);
        float3 mirrored = 2.0 * toeY - y;
        float3 outY = select(mirrored, y, d >= float3(0.0));
        return float4(pow(float3(10.0), outY), src.a);
    }
    """),
        MetalKernelSource(name: "highlightDesaturate", body: """
    // 명부 chroma desaturation (HIGHLIGHT_TONE_REDESIGN.md §5 옵션 C).
    // per-channel 반전/AutoLevels 가 명부에서 채널 비율을 틀어 남긴 "명부 따뜻함"(중립이어야 할
    // 밝은 회색이 R>B 로 노랗게, 측정 R-B≈10~13)을 제거한다. luma 는 보존하고, y 가 startY 위로
    // 갈수록 chroma 를 0(중립 white)으로 수렴시킨다. 이미 채도가 낮은(거의 중립) 명부일수록 강하게
    // 당기되, 채도가 높은 명부(노을·네온 등 의도된 색)는 desat 을 약하게 둬 탈색을 막는다
    // (lowChromaBias: 고채도 보호). 명부에서 rgb 비율을 중립으로 수렴시키는 표준 하이라이트 탈채도.
    [[stitchable]] float4 highlightDesaturate(coreimage::sample_t src, float strength, float startY) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = clamp(dot(src.rgb, ycoef), 0.0, 1.0);
        float3 chroma = src.rgb - float3(y);
        float sat = length(chroma);
        float hiMask = smoothstep(startY, 1.0, y);
        // 고채도(의도된 색)는 보호: 채도가 클수록 desat 약화. 중립 부근(작은 sat)만 강하게 중립화.
        float lowChromaBias = 1.0 - smoothstep(0.06, 0.22, sat);
        float desat = hiMask * strength * lowChromaBias;
        float3 rgb = clamp(float3(y) + chroma * (1.0 - desat), 0.0, 1.0);
        return float4(rgb, src.a);
    }
    """),
        MetalKernelSource(name: "ditherAdd", body: """
    // 8bit 양자화 banding dithering. sRGB 인코딩된 src 에 ±0.5/255(8bit 1스텝 이내) 노이즈를
    // 더한다. noise 는 [0,1] white noise. alpha 는 src 그대로 보존(LinearDodge 의 알파 합성 버그
    // 회피). banding 경계 픽셀만 인접 양자화 스텝으로 분산되고 디테일/평균 톤은 보존된다.
    [[stitchable]] float4 ditherAdd(coreimage::sample_t src, coreimage::sample_t noise) {
        float3 d = (noise.rgb - float3(0.5)) / 255.0;
        return float4(src.rgb + d, src.a);
    }
    """),
        MetalKernelSource(name: "channelClippingOverlay", body: """
    // Preview-only RGB channel clipping overlay. Core Image samples and kernel outputs are
    // premultiplied, so warning colors are multiplied by the overlay opacity before return.
    // A channel exactly at the SDR boundary is clipped by definition (<= 0 or >= 1).
    [[stitchable]] float4 channelClippingOverlay(coreimage::sample_t src) {
        if (src.a <= 1e-6) return float4(0.0);
        float3 rgb = src.rgb / src.a;
        bool shadow = any(rgb <= float3(0.0));
        bool highlight = any(rgb >= float3(1.0));
        if (!shadow && !highlight) return float4(0.0);

        constexpr float opacity = 0.62;
        constexpr float3 shadowColor = float3(0.055, 0.24, 0.82);
        constexpr float3 highlightColor = float3(0.90, 0.07, 0.055);
        constexpr float3 mixedColor = float3(0.64, 0.10, 0.70);
        float3 color = shadow && highlight ? mixedColor : (highlight ? highlightColor : shadowColor);
        return float4(color * opacity, opacity);
    }
    """),
    ]
}
