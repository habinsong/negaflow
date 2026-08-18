// macOS `ChromabaseMetalKernels.swift:242` `[[stitchable]] float4 parametricToneCurve(...)`.
// Windows CPU 판은 `imaging/tone_mapping.cpp:143` `apply_parametric_tone_curve` 이고,
// 이 셰이더는 그것과 화소값이 같아야 합니다(동치 시험 허용 오차 1e-5).
//
// 밴드 경계 8개는 macOS 가 인자로 받으므로 여기서도 인자입니다. **상수로 박지 마십시오** —
// `ParametricToneCurveBands` 는 프로파일에 따라 달라집니다.

#include "tone_shared.hlsli"

cbuffer ParametricToneCurveConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float HighlightsAmount;
    float LightsAmount;
    float DarksAmount;
    float ShadowsAmount;
    float ShadowLow;
    float ShadowHigh;
    float DarkLow;
    float DarkHigh;
    float LightLow;
    float LightHigh;
    float HighlightLow;
    float HighlightHigh;
};

[numthreads(8, 8, 1)]
void ParametricToneCurveMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];

    float3 safeRgb = ToneSafeUnitRGB(source.rgb);
    float sourceLuma = dot(safeRgb, LumaCoefficients);

    // 절대 검정(y≈0)은 앵커로 고정해, Shadows 를 올릴 때 바닥 전체가 회색으로 뜨는 것을
    // 막습니다. 가시 암부(y>0.045)에만 작용합니다.
    float shadowMask =
        (1.0 - smoothstep(ShadowLow, ShadowHigh, sourceLuma)) * smoothstep(0.0, 0.045, sourceLuma);
    float darkMask =
        smoothstep(ShadowLow, ShadowHigh, sourceLuma) * (1.0 - smoothstep(DarkLow, DarkHigh, sourceLuma));
    float lightMask =
        smoothstep(DarkLow, DarkHigh, sourceLuma) * (1.0 - smoothstep(LightLow, LightHigh, sourceLuma));
    float highlightMask = smoothstep(HighlightLow, HighlightHigh, sourceLuma);

    float delta =
        (ShadowsAmount * 0.160 * shadowMask) +
        (DarksAmount * 0.155 * darkMask) +
        (LightsAmount * 0.165 * lightMask) +
        (HighlightsAmount * 0.150 * highlightMask);
    float target = clamp(sourceLuma + delta, 0.0, 1.0);
    float lumaDelta = target - sourceLuma;

    Destination[coordinate] = float4(
        clamp(safeRgb.r + lumaDelta, 0.0, 1.0),
        clamp(safeRgb.g + lumaDelta, 0.0, 1.0),
        clamp(safeRgb.b + lumaDelta, 0.0, 1.0),
        source.a);
}
