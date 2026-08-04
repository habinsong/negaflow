#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/color_mixer.h"

#include <array>
#include <string_view>

namespace negaflow::fixtures {

inline constexpr std::string_view color_mixer_fixture_id =
    "color-mixer-scalar-v1";
inline constexpr float color_mixer_absolute_tolerance = 2.0e-5F;
inline constexpr float color_mixer_relative_tolerance = 2.0e-5F;

// Repository-owned synthetic fixture calculated independently from the macOS
// colorMixerHSL Float32 formula. This is not an actual Core Image render golden.
inline constexpr negaflow::imaging::ColorMixerParameters color_mixer_parameters{
    {0.4F, -0.25F, 0.15F, -0.5F, 0.3F, 0.55F, -0.35F, 0.2F},
    {0.7F, -0.3F, 0.45F, -0.65F, 0.35F, 0.8F, -0.55F, 0.25F},
    {-0.25F, 0.35F, 0.5F, -0.4F, 0.2F, -0.3F, 0.6F, -0.15F},
};

inline constexpr std::array<negaflow::core::Rgba32F, 12> color_mixer_input{{
    {-0.2F, 0.3F, 1.2F, 0.25F},
    {0.62F, 0.30F, 0.30F, 1.0F},
    {0.85F, 0.42F, 0.10F, 0.75F},
    {0.78F, 0.70F, 0.18F, 0.5F},
    {0.18F, 0.72F, 0.30F, 1.0F},
    {0.10F, 0.68F, 0.72F, 0.4F},
    {0.16F, 0.30F, 0.82F, 1.0F},
    {0.50F, 0.20F, 0.72F, 1.0F},
    {0.78F, 0.18F, 0.55F, 1.0F},
    {0.50F, 0.50F, 0.50F, 0.2F},
    {0.52F, 0.50F, 0.49F, 0.9F},
    {1.2F, -0.1F, 0.2F, 1.0F},
}};

inline constexpr std::array<negaflow::core::Rgba32F, 12> color_mixer_expected{{
    {0.0F, 0.0707591176F, 0.951111257F, 0.25F},
    {0.667499781F, 0.274565786F, 0.227822483F, 1.0F},
    {0.944569945F, 0.448086768F, 0.0714207888F, 0.75F},
    {0.873304248F, 0.783815145F, 0.227441549F, 0.5F},
    {0.290205121F, 0.499363661F, 0.292068452F, 1.0F},
    {0.0F, 0.694420576F, 0.884000063F, 0.4F},
    {0.0F, 0.0155036952F, 0.939910114F, 1.0F},
    {0.527987599F, 0.235611677F, 0.754545748F, 1.0F},
    {0.844525695F, 0.0569644570F, 0.438046902F, 1.0F},
    {0.5F, 0.5F, 0.5F, 0.2F},
    {0.519999981F, 0.5F, 0.490000010F, 0.9F},
    {0.954341888F, 0.0F, 0.0576635301F, 1.0F},
}};

}  // namespace negaflow::fixtures
