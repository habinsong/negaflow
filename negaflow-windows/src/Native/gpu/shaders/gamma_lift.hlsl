// `imaging/film_scan_denoise_tile.cpp:13` `extract_lifted_tile` 입니다.
//
//     std::pow(clamp_unit(source.red), gamma_lift_power)
//
// 어두운 쪽 잡음 진폭을 톤 전체에서 균일하게 보려고 들어 올립니다. 되돌리는 것은
// `film_scan_shrink.hlsl` 의 마지막 줄입니다.
//
// ⚠️ `pow` 는 CPU `std::pow` 와 **마지막 비트가 같지 않습니다.** D3D11 은 `log2`·`exp2` 에
//    각각 상대오차 2^-21 까지 허용하므로 `pow` 는 대략 1e-6 상대오차입니다. 되돌릴 때
//    지수 2.22 가 그 상대오차를 2.22배로 키웁니다. 이 경로의 실측 오차는 동치 시험이
//    보고합니다 — 허용치 `1e-5` 안인지는 **재서** 판단하십시오.

Texture2D<float4> Source : register(t0);
RWTexture2D<float4> Destination : register(u0);

cbuffer GammaLiftConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float Power;
    float3 Padding1;
};

[numthreads(8, 8, 1)]
void GammaLiftMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 at = id.xy;
    float4 source = Source[at];
    // 알파는 CPU 가 리프트하지 않습니다 — `Rgb` 세 채널만 다룹니다.
    Destination[at] = float4(pow(clamp(source.rgb, 0.0, 1.0), Power), source.a);
}
