// 형태학(침식·팽창)입니다. Windows CPU 는 `imaging/grain_mend_morphology.cpp` 이고
// **GrainMend 검출 CPU 시간의 82%** 가 여기 있습니다(먼지 형태학 47% + 미세 입자 35%,
// `04-gpu-plan.md` 6.2절).
//
// ☠️ **여기에는 부동소수 산술이 없습니다.** 창 안에서 **하나를 고르는** 일이라
//    고르는 방법이 달라도 고른 값은 같습니다 — CPU 의 단조 덱(vHGW)과 아래의 직접 훑기는
//    **비트 단위로 같은 값**을 냅니다. 평균·보간을 넣는 순간 그 성질이 깨집니다.
//
// 구조 요소는 **분리형 정사각형**입니다(수평 1D → 수직 1D). CPU 도 그렇습니다 —
// `13-performance-playbook.md` 4.3절이 걱정한 45° 사선 요소는 이 코드에 없습니다.
//
// ⚠️ **지금은 창을 직접 훑습니다(화소당 O(r)).** 실제 반경이 1·3·4·8·12(창 최대 25)로
//    작아서 고른 선택이고, CPU 와 값이 같다는 것은 이것으로도 증명됩니다.
//    반경 무관 O(1)(vHGW 블록 prefix/suffix, 또는 배가법)로 바꾸는 것은 **성능 작업**이며
//    **재고 나서** 하십시오 — 지금 이 저장소에는 단계별 ms 계측기가 없습니다
//    (`13-performance-playbook.md` 0절). 바꿔도 값은 그대로여야 합니다.
//
// 네 채널을 각각 독립으로 처리합니다. 검출은 채널 셋 + 휘도를 다루므로 한 텍스처에
// 담아 한 번에 돌릴 수 있습니다.

Texture2D<float4> Source : register(t0);
Texture2D<float4> Opened : register(t1);
Texture2D<float4> Closed : register(t2);
RWTexture2D<float4> Destination : register(u0);

// ☠️ 앞 16바이트는 화소별 커널과 같은 `GpuPointwiseExtent` 자리입니다.
cbuffer MorphologyConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    int Radius;
    // 1 이면 최소(침식), 0 이면 최대(팽창).
    int IsMinimum;
    float2 Padding1;
};

// 한 축을 훑습니다. 가장자리는 CPU 와 같이 **좌표를 클램프**합니다
// (`grain_mend_morphology.cpp:55` `std::clamp(logical_x, 0, length - 1)`).
float4 scan_axis(uint2 coordinate, bool horizontal) {
    int limit = horizontal ? int(Extent.x) : int(Extent.y);
    int position = horizontal ? int(coordinate.x) : int(coordinate.y);

    int first = clamp(position - Radius, 0, limit - 1);
    float4 best = horizontal ? Source[uint2(uint(first), coordinate.y)]
                             : Source[uint2(coordinate.x, uint(first))];
    for (int offset = -Radius + 1; offset <= Radius; ++offset) {
        int sampleAt = clamp(position + offset, 0, limit - 1);
        float4 value = horizontal ? Source[uint2(uint(sampleAt), coordinate.y)]
                                  : Source[uint2(coordinate.x, uint(sampleAt))];
        best = IsMinimum != 0 ? min(best, value) : max(best, value);
    }
    return best;
}

[numthreads(8, 8, 1)]
void MorphologyHorizontalMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    Destination[id.xy] = scan_axis(id.xy, true);
}

[numthreads(8, 8, 1)]
void MorphologyVerticalMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    Destination[id.xy] = scan_axis(id.xy, false);
}

// `grain_mend_morphology.cpp:208-218` `bipolar_top_hat` 의 마지막 두 루프입니다.
//
//     magnitude = max(0, source - opened)
//     magnitude = max(magnitude, max(0, closed - source))
[numthreads(8, 8, 1)]
void BipolarTopHatMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 at = id.xy;
    float4 source = Source[at];
    float4 opened = Opened[at];
    float4 closed = Closed[at];
    float4 magnitude = max(0.0, source - opened);
    Destination[at] = max(magnitude, max(0.0, closed - source));
}
