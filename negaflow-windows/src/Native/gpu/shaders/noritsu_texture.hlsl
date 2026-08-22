// NORITSU 장치 질감 — 감마 도메인 luminance USM.
//
// macOS : `ChromabaseMetalKernels.swift:505` `noritsuTexture`
// + `ScannerTargetGrade+Texture.swift` (`noritsuSharpenRadius = 0.9`)
// CPU 판 : `imaging/scanner_target_grade.cpp` `apply_noritsu_texture`
//
// 모양은 아큐턴스와 같습니다 — 수평 5탭 저역을 중간 텍스처에 쓰고,
// 수직 저역과 언샤프를 한 번에 합니다. 가우시안은 호스트가 만든 5탭입니다
// (σ ≈ 0.9). 셰이더에서 `exp` 로 다시 만들지 마십시오.
//
// 게이트 둘은 **순서까지** CPU/macOS 와 같습니다.
// ① `lo < 0 || hi > 1` → 원본 통과 (확장값 보존)
// ② `lumaO <= luma_gate` → 원본 통과
// 플로어 `max(yO * floor_ratio, min(yO, floor_absolute))` 의 상수 둘도
// 호스트 `ScannerTargetTextureSetup` 에서 옵니다.
// 마지막 `mx > 1` 공통 축소는 hue 보존입니다 — 채널별 클립으로 바꾸면 색이 틀어집니다.
//
// 하드 게이트가 있어 오차의 성격이 다릅니다. 경계에 앉은 화소는 1ulp 로
// 결과가 통째로 갈리고, 그때 최대 오차는 누적이 아니라 질감의 크기입니다.
// 시험은 최대 오차 + 이탈 화소 비율을 같이 겁니다.

#include "tone_shared.hlsli"

Texture2D<float4> Original : register(t1);

#define NEGAFLOW_NORITSU_TAPS 5
#define NEGAFLOW_NORITSU_SUPPORT 2
#define NEGAFLOW_NORITSU_VECTORS 2

cbuffer NoritsuTextureConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    // 배열은 원소마다 16바이트 — `float W[5]` 로 두지 마십시오.
    float4 Weights[NEGAFLOW_NORITSU_VECTORS];
    float Amount;
    float FloorRatio;
    float FloorAbsolute;
    float LumaGate;
};

float Weight(int index) {
    return Weights[index >> 2][index & 3];
}

int ClampCoordinate(int center, int offset, int upper) {
    return clamp(center + offset, 0, upper);
}

[numthreads(8, 8, 1)]
void NoritsuTextureHorizontalMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    int upper = int(Extent.x) - 1;
    float3 sum = float3(0.0, 0.0, 0.0);
    [unroll]
    for (int index = 0; index < NEGAFLOW_NORITSU_TAPS; ++index) {
        int column = ClampCoordinate(int(id.x), index - NEGAFLOW_NORITSU_SUPPORT, upper);
        sum += Source[uint2(uint(column), id.y)].rgb * Weight(index);
    }
    Destination[id.xy] = float4(sum, 1.0);
}

[numthreads(8, 8, 1)]
void NoritsuTextureVerticalMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    int upper = int(Extent.y) - 1;
    float3 blurred = float3(0.0, 0.0, 0.0);
    [unroll]
    for (int index = 0; index < NEGAFLOW_NORITSU_TAPS; ++index) {
        int row = ClampCoordinate(int(id.y), index - NEGAFLOW_NORITSU_SUPPORT, upper);
        blurred += Source[uint2(id.x, uint(row))].rgb * Weight(index);
    }

    float4 source = Original[id.xy];
    float lo = min(source.r, min(source.g, source.b));
    float hi = max(source.r, max(source.g, source.b));
    // ① 확장값 보존 — 측정 큐브 밖은 질감을 얹지 않습니다.
    if (lo < 0.0 || hi > 1.0) {
        Destination[id.xy] = source;
        return;
    }
    float lumaO = dot(source.rgb, LumaCoefficients);
    // ② 거의 검은 화소 — 이득이 luma 로 나누므로 0 폭주 방지.
    if (lumaO <= LumaGate) {
        Destination[id.xy] = source;
        return;
    }

    // CPU 는 채널을 먼저 자르지 않고 루마를 자릅니다
    // (`clamp(dot(blur), 0, 1)`). macOS 는 채널을 먼저 자릅니다.
    // Windows CPU 가 맞출 상대입니다.
    float lumaB = clamp(dot(blurred, LumaCoefficients), 0.0, 1.0);
    float yO = LinearToSrgbEncoded(lumaO);
    float yB = LinearToSrgbEncoded(lumaB);
    float floorY = max(yO * FloorRatio, min(yO, FloorAbsolute));
    float yN = clamp(yO + (Amount * (yO - yB)), floorY, 1.0);
    float gain = SrgbEncodedToLinear(yN) / lumaO;
    float maximum = hi * gain;
    if (maximum > 1.0) {
        gain /= maximum;
    }
    Destination[id.xy] = float4(source.rgb * gain, source.a);
}
