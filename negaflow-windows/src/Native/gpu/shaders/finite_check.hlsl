// 전 화소 유한성 확인입니다. Windows CPU 판은 `core/pixel.cpp` `validate_finite_pixels`
// 이고, 밴드 측정(`measure_parametric_tone_curve_bands`)이 맨 앞에서 부릅니다.
//
// 왜 GPU 로 옮기나 — 실측(13 문서 17절)에서 그 측정이 **전 화소를 CPU 로 두 번** 훑고
// 그 비용이 톤 단계의 절반에 가까웠습니다. 이것과 밉맵 축소가 그 두 패스입니다.
//
// ☠️ **CPU 판은 어느 행이 처음 실패했는지까지 돌려줍니다.** 이 커널은 **"있다/없다" 만**
//    말합니다. 그래서 호출부는 이렇게 씁니다:
//      · 플래그가 0 이면 — 전 화소가 유한합니다. CPU 패스를 건너뜁니다.
//      · 플래그가 1 이면 — CPU 판을 그대로 부릅니다. 어느 행인지는 그쪽이 알려 줍니다.
//    실패는 드물고, 드문 쪽에 비용을 몰아주는 것이 맞습니다.
//
// ⚠️ 알파는 보지 않습니다. CPU 판이 RGB 만 확인하기 때문입니다 — 다르게 하면 판정이 갈립니다.

Texture2D<float4> Source : register(t0);
RWStructuredBuffer<uint> Flag : register(u0);

cbuffer FiniteCheckConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
};

[numthreads(8, 8, 1)]
void FiniteCheckMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    float4 pixel = Source[id.xy];
    // `isfinite` 는 NaN 과 무한 둘 다 걸러 냅니다 — CPU 의 `std::isfinite` 와 같습니다.
    bool finite = isfinite(pixel.r) && isfinite(pixel.g) && isfinite(pixel.b);
    if (!finite) {
        // 한 스레드만 써도 충분하지만 원자로 둡니다 — 여러 스레드가 동시에 걸립니다.
        uint previous = 0U;
        InterlockedOr(Flag[0], 1U, previous);
    }
}
