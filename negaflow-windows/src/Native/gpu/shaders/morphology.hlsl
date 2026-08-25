// 형태학(침식·팽창)입니다. Windows CPU 는 `imaging/grain_mend_morphology.cpp` 이고
// **GrainMend 검출 CPU 시간의 82%** 가 여기 있습니다(먼지 형태학 47% + 미세 입자 35%,
// `04-gpu-plan.md` 6.2절).
//
// **여기에는 부동소수 산술이 없습니다.** 창 안에서 **하나를 고르는** 일이라
// 고르는 방법이 달라도 고른 값은 같습니다 — CPU 의 단조 덱(vHGW)과 아래의 직접 훑기는
// **비트 단위로 같은 값**을 냅니다. 평균·보간을 넣는 순간 그 성질이 깨집니다.
//
// 구조 요소는 **분리형 정사각형**입니다(수평 1D → 수직 1D). CPU 도 그렇습니다 —
// `13-performance-playbook.md` 4.3절이 걱정한 45° 사선 요소는 이 코드에 없습니다.
//
// 창은 여전히 직접 훑습니다(화소당 O(r)). 다만 **전역 메모리에서 같은 화소를 반복해서
// 읽지 않습니다** — 그룹이 자기 구간과 halo 를 groupshared 로 한 번만 올리고 거기서
// 훑습니다. 값을 고르는 방법은 그대로이므로 결과는 비트 단위로 같습니다.
//
// 왜 고쳤나(2026-08-25): 이 파일은 원래 "실제 반경이 1·3·4·8·12(창 최대 25)로 작아서"
// 직접 훑기를 골랐다고 적어 두고, 바꾸려면 **재고 나서** 하라고 했습니다. 재 봤더니
// 그 전제가 IR 검출에서 깨져 있었습니다. `infrared_defect_detector.cpp:158` 의 반경은
// `clamp(min(width,height)/100, 4, 96)` 이라 실제 스캔(2272×3431)에서 **22**, 창 **45**
// 이고 큰 스캔에서는 상한 96, 창 193 까지 갑니다. 실측(부산 22쌍)에서 `ir_signal` 이
// 검출 core p95 의 58%(686.7ms)였습니다.
//
// 8×8 그룹이 창 45 를 직접 훑으면 8 스레드가 8×45=360 번 읽어 고작 52 화소를 봅니다 —
// 6.9배가 중복입니다. 64 폭 그룹 + groupshared 면 64+44=108 화소를 한 번씩만 읽습니다.
//
// 재고 나서 결정했습니다(2026-08-25). `NEGA_GPU_TIMING=1` 로 커널 구간만 재면 실제 부산
// 22쌍에서 검출당 형태학 GPU 시간이 **73.5ms → 43.1ms(−40.6%)** 입니다(수평·수직 각 2
// 디스패치, n=20, disjoint drop 0). 두 빌드를 두 번씩 돌린 범위가 겹치지 않습니다.
//
// **CPU 벽시계로는 이 차이를 못 가릅니다.** 처음에 벽시계로 재고 "편차 안" 이라 판단해
// 이 변경을 한 번 되돌렸습니다. 그 비교는 (1) cold 캐시였고 (2) 낡은 exe 를 실행해 사실은
// **같은 바이너리를 두 번 잰 것**이었습니다. 자세한 것은 체크포인트 §18.
//
// 반경 무관 O(1)(vHGW 블록 prefix/suffix)은 **하지 않습니다.** 위 계측이 상한을 정해
// 줍니다 — 형태학을 0 으로 만들어도 `ir_signal` 에서 43ms 밖에 못 줄입니다.
//
// 네 채널을 각각 독립으로 처리합니다. 검출은 채널 셋 + 휘도를 다루므로 한 텍스처에
// 담아 한 번에 돌릴 수 있습니다.

Texture2D<float4> Source : register(t0);
Texture2D<float4> Opened : register(t1);
Texture2D<float4> Closed : register(t2);
RWTexture2D<float4> Destination : register(u0);

// 앞 16바이트는 화소별 커널과 같은 `GpuPointwiseExtent` 자리입니다.
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

