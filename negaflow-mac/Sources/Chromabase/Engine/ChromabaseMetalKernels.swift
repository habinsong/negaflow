import CoreImage

// allow: SIZE_OK — Metal stitchable kernels compile from one shared Core Image Metal source string; splitting the registry is outside this focused tone fix.
enum ChromabaseMetalKernels {
    static func colorKernel(named name: String) -> CIColorKernel? {
        kernels[name] as? CIColorKernel
    }

    static var availableKernelNames: Set<String> {
        Set(kernels.keys)
    }

    private static let kernels: [String: CIKernel] = {
        do {
            return Dictionary(
                uniqueKeysWithValues: try CIKernel.kernels(withMetalString: source).map { ($0.name, $0) }
            )
        } catch {
            assertionFailure("Failed to compile Chromabase Metal kernels: \(error)")
            return [:]
        }
    }()

    private static let source = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    // ── HSL 헬퍼 (Color Mixer / Calibration 공용) ──
    inline float3 rgb2hsl(float3 c) {
        float maxc = max(c.r, max(c.g, c.b));
        float minc = min(c.r, min(c.g, c.b));
        float l = (maxc + minc) * 0.5;
        float h = 0.0, s = 0.0;
        float d = maxc - minc;
        if (d > 1e-5) {
            s = l > 0.5 ? d / (2.0 - maxc - minc) : d / (maxc + minc);
            if (maxc == c.r)      h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
            else if (maxc == c.g) h = (c.b - c.r) / d + 2.0;
            else                  h = (c.r - c.g) / d + 4.0;
            h /= 6.0;
        }
        return float3(h, s, l);
    }
    inline float hue2rgb(float p, float q, float t) {
        if (t < 0.0) t += 1.0;
        if (t > 1.0) t -= 1.0;
        if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
        if (t < 1.0 / 2.0) return q;
        if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
        return p;
    }
    inline float3 hsl2rgb(float3 hsl) {
        float h = hsl.x, s = hsl.y, l = hsl.z;
        if (s < 1e-5) return float3(l);
        float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
        float p = 2.0 * l - q;
        return float3(hue2rgb(p, q, h + 1.0 / 3.0), hue2rgb(p, q, h), hue2rgb(p, q, h - 1.0 / 3.0));
    }

