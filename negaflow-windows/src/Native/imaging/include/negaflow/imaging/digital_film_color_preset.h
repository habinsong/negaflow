#pragma once

#include "negaflow/imaging/color_grading.h"
#include "negaflow/imaging/color_mixer.h"
#include "negaflow/imaging/film_emulation_color.h"
#include "negaflow/imaging/primary_calibration.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {

inline constexpr char digital_film_color_preset_algorithm_version[] =
    "chromabase-digital-film-color-preset-cpu-v1";
inline constexpr std::size_t digital_film_color_preset_scratch_target_pixels =
    1U << 20U;

struct DigitalFilmColorPreset final {
    ColorMixerParameters mixer{};
    ColorGradingParameters grading{};
    PrimaryCalibrationParameters calibration{};
};

struct DigitalFilmColorPresetParameters final {
    FilmEmulation emulation{FilmEmulation::none};
    double intensity{0.0};
};

enum class DigitalFilmColorPresetStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    allocation_failed,
    kernel_failed,
};

struct DigitalFilmColorPresetInfo final {
    bool applied{false};
    std::size_t scratch_peak_bytes{0U};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::ok};
};

struct DigitalFilmColorPresetResult final {
    DigitalFilmColorPresetStatus status{
        DigitalFilmColorPresetStatus::invalid_parameter};
    DigitalFilmColorPresetInfo info{};
    WorkingImage image{};
};

[[nodiscard]] const DigitalFilmColorPreset* digital_film_color_preset(
    FilmEmulation emulation) noexcept;

[[nodiscard]] bool valid_digital_film_color_preset_parameters(
    const DigitalFilmColorPresetParameters& parameters) noexcept;

[[nodiscard]] DigitalFilmColorPresetResult apply_digital_film_color_preset(
    WorkingImage image,
    const DigitalFilmColorPresetParameters& parameters) noexcept;

[[nodiscard]] const char* digital_film_color_preset_status_name(
    DigitalFilmColorPresetStatus status) noexcept;

}  // namespace negaflow::imaging
