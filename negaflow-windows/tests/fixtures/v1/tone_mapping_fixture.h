#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/working_tone_adjuster.h"

#include <array>
#include <string_view>

namespace negaflow::fixtures {

inline constexpr std::string_view tone_mapping_fixture_id = "tone-mapping-scalar-v1";
inline constexpr float tone_mapping_absolute_tolerance = 4.0e-6F;
inline constexpr float tone_mapping_relative_tolerance = 4.0e-6F;

// Repository-owned synthetic fixture transcribed independently from the macOS Float32 formulas.
// Its 3x2 dimensions intentionally select the macOS fixed parametric-band fallback.
inline constexpr std::array<negaflow::core::Rgba32F, 6> tone_mapping_input{{
    {-0.10F, 0.18F, 1.10F, 0.25F},
    {0.0F, 0.0F, 0.0F, 1.0F},
    {0.02F, 0.04F, 0.06F, 0.5F},
    {0.18F, 0.18F, 0.18F, 1.0F},
    {0.40F, 0.20F, 0.10F, 1.0F},
    {1.20F, 0.90F, 0.60F, 0.75F},
}};

inline constexpr negaflow::imaging::WorkingToneAdjustParameters
    tone_mapping_parameters{
        0.75F,
        {0.35F, 0.20F, -0.15F, 0.25F, 0.10F, -0.20F},
        {0.30F, -0.25F, 0.20F, 0.40F},
    };

// 2026-10-14: + 노출 숄더와 채널비 보존 어둡힘 이후 값. macOS Metal 경로(ToneMapper.applyExposure +
// applyToneCurves, 같은 입력·알파 1)로 계산한 결과이며 Windows CPU 판과 3e-7 안에서 일치했습니다.
// 2026-10-27: + 밝힘 chroma 접기(`withLuma`: 한 채널이 1 을 넘으면 채널별로 자르지 않고 목표 휘도를
// 지킨 채 chroma 만 줄임) 이후 값. 같은 맥 경로로 다시 계산했고, 영향받은 화소는 0 번(범위 밖
// 입력)과 5 번(밝은 주황 — 목표 휘도가 1 이라 흰색)뿐입니다. 나머지 네 화소는 이전 값과 같습니다.
// 2026-11-08: + 기본 톤 단조 합성(단계마다 앞 단계의 출력에 겁니다)과 파라메트릭 커브의 단조 PCHIP
// 매듭(이 3×2 화소는 측정 대신 기본 매듭 0.125·0.375·0.625·0.875)으로 바꾼 뒤 같은 맥 경로로 다시
// 계산했습니다. 2 번(어두운 화소)은 예전 커브가 선형 휘도에 0.16 × 0.4 를 더해 크게 들렸던 값이고,
// 5 번은 명부가 1 아래에 남습니다.
inline constexpr std::array<negaflow::core::Rgba32F, 6> tone_mapping_expected{{
    {0.101438656F, 0.288661033F, 0.903820217F, 0.25F},
    {0.0F, 0.0F, 0.0F, 1.0F},
    {0.0490359515F, 0.079209879F, 0.109383807F, 0.5F},
    {0.281021863F, 0.281021863F, 0.281021863F, 1.0F},
    {0.652404845F, 0.340023279F, 0.183832496F, 1.0F},
    {1.0F, 0.987765789F, 0.975531578F, 0.75F},
}};

}  // namespace negaflow::fixtures
