// macOS `digitalHalation`(`ChromabaseMetalKernels.swift:712`) 와
// Windows CPU `imaging/digital_halation.cpp` `apply_digital_halation_material` 입니다.
//
// 에멀전 내부 산란(작은 반경)과 베이스 반사(큰 반경 둘)를 나눠 합성합니다.
// **더하지 않고 원본에서 덜어내 재분배**하므로 총 광량이 늘지 않습니다.
//
// ☠️ **묶는 순서가 macOS 와 Windows 가 다릅니다. Windows 를 따릅니다.**
//
//     macOS  : far = fb*0.68 + wb*0.32;  src*keep + nb*s + far*h
//     Windows: acc  = src*keep
//              acc += nb * s
//              acc += fb * (h*0.68)
//              acc += wb * (h*0.32)
//
//    수학은 같고 부동소수 결합이 다릅니다. 동치 시험의 기준은 Windows CPU 이므로
//    **네 번에 나눠 더하는 쪽**을 그대로 옮깁니다.
//
// ☠️ 블러 셋은 전부 **원본**을 흐린 것입니다. 누적본을 흐리면 안 됩니다 —
//    CPU `accumulate_blur` 가 매번 `result.image`(손대지 않은 원본)를 읽습니다.

Texture2D<float4> Accumulator : register(t0);
Texture2D<float4> Blurred : register(t1);
RWTexture2D<float4> Destination : register(u0);

// ☠️ 앞 16바이트는 화소별 커널과 같은 `GpuPointwiseExtent` 자리입니다.
cbuffer HalationConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    // 기저 패스에서는 `keep = max(1 - scatter - halation, 0)`,
    // 누적 패스에서는 그 패스의 채널별 배율입니다. **호스트가 CPU 와 같은 식으로** 계산해
    // 넘깁니다 — 여기서 빼고 더하면 결합 순서가 CPU 와 갈립니다.
    float3 Scale;
    float Padding1;
};

// 기저 — `digital_halation.cpp:245-249`. 원본에서 덜어냅니다.
[numthreads(8, 8, 1)]
void HalationBaseMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 at = id.xy;
    float4 source = Accumulator[at];
    // 알파는 CPU 가 손대지 않습니다 — `digital_halation.cpp:277-279` 는 rgb 만 씁니다.
    Destination[at] = float4(source.rgb * Scale, source.a);
}

// 누적 — `digital_halation.cpp:154-156` `destination.red += sum.red * scale[0]`.
[numthreads(8, 8, 1)]
void HalationAccumulateMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 at = id.xy;
    float4 accumulated = Accumulator[at];
    float3 blurred = Blurred[at].rgb;
    // `precise` 로 fxc 의 FMA 축약을 막습니다. CPU 는 `/fp:precise` 라 곱과 합이 따로
    // 반올림되고, 여기 셋이 이어져 더해지므로 한 번만 어긋나도 남습니다.
    precise float3 result = accumulated.rgb + (blurred * Scale);
    Destination[at] = float4(result, accumulated.a);
}
