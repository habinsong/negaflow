// 자동 레벨·중성 균형이 쓰는 **면적 평균 표본 격자**입니다.
//
// CPU 판 : `imaging/scene_correction.cpp` `collect_sample_row`
//
// 스레드 하나가 격자 칸 하나를 맡아, 원본에서 겹치는 화소를 **겹친 넓이로** 가중
// 평균합니다. 1536x1026 한 장에서 CPU 는 이 일을 두 번(256칸·192칸) 하느라 17ms 를
// 썼고, 무엇보다 그러려면 화소가 호스트에 있어야 했습니다. 여기서 모으면 호스트로
// 내려오는 것은 **격자뿐**입니다 — 6.3MB 대신 176KB.
//
// **근사입니다.** 누적이 CPU 는 `double`, 여기는 `float` 입니다. 뒤이어 백분위와
// 중앙값을 뽑으므로 마지막 비트 차이는 계수에 거의 남지 않지만, 바이트 일치는
// 아닙니다. 호출부가 프리뷰·검출에서만 부릅니다.

Texture2D<float4> Source : register(t0);

struct SampleCell {
    // rgb 평균과, 그 칸이 유효한지(w). 겹치는 넓이가 0 이면 w 가 0 입니다.
    float4 value;
};

RWStructuredBuffer<SampleCell> SampleGrid : register(u0);

cbuffer SceneSampleGridConstants : register(b0) {
    // GpuPointwiseExtent — 16바이트.
    uint2 Extent;
    float2 ExtentPad;
    uint2 SampleExtent;
    // 원본 화소 / 격자 칸. CPU 의 `inverse_scale` 과 같은 자리입니다.
    float InverseScale;
    float SamplePad;
};

float Overlap(float a0, float a1, float b0, float b1) {
    return max(0.0, min(a1, b1) - max(a0, b0));
}

[numthreads(8, 8, 1)]
void SceneSampleGridMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= SampleExtent.x || id.y >= SampleExtent.y) {
        return;
    }
    float top = float(id.y) * InverseScale;
    float bottom = float(id.y + 1u) * InverseScale;
    float left = float(id.x) * InverseScale;
    float right = float(id.x + 1u) * InverseScale;
    uint firstY = uint(floor(top));
    uint lastY = min(Extent.y, uint(ceil(bottom)));
    uint firstX = uint(floor(left));
    uint lastX = min(Extent.x, uint(ceil(right)));

    float3 sum = float3(0.0, 0.0, 0.0);
    float weightSum = 0.0;
    for (uint y = firstY; y < lastY; ++y) {
        float yWeight = Overlap(top, bottom, float(y), float(y + 1u));
        for (uint x = firstX; x < lastX; ++x) {
            float weight = yWeight * Overlap(left, right, float(x), float(x + 1u));
            float4 pixel = Source[uint2(x, y)];
            sum += pixel.rgb * weight;
            weightSum += weight;
        }
    }
    SampleCell cell;
    cell.value = weightSum > 0.0
        ? float4(sum / weightSum, 1.0)
        : float4(0.0, 0.0, 0.0, 0.0);
    SampleGrid[(id.y * SampleExtent.x) + id.x] = cell;
}
