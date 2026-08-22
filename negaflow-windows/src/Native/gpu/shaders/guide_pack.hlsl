// `film_scan_denoise_tile.cpp:74-77` 입니다.
//
// guide[index] = luminance(fine[index]);
//
// 그리고 가이드 필터가 요구하는 묶음 `(source.rgb, guide)` 를 만듭니다.
//
// 이 커널이 없으면 이 한 걸음 때문에 타일마다 **다운로드 2회 + 업로드 1회**가 붙습니다.
// 커널이 아무리 빨라도 전송이 지배합니다 — `04-gpu-plan.md` 3절.

#include "film_scan_shared.hlsli"

Texture2D<float4> Lifted : register(t0);
Texture2D<float4> Fine : register(t1);
RWTexture2D<float4> Destination : register(u0);

cbuffer GuidePackConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
};

[numthreads(8, 8, 1)]
void GuidePackMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 at = id.xy;
    float3 lifted = Lifted[at].rgb;
    // `negaflow_luminance` 는 CPU 의 괄호를 그대로 지킵니다 — `dot` 을 쓰면 갈립니다.
    precise float guide = negaflow_luminance(Fine[at].rgb);
    Destination[at] = float4(lifted, guide);
}
