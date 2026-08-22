// 흐린 장면 vibrance 입니다.
//
// macOS : `ColorModel.swift` 의 `CIVibrance`(비공개 커널 — 측정 이식)
// CPU 판 : `imaging/muted_scene_vibrance.cpp` `apply_muted_scene_vibrance`
//
// **세기(`amount`)를 여기서 정하지 않습니다.** CPU 가 축소본에서 장면 평균 채도를
// 재서 `min(0.5, max(0, (0.24 − meanSat) × 3))` 로 정합니다. 그 측정은 축소기를
// 거치므로 GPU 로 옮기면 두 벌이 되고, 화소마다 같은 값이라 옮길 이유도 없습니다.
//
// CPU 는 화소마다 결과가 유한한지 보고 아니면 전체를 실패시킵니다. 이 셰이더에는
// 그 경로가 없습니다 — 호출부가 내린 뒤 한 번 확인합니다.

#include "tone_shared.hlsli"
#include "vibrance_shared.hlsli"

cbuffer MutedSceneVibranceConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float Amount;
    float Blend;
    float Quantum;
    uint Low;
};

[numthreads(8, 8, 1)]
void MutedSceneVibranceMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    Destination[coordinate] = float4(
        ApplyMeasuredVibrance(source.rgb, Amount, Low, Blend, Quantum),
        source.a);
}
