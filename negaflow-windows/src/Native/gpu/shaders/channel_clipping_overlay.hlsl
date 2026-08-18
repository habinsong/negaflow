// 프리뷰 전용 채널 클리핑 오버레이.
//
// macOS  : `ChromabaseMetalKernels.swift:604` `channelClippingOverlay`
// CPU 판 : `imaging/channel_clipping_overlay.h` `channel_clipping_overlay_pixel`
//
// ☠️ Windows 작업 이미지는 프리멀티가 아닙니다. `rgb / src.a` 를 하지 마십시오.
// ☠️ 경계는 `<= 0` / `>= 1` 입니다.

#include "tone_shared.hlsli"

cbuffer ChannelClippingOverlayConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
};

static const float OverlayOpacity = 0.62;
static const float3 ShadowColor = float3(0.055, 0.24, 0.82);
static const float3 HighlightColor = float3(0.90, 0.07, 0.055);
static const float3 MixedColor = float3(0.64, 0.10, 0.70);

[numthreads(8, 8, 1)]
void ChannelClippingOverlayMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    float4 source = Source[id.xy];
    if (source.a <= 1.0e-6) {
        Destination[id.xy] = float4(0.0, 0.0, 0.0, 0.0);
        return;
    }
    bool shadow = any(source.rgb <= float3(0.0, 0.0, 0.0));
    bool highlight = any(source.rgb >= float3(1.0, 1.0, 1.0));
    if (!shadow && !highlight) {
        Destination[id.xy] = float4(0.0, 0.0, 0.0, 0.0);
        return;
    }
    float3 color = shadow && highlight ? MixedColor : (highlight ? HighlightColor : ShadowColor);
    Destination[id.xy] = float4(color * OverlayOpacity, OverlayOpacity);
}
