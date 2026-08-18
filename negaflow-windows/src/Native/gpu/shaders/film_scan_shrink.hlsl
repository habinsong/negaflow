// macOS `filmScanShrink`(`ChromabaseMetalKernels.swift:362`) 와
// Windows CPU `imaging/film_scan_denoise_tile.cpp:103-228` `process_tile` 의 화소 루프입니다.
//
// 입력 여섯 장은 전부 **감마 리프트된 도메인**(x^0.45)입니다:
//   Source  = 리프트한 원본            (`extract_lifted_tile`)
//   Median3 = 3×3 중앙값               (`median3(source)`)
//   Median5 = 중앙값 두 번(≈5×5)       (`median3(med3)`)
//   Fine    = 가우시안 σ 1.3           (`gaussian_blur(source)`)
//   Middle  = 가이드 필터 반경 3        (`guided_base(source, guide, 3)`)
//   Coarse  = 가이드 필터 반경 7        (`guided_base(source, guide, 7)`)
//
// 마지막에 CPU 와 같이 되돌립니다(`pow(lifted, 1/0.45)`). 알파는 CPU 가 쓰지 않으므로
// 원본을 그대로 둡니다(`film_scan_denoise.cpp:156` 는 red/green/blue 만 씁니다).
//
// ☠️ 임계 계산의 상수는 **하나도 여기서 만들지 않습니다.** `process_tile:85-101` 이
//    이미지마다 한 번 계산하는 값들이고, 호스트가 CPU 와 같은 코드로 계산해 넘깁니다
//    (`GpuFilmScanShrink::resolve`). 여기에 숫자를 적으면 두 벌이 되어 어긋납니다.

#include "film_scan_shared.hlsli"

Texture2D<float4> Source : register(t0);
Texture2D<float4> Median3 : register(t1);
Texture2D<float4> Median5 : register(t2);
Texture2D<float4> Fine : register(t3);
Texture2D<float4> Middle : register(t4);
Texture2D<float4> Coarse : register(t5);
RWTexture2D<float4> Destination : register(u0);

// ☠️ 앞 16바이트는 화소별 커널과 같은 `GpuPointwiseExtent` 자리입니다.
cbuffer FilmScanShrinkConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;

    // `process_tile:90-101`
    float BaseLumaThreshold;
    float BaseChromaThreshold;
    float ImpulseLumaThreshold;
    float ImpulseChromaThreshold;

    // `Profile`(`film_scan_denoise.cpp:38` `profile_for`) 와 `axes.dark_tone * 2`
    float ShadowBoost;
    float DarkToneScale;
    float HighlightChroma;
    float HighlightLumaProtect;

    // `1.5 - axes.detail` · `axes.grain_protect` · `1 / 0.45`
    float DetailScale;
    float GrainProtect;
    float InverseGammaLiftPower;
    int Monochrome;
};

