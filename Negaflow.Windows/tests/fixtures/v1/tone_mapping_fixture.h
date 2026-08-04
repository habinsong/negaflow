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

inline constexpr std::array<negaflow::core::Rgba32F, 6> tone_mapping_expected{{
    {0.0739795268F, 0.284240693F, 0.967186987F, 0.25F},
    {0.0F, 0.0F, 0.0F, 1.0F},
    {0.0893102735F, 0.122946128F, 0.156581998F, 0.5F},
    {0.281710774F, 0.281710774F, 0.281710774F, 1.0F},
    {0.681074917F, 0.344716340F, 0.176537052F, 1.0F},
    {1.0F, 1.0F, 1.0F, 0.75F},
}};

}  // namespace negaflow::fixtures
