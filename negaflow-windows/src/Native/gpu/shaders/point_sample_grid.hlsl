// 타깃 그레이드의 장면 기준값이 쓰는 **점 표본 격자**입니다.
//
// CPU 판 : `imaging/scanner_target_measure.cpp` `measure_inset`
//
// 격자 칸마다 원본 화소 **하나**를 CPU 와 같은 정수 나눗셈으로 골라 그대로 옮깁니다. 필터도
// 누적도 없으므로 값이 비트 단위로 같습니다. 화상이 GPU 에 머물러 있을 때 전체를 내리지
// 않고 격자(160 x 수백 칸)만 내리려고 둡니다.

Texture2D<float4> Source : register(t0);
RWStructuredBuffer<float4> Samples : register(u0);

cbuffer PointSampleGridConstants : register(b0) {
    // GpuPointwiseExtent — 16바이트.
    uint2 Extent;
    float2 ExtentPad;
    // 채울 격자 칸 수와, 자리를 정하는 나눗수입니다. CPU 판은 안쪽 사각형이 격자보다
    // 작은 극단 비율에서 나눗수보다 한 줄 아래를 읽으므로 둘을 나눠 받습니다.
    uint2 SampleExtent;
    uint2 Divisor;
};

[numthreads(8, 8, 1)]
void PointSampleGridMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= SampleExtent.x || id.y >= SampleExtent.y) {
        return;
    }
    // CPU: min(width - 1, (x * width) / sample_width). 격자가 작아 32비트 곱이 넘치지 않습니다.
    uint x = min(Extent.x - 1u, (id.x * Extent.x) / Divisor.x);
    uint y = min(Extent.y - 1u, (id.y * Extent.y) / Divisor.y);
    Samples[id.y * SampleExtent.x + id.x] = Source[uint2(x, y)];
}
