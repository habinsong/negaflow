// 가이드 필터입니다. macOS 는 `[[stitchable]]` 커널 넷으로 나눠 놓았고
// (`ChromabaseMetalKernels.swift:466` `gfProduct` · `:470` `gfCoeffA` · `:482` `gfCoeffB` ·
// `:486` `gfApply`), Windows CPU 판은 `imaging/film_scan_denoise_filters.cpp` `guided_base`
// 한 함수 안에 같은 순서로 들어 있습니다.
//
// 원 논문의 성질대로 **창 크기와 무관한 O(1)** 입니다 — 박스 평균만 O(1)이면 됩니다.
// 그래서 박스 블러가 이 커널들보다 먼저였습니다.
//
// 순서 (CPU `guided_base` 와 같습니다):
//   1. guide² 와 source×guide 를 만든다                      ← Prepare
//   2. guide · source · guide² · (source×guide) 의 박스 평균   ← GpuBoxBlur ×2
//   3. variance = max(0, meanI² 평균 − 평균 meanI²)
//      covariance = 평균(source×guide) − 평균source × 평균guide
//      a = cov / (var + ε),  b = 평균source − a × 평균guide   ← Coefficients
//   4. a 와 b 의 박스 평균                                    ← GpuBoxBlur ×2
//   5. clamp01(평균a × guide + 평균b)                         ← Apply
//
// ☠️ **채널 묶음 규칙** — 박스 블러를 6번이 아니라 4번만 돌리려고 네 스칼라를 한 텍스처에
//    담습니다. 이 배치를 바꾸면 전부 어긋납니다:
//      Packed  = (source.r, source.g, source.b, guide)
//      Product = (source.r×guide, source.g×guide, source.b×guide, guide²)
//    이때 박스 블러는 **알파까지 흘려야** 합니다(`blur_alpha = true`).

Texture2D<float4> SourceA : register(t0);
Texture2D<float4> SourceB : register(t1);
Texture2D<float4> SourceC : register(t2);
RWTexture2D<float4> DestinationA : register(u0);
RWTexture2D<float4> DestinationB : register(u1);

cbuffer GuidedFilterConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float Epsilon;
    float3 Padding1;
};

// 1단계 — macOS `gfProduct`.
// 입력: Packed(source.rgb, guide). 출력: (source.rgb×guide, guide²).
[numthreads(8, 8, 1)]
void GuidedPrepareMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 packed = SourceA[coordinate];
    float guide = packed.a;
    DestinationA[coordinate] = float4(packed.rgb * guide, guide * guide);
}

// 3단계 — macOS `gfCoeffA` + `gfCoeffB`.
// 입력: MeanPacked(평균source.rgb, 평균guide), MeanProduct(평균(source×guide), 평균guide²).
// 출력: A(a.rgb), B(b.rgb).
//
// CPU 판과 같이 분산은 **0 으로 하한**을 둡니다. 박스 평균의 반올림으로 음수가 나올 수
// 있고, 그대로 두면 a 의 부호가 뒤집혀 가장자리에 링이 생깁니다.
[numthreads(8, 8, 1)]
void GuidedCoefficientsMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 meanPacked = SourceA[coordinate];
    float4 meanProduct = SourceB[coordinate];

    float3 meanSource = meanPacked.rgb;
    float meanGuide = meanPacked.a;
    float3 meanGuideProduct = meanProduct.rgb;
    float meanGuideSquared = meanProduct.a;

    // ☠️ 이 다섯 줄의 `precise` 를 빼지 마십시오. **여기가 증폭기입니다.**
    //
    //    `variance` 는 평탄한 영역에서 **0 에 아주 가깝습니다.** 그런데 `eps` 가 0.001 이라
    //    `1/(variance + eps)` 가 앞 단계의 마지막 비트 차이를 최대 **1000배로** 키웁니다.
    //    박스 블러 러닝 섬의 1 ulp 가 여기서 `2e-05`~`3.8e-05` 로 자랍니다 — 허용치 `1e-5`
    //    의 네 배입니다. 이 커널이 아니라 **박스 블러의 누적 순서**가 원인이었고
    //    (`box_blur.hlsl` 의 RGB/알파 주석), 그것을 고치니 WARP 에서 **delta 0** 입니다.
    //
    //    `precise` 는 fxc 의 FMA 축약·재배열을 막아 CPU 의 연산 순서를 지킵니다. `/Gis` 와
    //    겹치지만 둘 다 둡니다 — 플래그는 빠질 수 있고 이 표시는 소스에 남습니다.
    //
    // ⚠️ **`div` 하나만은 벤더가 갈릴 수 있고, 그것이 남은 오차의 전부입니다.**
    //    D3D11 은 add·sub·mul 에 **0.5 ULP**(정확 반올림)를 요구하지만 역수/나눗셈에는
    //    **1.0 ULP** 만 요구합니다. 이 체인에서 그 예외는 아래 `1.0 / (...)` 하나뿐입니다.
    //    실측: WARP **0**, RTX 4060 Ti **1.4e-06 ~ 4.1e-06**. 허용치 안이지만 **0 은 아니고**,
    //    다른 벤더에서도 0 이 될 것이라고 적지 마십시오.
    //    출처: https://learn.microsoft.com/en-us/windows/win32/direct3d11/floating-point-rules
    precise float variance = max(0.0, meanGuideSquared - (meanGuide * meanGuide));
    precise float3 covariance = meanGuideProduct - (meanSource * meanGuide);
    precise float reciprocal = 1.0 / (variance + Epsilon);
    precise float3 a = covariance * reciprocal;
    precise float3 b = meanSource - (a * meanGuide);

    DestinationA[coordinate] = float4(a, 0.0);
    DestinationB[coordinate] = float4(b, 0.0);
}

// 5단계 — macOS `gfApply`.
// 입력: MeanA, MeanB, Packed(가이드가 알파에 있음). 출력: 결과.
[numthreads(8, 8, 1)]
void GuidedApplyMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float3 meanA = SourceA[coordinate].rgb;
    float3 meanB = SourceB[coordinate].rgb;
    float4 packed = SourceC[coordinate];
    float guide = packed.a;
    // CPU 판 `clamp_unit` — 여기서 자릅니다.
    float3 result = clamp((meanA * guide) + meanB, 0.0, 1.0);
    DestinationA[coordinate] = float4(result, packed.a);
}
