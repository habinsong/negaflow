#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/film_emulation_color.h"

#include <array>
#include <string_view>

namespace negaflow::fixtures {

inline constexpr std::string_view film_emulation_color_fixture_id =
    "film-emulation-color-cube-v1";
inline constexpr float film_emulation_color_absolute_tolerance = 5.0e-5F;
inline constexpr float film_emulation_color_relative_tolerance = 5.0e-5F;

inline constexpr negaflow::imaging::FilmEmulationColorParameters
    film_emulation_color_parameters{
        negaflow::imaging::FilmEmulation::velvia_50,
        0.73,
    };

inline constexpr std::array<negaflow::core::Rgba32F, 12>
    film_emulation_color_input{{
        {-0.2F, 0.3F, 1.2F, 0.25F},
        {0.62F, 0.30F, 0.30F, 1.0F},
        {0.72F, 0.50F, 0.12F, 0.75F},
        {0.20F, 0.65F, 0.30F, 0.5F},
        {0.10F, 0.68F, 0.72F, 0.2F},
        {0.18F, 0.22F, 0.82F, 0.9F},
        {0.62F, 0.18F, 0.70F, 1.0F},
        {0.5F, 0.5F, 0.5F, 0.4F},
        {0.02F, 0.02F, 0.02F, 0.6F},
        {0.95F, 0.90F, 0.85F, 0.8F},
        {1.2F, -0.1F, 0.2F, 1.0F},
        {0.35F, 0.30F, 0.25F, 0.7F},
    }};

// Independently calculated with JavaScript Float32 transfer and trilinear
// sampling. This is not a Core Image render golden.
inline constexpr std::array<negaflow::core::Rgba32F, 12>
    film_emulation_color_expected{{
        {0.0F, 0.3475263715F, 1.0F, 0.25F},
        {0.8949480057F, 0.2835310400F, 0.2930659056F, 1.0F},
        {0.9249576330F, 0.6674498320F, 0.009928924963F, 0.75F},
        {0.07878451794F, 0.9042354226F, 0.2177673280F, 0.5F},
        {0.008163340390F, 0.9130247831F, 0.9249576330F, 0.2F},
        {0.1136861891F, 0.1733225733F, 0.9530426860F, 0.9F},
        {0.8950446844F, 0.08804196864F, 0.9191339612F, 1.0F},
        {0.6004769802F, 0.5897799730F, 0.5922223330F, 0.4F},
        {0.006466869731F, 0.007134150248F, 0.008512255736F, 0.6F},
        {0.9873597026F, 0.9573315382F, 0.9029705524F, 0.8F},
        {1.0F, 0.0F, 0.2371856421F, 1.0F},
        {0.4410558939F, 0.3252595961F, 0.2190486640F, 0.7F},
    }};

struct FilmEmulationProfileSignature final {
    negaflow::imaging::FilmEmulation emulation;
    negaflow::imaging::FilmEmulationCubeEntry expected;
};

inline constexpr std::array<FilmEmulationProfileSignature, 11>
    film_emulation_profile_signatures{{
        {negaflow::imaging::FilmEmulation::ektachrome_e100,
         {0.1947031468F, 0.5048093796F, 0.8232647777F}},
        {negaflow::imaging::FilmEmulation::provia_100f,
         {0.1223467514F, 0.4960364103F, 0.8800659180F}},
        {negaflow::imaging::FilmEmulation::velvia_50,
         {0.0F, 0.4807915986F, 1.0F}},
        {negaflow::imaging::FilmEmulation::portra_160,
         {0.2485320121F, 0.5129552484F, 0.7785375714F}},
        {negaflow::imaging::FilmEmulation::portra_400,
         {0.2423008382F, 0.5148361325F, 0.7881163359F}},
        {negaflow::imaging::FilmEmulation::portra_800,
         {0.2262144238F, 0.5186971426F, 0.8116714954F}},
        {negaflow::imaging::FilmEmulation::ektar_100,
         {0.1184210405F, 0.5039805770F, 0.8985710740F}},
        {negaflow::imaging::FilmEmulation::ultramax_400,
         {0.1958476454F, 0.5148543119F, 0.8305192590F}},
        {negaflow::imaging::FilmEmulation::colorplus_200,
         {0.2144787312F, 0.5136613250F, 0.8119668961F}},
        {negaflow::imaging::FilmEmulation::fujicolor_c200,
         {0.1957199126F, 0.5060714483F, 0.8368443847F}},
        {negaflow::imaging::FilmEmulation::pro_400h,
         {0.2590180039F, 0.5184112191F, 0.7771632075F}},
    }};

}  // namespace negaflow::fixtures
