// 밉맵 한 단계 축소입니다. Windows CPU 판은 `imaging/mipmap_downsampler.cpp` 의 `halve`
// 이고, 이 셰이더는 그것과 화소값이 **비트 단위로 같아야** 합니다.
//
// 왜 비트 단위여야 하나 — 이 축소의 결과가 파라메트릭 톤 커브의 **밴드 백분위**로 갑니다.
// 백분위가 달라지면 밴드가 달라지고, 밴드가 달라지면 **출력 화소가 달라집니다.**
// 근사로 두면 조용히 다른 사진이 나옵니다.
//
// 비트 단위가 가능한 이유: `halve` 는 float32 덧셈 셋과 `* 0.25` 뿐입니다. 곱셈이
// 2의 거듭제곱이라 반올림도 없습니다. 덧셈 순서만 CPU 와 같게 두면 값이 같습니다.
//
// ☠️ **덧셈 순서를 바꾸지 마십시오.** CPU 는 `(a + b + c + d) * 0.25` 를 왼쪽에서
//    오른쪽으로 접습니다 — `((a + b) + c) + d`. HLSL 에서 `a + b + c + d` 도 같은
//    결합이지만, 재배열을 막으려고 `precise` 를 답니다.
//
// ⚠️ **최종 이중선형 보간은 이 커널이 하지 않습니다.** CPU 판의 `bilinear` 는 가중치와
//    누적을 `double` 로 합니다. D3D11 의 double 은 선택 기능이라 벤더에 따라 없습니다 —
//    비트 단위로 옮길 수 없습니다. 그래서 **큰 축소만 GPU 가 하고**, 마지막 작은 단계에서
//    이중선형은 CPU 가 그대로 합니다. 그때 다루는 화소는 이미 작아서 쌉니다.

Texture2D<float4> Source : register(t0);
RWTexture2D<float4> Destination : register(u0);

cbuffer MipHalveConstants : register(b0) {
    // 부모(입력)의 크기입니다. 자식(출력)은 각 변의 절반이며 최소 1 입니다.
    uint2 Extent;
    float2 Padding0;
    uint2 ChildExtent;
    float2 Padding1;
};

[numthreads(8, 8, 1)]
void MipHalveMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= ChildExtent.x || id.y >= ChildExtent.y) {
        return;
    }
    // CPU 판과 같은 좌표 계산입니다 — 홀수 변에서 마지막 화소를 두 번 읽습니다.
    uint parentLastX = Extent.x - 1U;
    uint parentLastY = Extent.y - 1U;
    uint sx = min(id.x * 2U, parentLastX);
    uint sy = min(id.y * 2U, parentLastY);
    uint sx1 = min(sx + 1U, parentLastX);
    uint sy1 = min(sy + 1U, parentLastY);

    float4 a = Source[uint2(sx, sy)];
    float4 b = Source[uint2(sx1, sy)];
    float4 c = Source[uint2(sx, sy1)];
    float4 d = Source[uint2(sx1, sy1)];

    // ☠️ `precise` 를 빼지 마십시오. fxc 가 덧셈을 재배열하거나 FMA 로 접으면
    //    마지막 비트가 달라지고, 그것이 백분위를 지나 출력 화소를 바꿉니다.
    precise float red = ((a.r + b.r) + c.r) + d.r;
    precise float green = ((a.g + b.g) + c.g) + d.g;
    precise float blue = ((a.b + b.b) + c.b) + d.b;

    // CPU 판은 알파를 계산하지 않고 **1.0 을 박습니다.** 그대로 옮깁니다.
    Destination[uint2(id.x, id.y)] = float4(red * 0.25, green * 0.25, blue * 0.25, 1.0);
}
