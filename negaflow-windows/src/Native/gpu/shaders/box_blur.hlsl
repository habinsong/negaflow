// 분리형 박스 블러입니다. Windows CPU 판은 `imaging/film_scan_denoise_filters.cpp` `box_blur`
// 이고, 이 셰이더는 그것과 화소값이 같아야 합니다.
//
// macOS 는 `CIBoxBlur`(Apple 내장, `FilmScanDenoise.swift:154`)를 씁니다. Windows 에는
// 그 내장 필터가 없어 **우리가 만들어야 하는** 원시연산입니다.
//
// 가이드 필터(`gfProduct`/`gfCoeffA`/`gfCoeffB`/`gfApply`)와 `filmScanShrink` 가 이것에
// 물려 있습니다. 그래서 커널보다 이것이 먼저입니다.
//
// ☠️ **연산 순서를 바꾸지 마십시오.** CPU 판은 러닝 섬(슬라이딩 윈도우)이라 화소당 O(1)
//    이고, 부동소수 누적 순서가 결과에 남습니다. GPU 도 **행 하나에 스레드 하나**를 두어
//    같은 순서로 누적합니다. 반경만큼 다시 더하는 순진한 방식으로 바꾸면 값이 갈립니다.
//
// 가장자리는 CPU 와 같이 **좌표를 클램프**합니다(값을 0 으로 보지 않습니다).

Texture2D<float4> Source : register(t0);
RWTexture2D<float4> Destination : register(u0);

// ☠️ 앞 16바이트는 화소별 커널과 같은 `GpuPointwiseExtent` 자리입니다 — `uint2` 뒤의
//    `float2` 를 빼면 뒤 필드가 8바이트 앞에서 읽혀 조용히 틀린 값이 들어옵니다.
//    (실제로 그렇게 만들었다가 동치 시험이 delta 0.38 로 잡았습니다.)
cbuffer BoxBlurConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    int Radius;
    float3 Padding1;
};

// 한 줄을 통째로 맡는 스레드가 64개씩 묶여 돕니다. 화소별 커널의 8×8 과 달리 1D 입니다 —
// 러닝 섬이 줄 방향으로 순차적이기 때문입니다.
#define NEGAFLOW_BOX_BLUR_GROUP 64

[numthreads(NEGAFLOW_BOX_BLUR_GROUP, 1, 1)]
void BoxBlurHorizontalMain(uint3 id : SV_DispatchThreadID) {
    uint y = id.x;
    if (y >= Extent.y) {
        return;
    }
    int lastX = int(Extent.x) - 1;
    float inverse = 1.0 / float((Radius * 2) + 1);

    // 첫 창을 채웁니다. CPU 와 같이 음수 좌표는 0 으로 클램프됩니다.
    float4 sum = float4(0.0, 0.0, 0.0, 0.0);
    for (int offset = -Radius; offset <= Radius; ++offset) {
        int sampleX = clamp(offset, 0, lastX);
        sum += Source[uint2(uint(sampleX), y)];
    }

    for (uint x = 0U; x < Extent.x; ++x) {
        float4 blurred = sum * inverse;
        // 알파는 흐리지 않습니다 — CPU 판이 RGB 만 다룹니다.
        Destination[uint2(x, y)] = float4(blurred.rgb, Source[uint2(x, y)].a);

        int removeX = clamp(int(x) - Radius, 0, lastX);
        int addX = clamp(int(x) + Radius + 1, 0, lastX);
        sum += Source[uint2(uint(addX), y)] - Source[uint2(uint(removeX), y)];
    }
}

[numthreads(NEGAFLOW_BOX_BLUR_GROUP, 1, 1)]
void BoxBlurVerticalMain(uint3 id : SV_DispatchThreadID) {
    uint x = id.x;
    if (x >= Extent.x) {
        return;
    }
    int lastY = int(Extent.y) - 1;
    float inverse = 1.0 / float((Radius * 2) + 1);

    float4 sum = float4(0.0, 0.0, 0.0, 0.0);
    for (int offset = -Radius; offset <= Radius; ++offset) {
        int sampleY = clamp(offset, 0, lastY);
        sum += Source[uint2(x, uint(sampleY))];
    }

    for (uint y = 0U; y < Extent.y; ++y) {
        float4 blurred = sum * inverse;
        Destination[uint2(x, y)] = float4(blurred.rgb, Source[uint2(x, y)].a);

        int removeY = clamp(int(y) - Radius, 0, lastY);
        int addY = clamp(int(y) + Radius + 1, 0, lastY);
        sum += Source[uint2(x, uint(addY))] - Source[uint2(x, uint(removeY))];
    }
}