[numthreads(8, 8, 1)]
void FilmScanShrinkMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 at = id.xy;

    float4 original = Source[at];
    float3 medianThree = Median3[at].rgb;
    float3 medianFive = Median5[at].rgb;
    float3 fineValue = Fine[at].rgb;
    float3 middleValue = Middle[at].rgb;
    float3 coarseValue = Coarse[at].rgb;

    precise float y0 = negaflow_luminance(original.rgb);
    precise float ym3 = negaflow_luminance(medianThree);
    precise float ym5 = negaflow_luminance(medianFive);
    precise float y1 = negaflow_luminance(fineValue);
    precise float y2 = negaflow_luminance(middleValue);
    precise float y3 = negaflow_luminance(coarseValue);
    precise float3 c0 = negaflow_chroma(original.rgb, y0);
    precise float3 cm3 = negaflow_chroma(medianThree, ym3);
    precise float3 c1 = negaflow_chroma(fineValue, y1);
    precise float3 c2 = negaflow_chroma(middleValue, y2);
    precise float3 c3 = negaflow_chroma(coarseValue, y3);

    // ── 0) 톤 가중치 (`process_tile:128-134`)
    precise float shadow = 1.0 - negaflow_smoothstep(0.16, 0.42, y3);
    precise float nearClip = negaflow_smoothstep(0.88, 0.97, y3);
    precise float grainZone =
        negaflow_smoothstep(0.30, 0.50, y3) * (1.0 - negaflow_smoothstep(0.75, 0.92, y3));
    precise float grainWeight = GrainProtect * grainZone;

    // ── 1) 임펄스 교체 (`process_tile:136-155`)
    precise float consistency = 1.0 - negaflow_smoothstep(0.015, 0.055, abs(ym3 - ym5));
    precise float impulseLumaWeight = min(
        (negaflow_smoothstep(
             ImpulseLumaThreshold, ImpulseLumaThreshold * 1.9, abs(y0 - ym3)) *
         consistency) *
            (1.0 - (0.85 * grainWeight)),
        0.92);
    precise float fixedLuma = negaflow_mix(y0, ym3, impulseLumaWeight);
    precise float impulseChromaWeight = min(
        negaflow_smoothstep(
            ImpulseChromaThreshold,
            ImpulseChromaThreshold * 1.9,
            negaflow_length(c0 - cm3)) *
            consistency,
        0.92);
    precise float3 fixedChroma = negaflow_mix3(c0, cm3, impulseChromaWeight);

    // ── 2) 톤별 임계 (`process_tile:157-166`)
    precise float lumaThreshold = (BaseLumaThreshold *
                                   (1.0 + ((ShadowBoost * DarkToneScale) * shadow))) *
                                  (1.0 - (HighlightLumaProtect * nearClip));
    precise float chromaThreshold =
        BaseChromaThreshold *
        (1.0 + (((0.35 * DarkToneScale) * shadow) + (HighlightChroma * nearClip)));
    lumaThreshold = lumaThreshold * (1.0 - (0.95 * grainWeight));
    lumaThreshold = lumaThreshold * DetailScale;

    // ── 2.5) 구조 적응 가드 (`process_tile:168-177`)
    precise float lumaStructure = abs(y1 - y3);
    precise float chromaStructure = negaflow_length(c1 - c3);
    lumaThreshold = lumaThreshold *
        (1.0 - (0.90 * negaflow_smoothstep(
                           0.018 * DetailScale,
                           0.055 * DetailScale,
                           lumaStructure + (0.5 * chromaStructure))));
    chromaThreshold = chromaThreshold *
        (1.0 - (0.93 * negaflow_smoothstep(
                           0.045 * DetailScale,
                           0.120 * DetailScale,
                           chromaStructure + (0.5 * lumaStructure))));

    // ── 3) coring (`process_tile:179-216`). `a + b + c + d` 는 왼쪽부터 묶입니다.
    precise float detailOne = fixedLuma - y1;
    precise float detailTwo = y1 - y2;
    precise float detailThree = y2 - y3;
    precise float outputLuma =
        ((y3 +
          (detailThree * negaflow_smoothstep(
                             (0.55 * lumaThreshold) * 0.10,
                             (1.5 * lumaThreshold) * 0.10,
                             abs(detailThree)))) +
         (detailTwo * negaflow_smoothstep(
                          (0.55 * lumaThreshold) * 0.55,
                          (1.5 * lumaThreshold) * 0.55,
                          abs(detailTwo)))) +
        (detailOne * negaflow_smoothstep(
                         0.55 * lumaThreshold, 1.5 * lumaThreshold, abs(detailOne)));

    precise float3 outputChroma = c0;
    if (Monochrome == 0) {
        // B&W 필름은 파이프라인 끝 그레이스케일 변환이 chroma 를 지우므로 건드리지 않습니다.
        precise float3 detailChromaOne = fixedChroma - c1;
        precise float3 detailChromaTwo = c1 - c2;
        precise float3 detailChromaThree = c2 - c3;
        outputChroma =
            ((c3 +
              (detailChromaThree * negaflow_smoothstep(
                                       (0.55 * chromaThreshold) * 0.45,
                                       (1.5 * chromaThreshold) * 0.45,
                                       negaflow_length(detailChromaThree)))) +
             (detailChromaTwo * negaflow_smoothstep(
                                    (0.55 * chromaThreshold) * 0.80,
                                    (1.5 * chromaThreshold) * 0.80,
                                    negaflow_length(detailChromaTwo)))) +
            (detailChromaOne * negaflow_smoothstep(
                                   0.55 * chromaThreshold,
                                   1.5 * chromaThreshold,
                                   negaflow_length(detailChromaOne)));
    }

    precise float3 liftedOutput =
        negaflow_clamp_unit3(float3(outputLuma, outputLuma, outputLuma) + outputChroma);
    Destination[at] = float4(pow(liftedOutput, InverseGammaLiftPower), original.a);
}
