// macOS `ChromabaseMetalKernels.swift:151` `[[stitchable]] float4 calibrationPrimaries(...)`.
// Windows CPU 판은 `imaging/primary_calibration.cpp` `apply_primary_calibration` 이고,
// 이 셰이더는 그것과 화소값이 같아야 합니다(동치 시험 허용 오차 1e-5).
//
// 컬러 믹서(밴드 8개)와 모양은 같지만 **상수가 다릅니다** — 원색 3개, 폭 0.22, 게이트
// 0.03~0.16, 색상 스케일 0.08. 믹서 쪽 값을 여기 끌어다 쓰지 마십시오.
// 광도 조정도 없습니다(믹서에만 있습니다).

#include "tone_shared.hlsli"
#include "hsl_shared.hlsli"

#define NEGAFLOW_PRIMARY_COUNT 3

cbuffer PrimaryCalibrationConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    // HLSL 상수 버퍼 배열은 원소마다 16바이트 정렬입니다. `.x` 만 씁니다.
    float4 HueControls[NEGAFLOW_PRIMARY_COUNT];
    float4 SaturationControls[NEGAFLOW_PRIMARY_COUNT];
};

// `imaging/primary_calibration.cpp` 의 constexpr 과 같은 값이어야 합니다.
static const float NegaflowPrimaryCenters[NEGAFLOW_PRIMARY_COUNT] = {0.0, 0.333333, 0.666667};
static const float NegaflowPrimaryBandWidth = 0.22;
static const float NegaflowPrimaryHueShiftScale = 0.08;
static const float NegaflowPrimaryGateLow = 0.03;
static const float NegaflowPrimaryGateHigh = 0.16;
static const float NegaflowPrimaryIdentityEpsilon = 1.0e-4;

[numthreads(8, 8, 1)]
void PrimaryCalibrationMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];

    float3 hsl = NegaflowRgbToHsl(clamp(source.rgb, 0.0, 1.0));

    float weightSum = 0.0;
    float hueShift = 0.0;
    float saturationFactor = 0.0;
    [unroll]
    for (int index = 0; index < NEGAFLOW_PRIMARY_COUNT; ++index) {
        float distance = abs(hsl.x - NegaflowPrimaryCenters[index]);
        distance = min(distance, 1.0 - distance);
        float weight = max(0.0, 1.0 - (distance / NegaflowPrimaryBandWidth));
        weightSum += weight;
        hueShift += weight * HueControls[index].x;
        saturationFactor += weight * SaturationControls[index].x;
    }
    if (weightSum > NegaflowPrimaryIdentityEpsilon) {
        hueShift /= weightSum;
        saturationFactor /= weightSum;
    }

    float gate = smoothstep(NegaflowPrimaryGateLow, NegaflowPrimaryGateHigh, hsl.y);
    // CPU 판은 `+ 1.0` 한 뒤 `floor` 를 빼서 감쌉니다. `frac` 은 음수 입력에서 다릅니다.
    float shiftedHue = hsl.x + (hueShift * NegaflowPrimaryHueShiftScale * gate) + 1.0;
    hsl.x = shiftedHue - floor(shiftedHue);
    hsl.y = clamp(hsl.y * (1.0 + (saturationFactor * gate)), 0.0, 1.0);

    float3 rgb = NegaflowHslToRgb(hsl);
    Destination[coordinate] = float4(clamp(rgb, 0.0, 1.0), source.a);
}
