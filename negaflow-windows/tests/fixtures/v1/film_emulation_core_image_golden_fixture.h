#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/film_emulation_acutance.h"
#include "negaflow/imaging/film_emulation_color.h"

#include <array>
#include <cstdint>
#include <string_view>

namespace negaflow::fixtures {

inline constexpr std::string_view film_emulation_core_image_fixture_id =
    "film-emulation-core-image-v1";
inline constexpr std::string_view film_emulation_core_image_baseline_commit =
    "2fa1d6297378673b58b8bec72025e968ccc3125c";
inline constexpr std::string_view film_emulation_core_image_runner_commit =
    "6d9994f00f8ce3ad8c05c3ac3ae9ae33e78f0c22";
inline constexpr std::string_view film_emulation_core_image_operating_system =
    "macOS 26.5.2 (25F84)";
inline constexpr float film_emulation_core_image_color_absolute_tolerance =
    2.1e-3F;
inline constexpr float film_emulation_core_image_acutance_absolute_tolerance =
    4.0e-4F;

inline constexpr std::array<negaflow::imaging::FilmEmulationCubeEntry, 12>
    film_emulation_core_image_color_expected{{
        {0.0F, 0.349415243F, 0.999994218F},
        {0.894700944F, 0.283593684F, 0.293040901F},
        {0.924774647F, 0.667105854F, 0.0100071356F},
        {0.0790485889F, 0.904135227F, 0.217947617F},
        {0.00822509546F, 0.91256988F, 0.924669743F},
        {0.113492958F, 0.173543185F, 0.952860832F},
        {0.894700944F, 0.0881066695F, 0.918824613F},
        {0.60081923F, 0.590054214F, 0.591605306F},
        {0.00647022482F, 0.00711148418F, 0.00856169313F},
        {0.987223744F, 0.958691061F, 0.904141843F},
        {1.0F, 0.0F, 0.238664478F},
        {0.441733211F, 0.325765729F, 0.21854189F},
    }};

struct FilmEmulationAcutanceProfileSignature final {
    negaflow::imaging::FilmEmulation emulation;
    double radius;
    double intensity;
};

inline constexpr std::array<FilmEmulationAcutanceProfileSignature, 12>
    film_emulation_acutance_profile_signatures{{
        {negaflow::imaging::FilmEmulation::none, 1.0, 0.0},
        {negaflow::imaging::FilmEmulation::ektachrome_e100, 1.0, 0.12},
        {negaflow::imaging::FilmEmulation::provia_100f, 1.1, 0.20},
        {negaflow::imaging::FilmEmulation::velvia_50, 1.2, 0.22},
        {negaflow::imaging::FilmEmulation::portra_160, 1.0, 0.08},
        {negaflow::imaging::FilmEmulation::portra_400, 1.0, 0.05},
        {negaflow::imaging::FilmEmulation::portra_800, 1.0, 0.03},
        {negaflow::imaging::FilmEmulation::ektar_100, 1.0, 0.16},
        {negaflow::imaging::FilmEmulation::ultramax_400, 1.0, 0.04},
        {negaflow::imaging::FilmEmulation::colorplus_200, 1.0, 0.07},
        {negaflow::imaging::FilmEmulation::fujicolor_c200, 1.0, 0.06},
        {negaflow::imaging::FilmEmulation::pro_400h, 1.0, 0.04},
    }};

enum class FilmEmulationAcutancePattern : std::uint8_t {
    neutral_impulse = 0,
    saturated_step,
};

struct FilmEmulationAcutanceGoldenCase final {
    negaflow::imaging::FilmEmulation emulation;
    FilmEmulationAcutancePattern pattern;
    std::array<negaflow::core::Rgba32F, 9> expected_center_samples;
};

inline constexpr std::uint32_t film_emulation_acutance_sample_x_begin = 12U;

inline constexpr std::array<FilmEmulationAcutanceGoldenCase, 6>
    film_emulation_acutance_golden_cases{{
        {
            negaflow::imaging::FilmEmulation::ektar_100,
            FilmEmulationAcutancePattern::neutral_impulse,
            {{
                {0.25F, 0.25F, 0.25F, 1.0F},
                {0.249824136F, 0.249824136F, 0.249824136F, 1.0F},
                {0.248143628F, 0.248143628F, 0.248143628F, 1.0F},
                {0.242594033F, 0.242594033F, 0.242594033F, 1.0F},
                {0.818255961F, 0.818255961F, 0.818255961F, 1.0F},
                {0.242594033F, 0.242594033F, 0.242594033F, 1.0F},
                {0.248143628F, 0.248143628F, 0.248143628F, 1.0F},
                {0.249824136F, 0.249824136F, 0.249824136F, 1.0F},
                {0.25F, 0.25F, 0.25F, 1.0F},
            }},
        },
        {
            negaflow::imaging::FilmEmulation::ektar_100,
            FilmEmulationAcutancePattern::saturated_step,
            {{
                {0.649964809F, 0.0999960899F, 0.0800007805F, 1.0F},
                {0.65051192F, 0.099468492F, 0.0799226165F, 1.0F},
                {0.655905187F, 0.0941143185F, 0.0791409835F, 1.0F},
                {0.677126527F, 0.0727757737F, 0.0760437697F, 1.0F},
                {0.0727757737F, 0.677087426F, 0.163948804F, 1.0F},
                {0.0941143185F, 0.655827045F, 0.160841808F, 1.0F},
                {0.099468492F, 0.65051192F, 0.160079718F, 1.0F},
                {0.0999960899F, 0.649964809F, 0.160001561F, 1.0F},
                {0.0999960899F, 0.649964809F, 0.160001561F, 1.0F},
            }},
        },
        {
            negaflow::imaging::FilmEmulation::provia_100f,
            FilmEmulationAcutancePattern::neutral_impulse,
            {{
                {0.25F, 0.25F, 0.25F, 1.0F},
                {0.249609381F, 0.249609381F, 0.249609381F, 1.0F},
                {0.247412115F, 0.247412115F, 0.247412115F, 1.0F},
                {0.241650388F, 0.241650388F, 0.241650388F, 1.0F},
                {0.837695301F, 0.837695301F, 0.837695301F, 1.0F},
                {0.241650388F, 0.241650388F, 0.241650388F, 1.0F},
                {0.247412115F, 0.247412115F, 0.247412115F, 1.0F},
                {0.249658197F, 0.249658197F, 0.249658197F, 1.0F},
                {0.25F, 0.25F, 0.25F, 1.0F},
            }},
        },
        {
            negaflow::imaging::FilmEmulation::provia_100f,
            FilmEmulationAcutancePattern::saturated_step,
            {{
                {0.650019526F, 0.100004882F, 0.080033198F, 1.0F},
                {0.651289046F, 0.098808594F, 0.0798378885F, 1.0F},
                {0.659589827F, 0.0905322284F, 0.0786293894F, 1.0F},
                {0.685664058F, 0.0642871112F, 0.0748085901F, 1.0F},
                {0.0642382801F, 0.685712874F, 0.165217772F, 1.0F},
                {0.0905810595F, 0.659394503F, 0.161409169F, 1.0F},
                {0.098808594F, 0.651191354F, 0.160212889F, 1.0F},
                {0.100004882F, 0.650019526F, 0.160066396F, 1.0F},
                {0.100004882F, 0.650019526F, 0.160066396F, 1.0F},
            }},
        },
        {
            negaflow::imaging::FilmEmulation::velvia_50,
            FilmEmulationAcutancePattern::neutral_impulse,
            {{
                {0.249946296F, 0.249946296F, 0.249946296F, 1.0F},
                {0.249409184F, 0.249409184F, 0.249409184F, 1.0F},
                {0.246938482F, 0.246938482F, 0.246938482F, 1.0F},
                {0.241782233F, 0.241782233F, 0.241782233F, 1.0F},
                {0.848559558F, 0.848559558F, 0.848559558F, 1.0F},
                {0.241782233F, 0.241782233F, 0.241782233F, 1.0F},
                {0.246938482F, 0.246938482F, 0.246938482F, 1.0F},
                {0.249409184F, 0.249409184F, 0.249409184F, 1.0F},
                {0.249946296F, 0.249946296F, 0.249946296F, 1.0F},
            }},
        },
        {
            negaflow::imaging::FilmEmulation::velvia_50,
            FilmEmulationAcutancePattern::saturated_step,
            {{
                {0.650343716F, 0.0998173878F, 0.0799828097F, 1.0F},
                {0.652384758F, 0.0977763683F, 0.0796874017F, 1.0F},
                {0.663019478F, 0.0872221664F, 0.0781566352F, 1.0F},
                {0.691056609F, 0.059104491F, 0.0740611777F, 1.0F},
                {0.059104491F, 0.691056609F, 0.165981248F, 1.0F},
                {0.0872221664F, 0.663019478F, 0.161899209F, 1.0F},
                {0.0977763683F, 0.652384758F, 0.160368457F, 1.0F},
                {0.0998173878F, 0.650343716F, 0.160073042F, 1.0F},
                {0.100018799F, 0.650128901F, 0.160019338F, 1.0F},
            }},
        },
    }};

}  // namespace negaflow::fixtures
