#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/color_grading.h"

#include <array>
#include <string_view>

namespace negaflow::fixtures {

inline constexpr std::string_view color_grading_fixture_id =
    "color-grading-scalar-v1";
inline constexpr float color_grading_absolute_tolerance = 2.0e-5F;
inline constexpr float color_grading_relative_tolerance = 2.0e-5F;

// Repository-owned synthetic fixture calculated independently from the macOS
// colorGrade Float32 formula. This is not an actual Core Image render golden.
inline constexpr negaflow::imaging::ColorGradingParameters
    color_grading_parameters{
        {30.0F, 0.8F, -0.25F},
        {205.0F, 0.55F, 0.3F},
        {315.0F, 0.7F, -0.15F},
        0.65F,
        -0.25F,
    };

inline constexpr std::array<negaflow::core::Rgba32F, 12>
    color_grading_input{{
        {-0.2F, 0.3F, 1.2F, 0.25F},
        {0.05F, 0.05F, 0.05F, 1.0F},
        {0.18F, 0.18F, 0.18F, 0.75F},
        {0.35F, 0.30F, 0.25F, 0.5F},
        {0.5F, 0.5F, 0.5F, 0.2F},
        {0.65F, 0.55F, 0.45F, 0.9F},
        {0.82F, 0.82F, 0.82F, 1.0F},
        {0.95F, 0.90F, 0.85F, 0.4F},
        {0.62F, 0.30F, 0.30F, 1.0F},
        {0.10F, 0.68F, 0.72F, 0.6F},
        {1.2F, -0.1F, 0.2F, 1.0F},
        {0.52F, 0.50F, 0.49F, 0.8F},
    }};

inline constexpr std::array<negaflow::core::Rgba32F, 12>
    color_grading_expected{{
        {0.0F, 0.245708153F, 1.0F, 0.25F},
        {0.252880007F, 0.0F, 0.0F, 1.0F},
        {0.349669158F, 0.111149028F, 0.0F, 0.75F},
        {0.500740767F, 0.253330857F, 0.201340303F, 0.5F},
        {0.692804575F, 0.436151803F, 0.725924671F, 0.2F},
        {0.885054827F, 0.458310753F, 0.701643050F, 0.9F},
        {1.0F, 0.646956265F, 1.0F, 1.0F},
        {1.0F, 0.726956248F, 1.0F, 0.4F},
        {0.765497327F, 0.262025595F, 0.371928036F, 1.0F},
        {0.332186401F, 0.590211987F, 0.970158637F, 0.6F},
        {1.0F, 0.0F, 0.0F, 1.0F},
        {0.715183377F, 0.434591770F, 0.717549205F, 0.8F},
    }};

}  // namespace negaflow::fixtures
