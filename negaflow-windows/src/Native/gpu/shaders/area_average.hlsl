// macOS `CIAreaAverage` 대응 — 사각형 합 + 개수.
//
// CPU 판은 `imaging/area_average.cpp` 가 행 우선 `double` 로 더합니다.
// 여기는 cs_5_0 `groupshared` 트리입니다. Wave 내장은 쓰지 않습니다 —
// wave 크기가 벤더마다 달라 내장/외장 공통 하한과 충돌합니다.
//
// 덧셈 순서가 CPU 와 다릅니다. 평균 허용 오차는 1e-5 입니다.

#define NEGAFLOW_REDUCE_GROUP 16u
#define NEGAFLOW_REDUCE_THREADS 256u

struct Partial {
    float4 sum; // rgb + count(w)
};

Texture2D<float4> Source : register(t0);
StructuredBuffer<Partial> InputPartials : register(t1);
RWStructuredBuffer<Partial> OutputPartials : register(u0);

cbuffer AreaAverageConstants : register(b0) {
    // GpuPointwiseExtent — 16바이트. uint2 뒤에 바로 Origin 을 두면 같은 레지스터에 붙습니다.
    uint2 Extent;
    float2 ExtentPad;
    uint2 Origin;
    uint2 Region;
    uint PartialCount;
    uint Padding0;
    float2 Pad1;
};

groupshared float4 Gs[NEGAFLOW_REDUCE_THREADS];

void TreeReduce(uint group_index) {
    [unroll]
    for (uint stride = NEGAFLOW_REDUCE_THREADS / 2u; stride > 0u; stride >>= 1u) {
        GroupMemoryBarrierWithGroupSync();
        if (group_index < stride) {
            Gs[group_index] += Gs[group_index + stride];
        }
    }
}

[numthreads(NEGAFLOW_REDUCE_GROUP, NEGAFLOW_REDUCE_GROUP, 1)]
void ReduceImageMain(uint3 id : SV_DispatchThreadID, uint group_index : SV_GroupIndex, uint3 group_id : SV_GroupID) {
    float4 value = float4(0.0, 0.0, 0.0, 0.0);
    if (id.x < Region.x && id.y < Region.y) {
        uint2 pixel = Origin + id.xy;
        if (pixel.x < Extent.x && pixel.y < Extent.y) {
            float4 source = Source[pixel];
            value = float4(source.r, source.g, source.b, 1.0);
        }
    }
    Gs[group_index] = value;
    TreeReduce(group_index);
    if (group_index == 0u) {
        uint groups_x = (Region.x + NEGAFLOW_REDUCE_GROUP - 1u) / NEGAFLOW_REDUCE_GROUP;
        Partial out_value;
        out_value.sum = Gs[0];
        OutputPartials[group_id.y * groups_x + group_id.x] = out_value;
    }
}

[numthreads(NEGAFLOW_REDUCE_THREADS, 1, 1)]
void ReducePartialsMain(uint3 id : SV_DispatchThreadID, uint group_index : SV_GroupIndex, uint3 group_id : SV_GroupID) {
    float4 value = float4(0.0, 0.0, 0.0, 0.0);
    if (id.x < PartialCount) {
        value = InputPartials[id.x].sum;
    }
    Gs[group_index] = value;
    TreeReduce(group_index);
    if (group_index == 0u) {
        Partial out_value;
        out_value.sum = Gs[0];
        OutputPartials[group_id.x] = out_value;
    }
}
