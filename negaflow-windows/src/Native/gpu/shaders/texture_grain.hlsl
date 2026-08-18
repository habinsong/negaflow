// TextureStage 그레인 — macOS `filmGrain` (`ChromabaseMetalKernels.swift:281`).
// CPU 판 : `imaging/texture_stage_effects.cpp` `apply_grain`
//
// ☠️ 맞춰야 할 상대는 Apple `CIRandomGenerator` 가 아니라 Windows CPU 좌표 해시입니다.
//    해시·`>> 8`·16777215 나눗셈은 uint32 이라 **비트 단위로 같아야** 합니다.
//    루마·smoothstep·클램프는 부동소수라 마지막 비트가 갈릴 수 있습니다.

#include "tone_shared.hlsli"

cbuffer TextureGrainConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    // `strength * 0.055` — CPU 가 화소 루프 밖에서 곱한 값입니다. 여기서 다시 곱하지 마십시오.
    float Amount;
    float3 Padding1;
};

// `texture_stage_math.h` `coordinate_hash`. 채널 항이 없습니다 — 디지털 필름 그레인 해시와 다릅니다.
uint CoordinateHash(uint x, uint y) {
    uint value = x * 0x9e3779b9u ^ y * 0x85ebca6bu ^ 0xc2b2ae35u;
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

[numthreads(8, 8, 1)]
void TextureGrainMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    float y = dot(source.rgb, LumaCoefficients);
    float t0 = saturate((y - 0.02) / (0.16 - 0.02));
    float t1 = saturate((y - 0.82) / (1.0 - 0.82));
    float w = (t0 * t0 * (3.0 - 2.0 * t0)) * (1.0 - (t1 * t1 * (3.0 - 2.0 * t1)));
    float noise = float(CoordinateHash(id.x, id.y) >> 8u) / 16777215.0 - 0.5;
    float grain = noise * Amount * w;
    Destination[coordinate] = float4(saturate(source.rgb + grain), source.a);
}