// 한 축 그룹의 스레드 수입니다. C++ 쪽 `gpu_morphology_axis_group` 과 **같아야** 합니다.
#define MORPH_AXIS_GROUP 64
// groupshared 로 감당할 최대 반경입니다. 이보다 크면 직접 훑기로 내려갑니다 — 값은 같고
// 속도만 예전과 같습니다. 96 은 `infrared_defect_detector.cpp` 의 반경 상한입니다.
#define MORPH_MAX_RADIUS 96

// 64 + 2*96 = 256 개 × 16B = 4KB. D3D11 의 32KB 한도 안입니다.
groupshared float4 g_axis_tile[MORPH_AXIS_GROUP + 2 * MORPH_MAX_RADIUS];

// groupshared 에 올린 구간에서 창을 훑습니다. `scan_axis` 와 **같은 화소들을 같은
// 연산으로** 봅니다 — min/max 는 순서와 무관하므로 값이 비트 단위로 같습니다.
float4 scan_tile(uint local, int radius) {
    float4 best = g_axis_tile[local];
    for (int k = 1; k <= 2 * radius; ++k) {
        float4 value = g_axis_tile[local + uint(k)];
        best = IsMinimum != 0 ? min(best, value) : max(best, value);
    }
    return best;
}

[numthreads(MORPH_AXIS_GROUP, 1, 1)]
void MorphologyHorizontalMain(
    uint3 id : SV_DispatchThreadID,
    uint3 local : SV_GroupThreadID,
    uint3 group : SV_GroupID) {
    // 반경은 상수 버퍼라 그룹 안에서 균일합니다. 균일한 분기라 아래 배리어가 안전합니다.
    if (Radius > MORPH_MAX_RADIUS) {
        if (id.x < Extent.x && id.y < Extent.y) {
            Destination[id.xy] = scan_axis(id.xy, true);
        }
        return;
    }
    // 행 번호는 검사하지 않습니다. 이 패스의 디스패치 그룹 수가 정확히 높이라
    // `id.y` 가 절대 범위를 벗어나지 않습니다 — 배리어 앞에 varying 분기를 두면
    // 컴파일러가 균일성을 증명하지 못해 X4026 이 납니다.
    const int limit = int(Extent.x);
    const int start = int(group.x) * MORPH_AXIS_GROUP - Radius;
    const int span = MORPH_AXIS_GROUP + 2 * Radius;
    for (int j = int(local.x); j < span; j += MORPH_AXIS_GROUP) {
        const int at = clamp(start + j, 0, limit - 1);
        g_axis_tile[j] = Source[uint2(uint(at), id.y)];
    }
    GroupMemoryBarrierWithGroupSync();
    if (id.x >= Extent.x) {
        return;
    }
    Destination[id.xy] = scan_tile(local.x, Radius);
}

[numthreads(1, MORPH_AXIS_GROUP, 1)]
void MorphologyVerticalMain(
    uint3 id : SV_DispatchThreadID,
    uint3 local : SV_GroupThreadID,
    uint3 group : SV_GroupID) {
    if (Radius > MORPH_MAX_RADIUS) {
        if (id.x < Extent.x && id.y < Extent.y) {
            Destination[id.xy] = scan_axis(id.xy, false);
        }
        return;
    }
    // 열 번호도 같은 이유로 검사하지 않습니다 — 디스패치 그룹 수가 정확히 폭입니다.
    const int limit = int(Extent.y);
    const int start = int(group.y) * MORPH_AXIS_GROUP - Radius;
    const int span = MORPH_AXIS_GROUP + 2 * Radius;
    for (int j = int(local.y); j < span; j += MORPH_AXIS_GROUP) {
        const int at = clamp(start + j, 0, limit - 1);
        g_axis_tile[j] = Source[uint2(id.x, uint(at))];
    }
    GroupMemoryBarrierWithGroupSync();
    if (id.y >= Extent.y) {
        return;
    }
    Destination[id.xy] = scan_tile(local.y, Radius);
}

// `grain_mend_morphology.cpp:208-218` `bipolar_top_hat` 의 마지막 두 루프입니다.
//
// magnitude = max(0, source - opened)
// magnitude = max(magnitude, max(0, closed - source))
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
