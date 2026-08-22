// macOS `ChromabaseMetalKernels.swift:123` `[[stitchable]] float4 bwToning(...)`.
// Windows CPU 판은 `imaging/bw_toning.cpp` `apply_bw_toning` 이고, 이 셰이더는 그것과
// 화소값이 같아야 합니다(동치 시험 허용 오차 1e-5).
//
// CPU 판은 macOS 커널보다 한 가지를 더 합니다 — **조색을 끄더라도 먼저 중성화**합니다
// (`pixel.red = pixel.green = pixel.blue = neutral`). 흑백 변환과 조색이 한 패스이기 때문입니다.
// 그래서 `Tone` 이 0 이어도 이 커널은 돌아야 합니다. 조기 반환으로 건너뛰면 흑백 변환이 사라집니다.
//
// 주의 `Tone` 이 0 일 때 CPU 는 중성값을 **클램프하지 않고** 그대로 씁니다.
// 켜져 있을 때만 `clamp_unit` 을 겁니다. 그 차이를 그대로 옮겼습니다.
//
// 색조(tint)는 `imaging::prepare_bw_toning` 이 만든 것을 받습니다. 여기서 다시 계산하지 마십시오.

#include "tone_shared.hlsli"

cbuffer BwToningConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float3 ShadowTint;
    float Strength;
    float3 HighlightTint;
    float Mode; // 세피아 1.0, 셀레늄 0.0
    float Tone; // 조색을 거는지 (1.0/0.0)
    float3 Padding1;
};

[numthreads(8, 8, 1)]
void BwToningMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];

    float neutral = dot(source.rgb, LumaCoefficients);
    if (Tone < 0.5) {
        // CPU 판과 같이 클램프하지 않습니다.
        Destination[coordinate] = float4(neutral, neutral, neutral, source.a);
        return;
    }

    float value = clamp(neutral, 0.0, 1.0);
    float shadowReach = 0.68 + ((0.92 - 0.68) * Mode);
    float highlightReach = 0.38 + ((0.76 - 0.38) * Mode);
    float shadowWeight = 1.0 - smoothstep(0.18, shadowReach, value);
    float highlightWeight = smoothstep(1.0 - highlightReach, 0.98, value);
    float crossover = smoothstep(0.22, 0.86, value);
    float3 tint = ShadowTint + ((HighlightTint - ShadowTint) * crossover);
    float tintY = max(dot(tint, LumaCoefficients), 0.001);
    float3 toned = (value * tint) / tintY;

    float toneMask = clamp(
        (shadowWeight * (0.95 + ((0.68 - 0.95) * Mode))) +
            (highlightWeight * (0.30 + ((0.72 - 0.30) * Mode))),
        0.0,
        1.0);
    float amount = Strength * (0.18 + ((0.36 - 0.18) * Mode)) * toneMask;

    float seleniumDensity = 1.0 - (0.060 * Strength * shadowWeight);
    float sepiaDensity = 1.0 - (0.026 * Strength * smoothstep(0.36, 0.92, value));
    float density = seleniumDensity + ((sepiaDensity - seleniumDensity) * Mode);

    float3 neutralRgb = float3(value, value, value);
    float3 rgb = neutralRgb + ((toned - neutralRgb) * amount);
    Destination[coordinate] = float4(clamp(rgb * density, 0.0, 1.0), source.a);
}
