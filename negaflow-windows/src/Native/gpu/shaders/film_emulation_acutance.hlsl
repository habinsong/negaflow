// 필름 스톡 아큐턴스(분리형 11탭 가우시안 언샤프)입니다.
//
// macOS  : `FilmEmulationStage` 의 공간 성분(Core Image 내장 블러 + 언샤프)
// CPU 판 : `imaging/film_emulation_acutance.cpp` `apply_film_emulation_acutance`
//
// 두 패스입니다 — 수평 블러를 중간 텍스처에 쓰고, 수직 블러와 언샤프를 한 번에 합니다.
// CPU 도 같은 구조입니다(수평 결과를 11행짜리 링 버퍼에 캐시).
//
// ☠️ **가중치를 여기서 만들지 마십시오.** `imaging::prepare_film_emulation_acutance` 가
//    만든 것을 상수 버퍼로 받습니다. 두 곳에서 만들면 `exp` 구현 차이가 화소마다 실립니다.
//
// ⚠️ CPU 는 두 패스 모두 `double` 로 누적합니다. GPU 는 float 입니다 — 11항이라
//    누적 오차가 1e-6 대이고, 언샤프 세기(≤0.3)가 다시 눌러 출력에서는 1e-7 대입니다.
//    시험이 그 값을 고정합니다.
//
// ⚠️ 중간 텍스처는 CPU 스크래치와 같은 **float32 RGB** 반올림을 지납니다. CPU 가
//    `double` 누적을 float 로 내려 캐시하기 때문입니다 — 그 자리를 건너뛰면 값이 갈립니다.

#include "tone_shared.hlsli"

// 원본(수직 패스에서 언샤프의 기준이 됩니다).
Texture2D<float4> Original : register(t1);

// `film_emulation_acutance_scratch_rows` = 11.
#define NEGAFLOW_ACUTANCE_TAPS 11
#define NEGAFLOW_ACUTANCE_SUPPORT 5
#define NEGAFLOW_ACUTANCE_VECTORS 3

cbuffer FilmEmulationAcutanceConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    // ⚠️ HLSL 상수 버퍼의 배열은 원소마다 16바이트입니다. 11탭을 `float4[3]` 로 묶어
    //    `[i>>2][i&3]` 로 읽습니다 — `float W[11]` 로 두면 인덱싱이 어긋납니다.
    float4 Weights[NEGAFLOW_ACUTANCE_VECTORS];
    float Amount;
    float3 Padding1;
};

float Weight(int index) {
    return Weights[index >> 2][index & 3];
}

// `clamp_coordinate` 와 같습니다.
int ClampCoordinate(int center, int offset, int upper) {
    return clamp(center + offset, 0, upper);
}

[numthreads(8, 8, 1)]
void AcutanceHorizontalMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    int upper = int(Extent.x) - 1;
    float3 sum = float3(0.0, 0.0, 0.0);
    [unroll]
    for (int index = 0; index < NEGAFLOW_ACUTANCE_TAPS; ++index) {
        int column = ClampCoordinate(int(id.x), index - NEGAFLOW_ACUTANCE_SUPPORT, upper);
        sum += Source[uint2(uint(column), id.y)].rgb * Weight(index);
    }
    // 알파는 쓰이지 않습니다 — 수직 패스가 원본에서 가져옵니다. CPU 스크래치도 RGB 셋뿐입니다.
    Destination[id.xy] = float4(sum, 1.0);
}

[numthreads(8, 8, 1)]
void AcutanceVerticalMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    int upper = int(Extent.y) - 1;
    float3 blurred = float3(0.0, 0.0, 0.0);
    [unroll]
    for (int index = 0; index < NEGAFLOW_ACUTANCE_TAPS; ++index) {
        int row = ClampCoordinate(int(id.y), index - NEGAFLOW_ACUTANCE_SUPPORT, upper);
        blurred += Source[uint2(id.x, uint(row))].rgb * Weight(index);
    }
    float4 source = Original[id.xy];
    Destination[id.xy] = float4(
        source.rgb + (Amount * (source.rgb - blurred)),
        source.a);
}