    // Exposure is scene-linear and can legitimately produce values outside [0, 1]. Tone masks and
    // smoothstep curves below are display-referred, so bring only their input into that domain while
    // preserving luma and hue. Per-channel hard clipping here would create colored highlight bands.
    inline float3 toneSafeUnitRGB(float3 rgb) {
        float y = clamp(dot(rgb, float3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
        float3 chroma = rgb - float3(y);
        float tr = chroma.r > 1e-5 ? (1.0 - y) / chroma.r : (chroma.r < -1e-5 ? (-y) / chroma.r : 1.0);
        float tg = chroma.g > 1e-5 ? (1.0 - y) / chroma.g : (chroma.g < -1e-5 ? (-y) / chroma.g : 1.0);
        float tb = chroma.b > 1e-5 ? (1.0 - y) / chroma.b : (chroma.b < -1e-5 ? (-y) / chroma.b : 1.0);
        float t = clamp(min(1.0, min(tr, min(tg, tb))), 0.0, 1.0);
        return clamp(float3(y) + t * chroma, 0.0, 1.0);
    }

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

    inline float srgbEncodeLuma(float v) {
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1.0 / 2.4) - 0.055;
    }
    inline float srgbDecodeLuma(float v) {
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
    }

    // Basic Tone — photometric 렌더(적정 미드 = linear 0.18 = sRGB 0.46) 기준.
    // 마스크·델타·대비 피벗은 **sRGB 감마 도메인**(지각 균등)에서 정의하고, luma 차이를
    // linear 로 되돌려 additive 로 적용한다(채널 오프셋 보존 — 기존 구조 유지).
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

        // Whites: 최상단 백점 영역.
        float whiteMask = smoothstep(0.68, 0.92, gy);
        target += whitesAmount * 0.12 * whiteMask;

        // Blacks: 흑점 제어 — 순검정 바로 위 띠(full 0.03~0.14), y=0 앵커.
        float blackMask = smoothstep(0.0, 0.03, gy) * (1.0 - smoothstep(0.14, 0.30, gy));
        target += blacksAmount * 0.06 * blackMask;

        float newY = srgbDecodeLuma(clamp(target, 0.0, 1.0));
        float3 rgb = sourceRGB + float3(newY - y);
        return float4(clamp(rgb, float3(0.0), float3(1.0)), src.a);
    }

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
        float3 rgb = sourceRGB + float3(target - y);
        return float4(clamp(rgb, float3(0.0), float3(1.0)), src.a);
    }

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

    // ── Guided filter (He et al.) 구성 요소 — FilmScanDenoise의 엣지 인식 coarse base와
    // ScannerNoiseReduction의 guidedChroma가 공유한다.
    // CIGuidedFilter는 guide/epsilon 파라미터가 반영되지 않아(프로브 검증) 직접 구현한다.
    // 창 회귀: a = cov(I,P)/(var(I)+eps), b = mean(P) - a*mean(I), base = mean(a)*I + mean(b).
    // guide I는 단일 채널 gray(rgb 동일값).
    [[stitchable]] float4 gfProduct(coreimage::sample_t a, coreimage::sample_t b) {
        return float4(a.r * b.rgb, 1.0);
    }

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

    [[stitchable]] float4 gfCoeffB(coreimage::sample_t a, coreimage::sample_t mI, coreimage::sample_t mP) {
        return float4(mP.rgb - a.rgb * mI.rgb, 1.0);
    }

    [[stitchable]] float4 gfApply(coreimage::sample_t mA, coreimage::sample_t mB, coreimage::sample_t guide, coreimage::sample_t src) {
        return float4(clamp(mA.rgb * guide.rgb + mB.rgb, float3(0.0), float3(1.0)), src.a);
    }

    // Constant-hue gamut soft-clip. 채도/톤 부스트가 채널을 [0,1] 밖으로 밀면, 채널별 하드
    // 클립이 채널 비율을 깨뜨려 hue가 틀어진다(명부 노랑, 암부/미드 보라, 채널별 크러시).
    // 대신 luma는 보존한 채 chroma만 줄여(중립으로 desaturate) gamut 안으로 들인다.
    [[stitchable]] float4 gamutSoftClip(coreimage::sample_t src) {
        return float4(toneSafeUnitRGB(src.rgb), src.a);
    }

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

    // 8bit 양자화 banding dithering. sRGB 인코딩된 src 에 ±0.5/255(8bit 1스텝 이내) 노이즈를
    // 더한다. noise 는 [0,1] white noise. alpha 는 src 그대로 보존(LinearDodge 의 알파 합성 버그
    // 회피). banding 경계 픽셀만 인접 양자화 스텝으로 분산되고 디테일/평균 톤은 보존된다.
    [[stitchable]] float4 ditherAdd(coreimage::sample_t src, coreimage::sample_t noise) {
        float3 d = (noise.rgb - float3(0.5)) / 255.0;
        return float4(src.rgb + d, src.a);
    }

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

    // ── 디지털 소스 전용 필름 시뮬레이션 ──
    //
    // 아래 커널들은 isDigitalSource 경로에서만 호출된다. 필름 스캔은 이미 이 물리를 픽셀에
    // 담고 있으므로 같은 응답을 두 번 얹지 않는다.

    /// 부드러운 상한. t≥0 에서 limit 로 단조 수렴하되 t≪limit 구간의 기울기 1을 보존한다.
    /// n 이 작을수록 완만하게 눕는다(= 관용도가 넓은 유제).
    inline float softLimit(float t, float limit, float n) {
        if (limit <= 1e-6) return 0.0;
        float r = max(t, 0.0) / limit;
        return t / pow(1.0 + pow(r, n), 1.0 / n);
    }

    inline float3 softLimit3(float3 t, float limit, float n) {
        return float3(softLimit(t.x, limit, n), softLimit(t.y, limit, n), softLimit(t.z, limit, n));
    }

    // 디스플레이 렌더된 값 → 필름이 받는 노출(scene-linear) 추정.
    // 카메라가 이미 씌운 숄더를 역으로 풀어 명부에 헤드룸을 되돌린다. 클리핑으로 사라진
    // 정보는 복원되지 않으며, 이는 재구성이지 복원이 아니다.
    // p = (a, dmin, scale, _). a/dmin 이 확장 곡선을, scale 이 중간 회색 앵커를 맞춘다.
    [[stitchable]] float4 digitalSceneReconstruct(coreimage::sample_t src, float4 p) {
        float3 v = src.rgb;
        float3 om = float3(1.0) - v;
        float3 denom = 0.5 * (om + sqrt(om * om + 4.0 * p.y * p.y));
        return float4(p.x * v / denom * p.z, src.a);
    }

    // 노출 → 채널별 특성곡선 밀도. 중간 회색(0.18)에서 밀도 0 이 되도록 중심을 맞춘다.
    // polarity +1 = 네거티브(노출↑ → 밀도↑), -1 = 반전.
    // exposureScale 은 장면의 노출 범위를 그 유제의 관용도에 맞춰 옮기는 비율이다. 관용도가
    // 좁은 반전 필름일수록 작아진다 — 좁은 필름에 넓은 장면을 그대로 밀어 넣으면 명부가
    // 곡선 밖으로 나가 계조가 남지 않는다.
    // gammaPolarity = (γR, γG, γB, polarity), limits = (Lhi, Llo, nShoulder, nToe)
    [[stitchable]] float4 digitalFilmDensity(coreimage::sample_t src,
                                             float4 gammaPolarity,
                                             float4 limits,
                                             float exposureScale,
                                             float4 layerSpeed,
                                             float4 layerDmax) {
        float3 e = max(src.rgb, float3(1e-5));
        // 감광층은 감도가 서로 다르게 설계된다. 층마다 곡선이 노출 축에서 어긋나 있고,
        // 그 어긋남이 밝기대별로 색이 갈리는 크로스오버의 물리적 출처다.
        float3 stops = (log2(e / float3(0.18)) + layerSpeed.rgb) * exposureScale;
        float3 d = gammaPolarity.rgb * 0.30103 * stops * gammaPolarity.w;
        // 층별 최대 밀도도 같지 않다 — 적감(시안 형성) 층이 가장 높은 Dmax 로 눕는다.
        float3 hi = float3(
            softLimit(max(d.x, 0.0), limits.x * layerDmax.x, limits.z),
            softLimit(max(d.y, 0.0), limits.x * layerDmax.y, limits.z),
            softLimit(max(d.z, 0.0), limits.x * layerDmax.z, limits.z)
        );
        float3 lo = float3(
            softLimit(max(-d.x, 0.0), limits.y * layerDmax.x, limits.w),
            softLimit(max(-d.y, 0.0), limits.y * layerDmax.y, limits.w),
            softLimit(max(-d.z, 0.0), limits.y * layerDmax.z, limits.w)
        );
        return float4(hi - lo, src.a);
    }

    // DIR 커플러의 층간 억제(inter-image effect). 한 층의 밀도가 이웃 층의 현상을 억제한다.
    // 중립 대비로 정규화하므로 무채색은 정확히 보존되고 유채색만 채널 간격이 벌어진다 —
    // 색 대비를 중립 대비에서 분리하는 것이 DIR 커플러가 채도를 만드는 실제 메커니즘이다.
    [[stitchable]] float4 digitalInterImage(coreimage::sample_t src, float4 k) {
        float3 d = src.rgb;
        float3 kk = max(k.rgb, float3(0.0));
        float3 others = (float3(d.x + d.y + d.z) - d) * 0.5;
        return float4((d - kk * others) / max(float3(1.0) - kk, float3(1e-3)), src.a);
    }

    // 네거티브 밀도 → 인화 노출 → RA-4 인화지 밀도 → 반사율.
    // 네거티브의 낮은 감마(≈0.6)를 인화지의 높은 감마(≈1.7)가 되살리는 2단 구조가
    // 네거티브 특유의 "늦게 눕는 명부 + 살아 있는 암부"를 만든다.
    // paper = (γ, Dmax, Dmin, n)
    [[stitchable]] float4 digitalPrintPaper(coreimage::sample_t src, float4 paper) {
        float3 stops = -src.rgb / 0.30103;
        float3 dp = paper.x * 0.30103 * stops;
        float3 hi = softLimit3(max(dp, float3(0.0)), paper.y, paper.w);
        float3 lo = softLimit3(max(-dp, float3(0.0)), paper.z, paper.w);
        return float4(0.18 * pow(float3(10.0), -(hi - lo)), src.a);
    }

    // 반전 필름은 인화 단계가 없다. 밀도를 그대로 투과율로 읽는다.
    // p = (Dmax, Dmin, n, _)
    [[stitchable]] float4 digitalReversalTransmit(coreimage::sample_t src, float4 p) {
        float3 d = src.rgb;
        float3 hi = softLimit3(max(d, float3(0.0)), p.x, p.z);
        float3 lo = softLimit3(max(-d, float3(0.0)), p.y, p.z);
        return float4(0.18 * pow(float3(10.0), -(hi - lo)), src.a);
    }

    // 산란 + 헐레이션. 에멀전 내부 산란(작은 반경)과 베이스 반사(큰 반경, 다중 바운스)를
    // 나눠 합성한다. 되돌아온 빛은 적색 층을 먼저 때리므로 R ≫ G > B 로 실린다.
    // 더하지 않고 원본에서 덜어내 재분배하므로 총 광량이 늘지 않는다.
    [[stitchable]] float4 digitalHalation(coreimage::sample_t src,
                                          coreimage::sample_t nearBlur,
                                          coreimage::sample_t farBlur,
                                          coreimage::sample_t wideBlur,
                                          float4 scatter, float4 halation) {
        float3 s = max(scatter.rgb, float3(0.0));
        float3 h = max(halation.rgb, float3(0.0));
        float3 far = farBlur.rgb * 0.68 + wideBlur.rgb * 0.32;
        float3 keep = max(float3(1.0) - s - h, float3(0.0));
        return float4(src.rgb * keep + nearBlur.rgb * s + far * h, src.a);
    }

    inline float3 digitalLinearToSRGB(float3 c) {
        float3 lo = c * 12.92;
        float3 hi = 1.055 * pow(max(c, float3(0.0)), float3(1.0 / 2.4)) - 0.055;
        return select(hi, lo, c <= float3(0.0031308));
    }

    inline float3 digitalSRGBToLinear(float3 c) {
        float3 lo = c / 12.92;
        float3 hi = pow(max((c + 0.055) / 1.055, float3(0.0)), float3(2.4));
        return select(hi, lo, c <= float3(0.04045));
    }

    // 색 조정 스테이지(그레이딩·믹서·캘리브레이션)는 표시 도메인 0…1 을 전제로 만들어졌다.
    // 가상 현상 결과는 선형 반사율이므로, 그 스테이지들을 태우기 전후로 도메인을 옮긴다.
    [[stitchable]] float4 digitalToDisplayGamma(coreimage::sample_t src) {
        return float4(digitalLinearToSRGB(src.rgb), src.a);
    }

    [[stitchable]] float4 digitalToLinearLight(coreimage::sample_t src) {
        return float4(digitalSRGBToLinear(src.rgb), src.a);
    }

    inline float digitalHueDegrees(float3 c) {
        float mx = max(c.r, max(c.g, c.b));
        float mn = min(c.r, min(c.g, c.b));
        float d = mx - mn;
        if (d <= 1e-6) return 0.0;
        float h;
        if (mx == c.r)      h = (c.g - c.b) / d;
        else if (mx == c.g) h = 2.0 + (c.b - c.r) / d;
        else                h = 4.0 + (c.r - c.g) / d;
        h *= 60.0;
        return h < 0.0 ? h + 360.0 : h;
    }

    // 6색 앵커(R,Y,G,C,B,M)를 hue 원형 선형보간.
    inline float digitalHueBand(float hue, float4 a, float4 b) {
        float anchors[6] = { a.x, a.y, a.z, a.w, b.x, b.y };
        float seg = hue / 60.0;
        float base = floor(seg);
        int i = int(base) % 6;
        int j = (i + 1) % 6;
        float f = seg - base;
        return anchors[i] * (1.0 - f) + anchors[j] * f;
    }

    // 필름 스톡의 색 시그니처. 대비/계조는 가상 현상이 이미 만들었으므로 여기서는 색만 얹는다.
    // 계수가 sRGB 감마 도메인 기준이라 그 도메인으로 옮겨 적용하고 되돌린다.
    // mR/mG/mB = 색 매트릭스 행(.w = 채널 lift). hue 앵커 6개는 iieHueA 전체와 iieHueB.xy 에
    // 담고, inter-image 채도 강도는 iieHueB.z 에 둔다.
    [[stitchable]] float4 digitalFilmColor(coreimage::sample_t src,
                                           float4 mR, float4 mG, float4 mB,
                                           float4 shadowTint, float4 highlightTint,
                                           float4 iieHueA, float4 iieHueB) {
        constexpr float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float3 v = digitalLinearToSRGB(src.rgb) + float3(mR.w, mG.w, mB.w);
        v = max(float3(dot(mR.rgb, v), dot(mG.rgb, v), dot(mB.rgb, v)), float3(0.0));

        float yl = clamp(dot(v, ycoef), 0.0, 1.0);
        v += shadowTint.rgb * (1.0 - yl) * (1.0 - yl) + highlightTint.rgb * yl * yl;

        float y = dot(v, ycoef);
        float chroma = max(v.r, max(v.g, v.b)) - min(v.r, min(v.g, v.b));
        float expW = smoothstep(0.12, 0.72, y);
        float protectW = smoothstep(0.02, 0.14, chroma);
        float hueW = 1.0 + digitalHueBand(digitalHueDegrees(v), iieHueA, iieHueB);
        float sat = 1.0 + iieHueB.z * expW * protectW * hueW;
        v = float3(y) + (v - float3(y)) * sat;

        return float4(digitalSRGBToLinear(max(v, float3(0.0))), src.a);
    }

    // 밀도 의존 그레인. 물리 granularity 는 밀도의 제곱근을 따라 커지고(Selwyn), 지각되는
    // 거칠기는 밀도 1.0 부근에서 가장 크다. 두 특성을 곱해 진폭을 정한다. 노이즈는 밀도
    // 도메인에서 더한다 — 필름 그레인은 가산 오버레이가 아니라 곱셈 변조이기 때문이다.
    // p = (amplitude, chromaRatio, _, _)
    [[stitchable]] float4 digitalFilmGrainDensity(coreimage::sample_t src,
                                                  coreimage::sample_t noise,
                                                  float4 p) {
        float3 v = max(src.rgb, float3(1e-5));
        float3 dens = -log10(v / float3(0.18));
        float3 physical = sqrt(max(dens, float3(0.0)) + float3(0.02));
        float3 t = (dens - float3(1.0)) / float3(1.15);
        float3 perceptual = exp(-t * t);
        float3 amp = p.x * physical * perceptual;
        float3 n = noise.rgb - float3(0.5);
        float nl = (n.x + n.y + n.z) / 3.0;
        n = mix(float3(nl), n, p.y);
        return float4(0.18 * pow(float3(10.0), -(dens + n * amp)), src.a);
    }
    """
}
