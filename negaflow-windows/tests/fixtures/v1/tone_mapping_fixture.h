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
inline constexpr std::array<negaflow::core::Rgba32F, 6> tone_mapping_expected{{
    {0.0980727226F, 0.284595937F, 0.897457898F, 0.25F},
    {0.0F, 0.0F, 0.0F, 1.0F},
    {0.0931359679F, 0.122321256F, 0.151506543F, 0.5F},
    {0.281710714F, 0.281710714F, 0.281710714F, 1.0F},
    {0.669849932F, 0.347121775F, 0.185757712F, 1.0F},
    {1.0F, 1.0F, 1.0F, 0.75F},
}};

}  // namespace negaflow::fixtures
