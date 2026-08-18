// 3×3 중앙값입니다. macOS 는 `CIMedianFilter`(Apple 내장, `FilmScanDenoise.swift:171`)를
// 씁니다. Windows CPU 판은 `imaging/film_scan_denoise_filters.cpp:77` `median3` 이고
// 채널마다 따로 `median9` 를 부릅니다:
//
//     std::nth_element(values.begin(), values.begin() + 4, values.end());
//     return values[4];
//
// ☠️ **여기에는 부동소수 산술이 없습니다.** 중앙값은 입력 아홉 개 중 **하나를 고르는**
//    일이라, 고르는 방법이 달라도 고른 값은 같습니다. 그래서 CPU 의 `nth_element` 와
//    아래 정렬 네트워크는 **비트 단위로 같은 값**을 냅니다 — 오차가 아니라 동일입니다.
//    (min/max 만 씁니다. 평균·보간을 넣는 순간 그 성질이 깨집니다.)
//
// 가장자리는 CPU 와 같이 좌표를 클램프합니다.
//
// 알파는 흐리지 않습니다 — CPU 의 `Rgb` 가 알파를 들고 다니지 않습니다.

Texture2D<float4> Source : register(t0);
RWTexture2D<float4> Destination : register(u0);

// ☠️ 앞 16바이트는 화소별 커널과 같은 `GpuPointwiseExtent` 자리입니다.
cbuffer Median3Constants : register(b0) {
    uint2 Extent;
    float2 Padding0;
};

// 정렬 네트워크입니다. 출처: Morgan McGuire, "A Fast, Small-Radius GPU Median Filter"
// (ShaderX / https://casual-effects.com/research/McGuire2008Median/). 교환 19번으로
// 아홉 원소의 중앙값을 냅니다. 완전 정렬이 아니라 **중앙 하나만** 확정합니다.
#define NEGAFLOW_S2(a, b) { float3 t = min(a, b); b = max(a, b); a = t; }
#define NEGAFLOW_MN3(a, b, c) { NEGAFLOW_S2(a, b); NEGAFLOW_S2(a, c); }
#define NEGAFLOW_MX3(a, b, c) { NEGAFLOW_S2(b, c); NEGAFLOW_S2(a, c); }
#define NEGAFLOW_MNMX3(a, b, c) { NEGAFLOW_MX3(a, b, c); NEGAFLOW_S2(a, b); }
#define NEGAFLOW_MNMX4(a, b, c, d) \
    { NEGAFLOW_S2(a, b); NEGAFLOW_S2(c, d); NEGAFLOW_S2(a, c); NEGAFLOW_S2(b, d); }
#define NEGAFLOW_MNMX5(a, b, c, d, e) \
    { NEGAFLOW_S2(a, b); NEGAFLOW_S2(c, d); NEGAFLOW_MN3(a, c, e); NEGAFLOW_MX3(b, d, e); }
#define NEGAFLOW_MNMX6(a, b, c, d, e, f)                                  \
    { NEGAFLOW_S2(a, d); NEGAFLOW_S2(b, e); NEGAFLOW_S2(c, f);            \
      NEGAFLOW_MN3(a, b, c); NEGAFLOW_MX3(d, e, f); }

[numthreads(8, 8, 1)]
void Median3Main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    int lastX = int(Extent.x) - 1;
    int lastY = int(Extent.y) - 1;

    // CPU 와 같은 순서로 모읍니다 — dy 바깥, dx 안쪽. 중앙값은 순서와 무관하지만 읽는
    // 자리를 CPU 와 맞춰 두어야 나중에 대조하기 쉽습니다.
    float3 v[9];
    int cursor = 0;
    for (int dy = -1; dy <= 1; ++dy) {
        int sampleY = clamp(int(coordinate.y) + dy, 0, lastY);
        for (int dx = -1; dx <= 1; ++dx) {
            int sampleX = clamp(int(coordinate.x) + dx, 0, lastX);
            v[cursor] = Source[uint2(uint(sampleX), uint(sampleY))].rgb;
            ++cursor;
        }
    }

    NEGAFLOW_MNMX6(v[0], v[1], v[2], v[3], v[4], v[5]);
    NEGAFLOW_MNMX5(v[1], v[2], v[3], v[4], v[6]);
    NEGAFLOW_MNMX4(v[2], v[3], v[4], v[7]);
    NEGAFLOW_MNMX3(v[3], v[4], v[8]);

    Destination[coordinate] = float4(v[4], Source[coordinate].a);
}
