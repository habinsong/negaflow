// GrainMend 스크래치 각도. CPU 는 `imaging/grain_mend_scratch_angles.cpp`.
// 탭 좌표는 CPU 가 lround 로 만들어 넘깁니다. 여기서 다시 만들지 마십시오.
//
// HLSL 배열은 원소마다 16바이트라 탭은 int4 입니다. xy 만 씁니다.
// https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-packing-rules

Texture2D<float4> Source : register(t0);
Texture2D<float4> Other : register(t1);
RWTexture2D<float4> Destination : register(u0);

cbuffer ScratchAngleConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    int TapCount;
    float BalanceLimit;
    int Accumulate;
    int Padding1;
    int4 Center[5];
    int4 Positive[5];
    int4 Negative[5];
    int4 Along[25];
};

float sample_r(int2 p) {
    int2 q = int2(
        clamp(p.x, 0, int(Extent.x) - 1),
        clamp(p.y, 0, int(Extent.y) - 1));
    return Source[q].r;
}

bool inside(int2 p) {
    return p.x >= 0 && p.y >= 0 && p.x < int(Extent.x) && p.y < int(Extent.y);
}

[numthreads(8, 8, 1)]
void RidgeMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    int2 p = int2(id.xy);
    if (Source[p].g == 0.0) {
        Destination[p] = float4(0.0, 0.0, 0.0, 0.0);
        return;
    }
    precise float center = 0.0;
    precise float positive = 0.0;
    precise float negative = 0.0;
    [unroll]
    for (int tap = 0; tap < 5; ++tap) {
        center += sample_r(p + Center[tap].xy);
        positive += sample_r(p + Positive[tap].xy);
        negative += sample_r(p + Negative[tap].xy);
    }
    center /= 5.0;
    positive /= 5.0;
    negative /= 5.0;
    float ridge = 0.0;
    if (!(abs(positive - negative) >= BalanceLimit)) {
        ridge = max(
            0.0,
            max(min(center - positive, center - negative),
                min(positive - center, negative - center)));
    }
    Destination[p] = float4(ridge, Source[p].g, 0.0, 0.0);
}

[numthreads(8, 8, 1)]
void IntegrateMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    int2 p = int2(id.xy);
    if (Source[p].g == 0.0) {
        if (Accumulate == 0) {
            Destination[p] = float4(0.0, Source[p].g, 0.0, 0.0);
        }
        return;
    }
    precise float sum = 0.0;
    int samples = 0;
    for (int tap = 0; tap < TapCount; ++tap) {
        int2 q = p + Along[tap].xy;
        if (inside(q)) {
            sum += Source[q].r;
            samples += 1;
        }
    }
    float response = samples == 0 ? 0.0 : sum / float(samples);
    if (Accumulate != 0) {
        response = max(Destination[p].r, response);
    }
    Destination[p] = float4(response, Source[p].g, 0.0, 0.0);
}

[numthreads(8, 8, 1)]
void MaxMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    int2 p = int2(id.xy);
    float4 a = Destination[p];
    float4 b = Source[p];
    float4 c = Other[p];
    // r = best integrated, g = best ridge
    Destination[p] = float4(max(a.r, b.r), max(a.g, c.r), 0.0, 0.0);
}
