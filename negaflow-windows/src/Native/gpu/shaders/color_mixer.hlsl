// macOS `ChromabaseMetalKernels.swift:74` `[[stitchable]] float4 colorMixerHSL(...)`.
// Windows CPU 판은 `imaging/color_mixer.cpp` `apply_color_mixer` 이고, 이 셰이더는 그것과
// 화소값이 같아야 합니다(동치 시험 허용 오차 1e-5).
//
// 밴드 8개(빨강·주황·노랑·초록·하늘·파랑·보라·자홍)마다 색상/채도/광도를 따로 밉니다.
// macOS 는 밴드를 `float4` 두 개로 묶어 넘기지만, 여기서는 배열 그대로 넘깁니다 —
// HLSL 상수 버퍼의 배열은 원소마다 16바이트를 차지하므로 CPU 쪽 구조체도 그렇게 맞춥니다.
//
// **상수를 여기에 박지 마십시오.** 밴드 중심·폭·게이트·스케일은 전부 CPU 와 같은 값이어야 하고,
// 지금은 셰이더 안에 있지만 CPU 쪽 `color_mixer.cpp` 의 constexpr 과 **하나라도 다르면**
// 동치 시험이 잡습니다. 바꿀 일이 생기면 양쪽을 같이 바꾸십시오.

#include "tone_shared.hlsli"
#include "hsl_shared.hlsli"

#define NEGAFLOW_COLOR_MIXER_BANDS 8

cbuffer ColorMixerConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    // HLSL 상수 버퍼 배열은 원소마다 16바이트 정렬입니다. `.x` 만 씁니다.
    float4 HueControls[NEGAFLOW_COLOR_MIXER_BANDS];
    float4 SaturationControls[NEGAFLOW_COLOR_MIXER_BANDS];
    float4 LuminanceControls[NEGAFLOW_COLOR_MIXER_BANDS];
};

// `imaging/color_mixer.cpp` 의 constexpr 과 같은 값이어야 합니다.
static const float NegaflowBandCenters[NEGAFLOW_COLOR_MIXER_BANDS] = {
    0.0, 0.083333, 0.166667, 0.333333, 0.5, 0.666667, 0.75, 0.833333
};
static const float NegaflowBandWidth = 0.14;
static const float NegaflowHueShiftScale = 0.0833;
static const float NegaflowLuminanceShiftScale = 0.16;
static const float NegaflowGateLow = 0.04;
static const float NegaflowGateHigh = 0.18;
static const float NegaflowIdentityEpsilon = 1.0e-4;

[numthreads(8, 8, 1)]
void ColorMixerMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];

    float3 hsl = NegaflowRgbToHsl(clamp(source.rgb, 0.0, 1.0));

    float weightSum = 0.0;
    float hueShift = 0.0;
    float saturationFactor = 0.0;
    float luminanceFactor = 0.0;
    [unroll]
    for (int index = 0; index < NEGAFLOW_COLOR_MIXER_BANDS; ++index) {
        float distance = abs(hsl.x - NegaflowBandCenters[index]);
        distance = min(distance, 1.0 - distance);
        float weight = max(0.0, 1.0 - (distance / NegaflowBandWidth));
        weightSum += weight;
        hueShift += weight * HueControls[index].x;
        saturationFactor += weight * SaturationControls[index].x;
        luminanceFactor += weight * LuminanceControls[index].x;
    }
    if (weightSum > NegaflowIdentityEpsilon) {
        hueShift /= weightSum;
        saturationFactor /= weightSum;
        luminanceFactor /= weightSum;
    }

    float gate = smoothstep(NegaflowGateLow, NegaflowGateHigh, hsl.y);
    // CPU 판은 `+ 1.0` 한 뒤 `floor` 를 빼서 감쌉니다. `frac` 은 음수 입력에서 결과가 달라지므로
    // **그대로 옮깁니다.**
    float shiftedHue = hsl.x + (hueShift * NegaflowHueShiftScale * gate) + 1.0;
    hsl.x = shiftedHue - floor(shiftedHue);
    hsl.y = clamp(hsl.y * (1.0 + (saturationFactor * gate)), 0.0, 1.0);
    hsl.z = clamp(hsl.z + (luminanceFactor * NegaflowLuminanceShiftScale * gate), 0.0, 1.0);

    float3 rgb = NegaflowHslToRgb(hsl);
    Destination[coordinate] = float4(clamp(rgb, 0.0, 1.0), source.a);
}
