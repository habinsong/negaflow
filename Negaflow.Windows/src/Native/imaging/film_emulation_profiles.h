#pragma once

#include "negaflow/imaging/film_emulation_color.h"

#include <array>

namespace negaflow::imaging::detail {

struct FilmRgb64 final {
    double red;
    double green;
    double blue;
};

struct FilmToneCurve final {
    double contrast;
    double black;
    double white;
    double lift;
    double pivot;
};

struct FilmEmulationColorProfile final {
    FilmToneCurve tone_red;
    FilmToneCurve tone_green;
    FilmToneCurve tone_blue;
    FilmRgb64 matrix_red;
    FilmRgb64 matrix_green;
    FilmRgb64 matrix_blue;
    FilmRgb64 shadow_tint;
    FilmRgb64 highlight_tint;
    double exposure_saturation;
    std::array<double, 6> hue_saturation_weights;
};

[[nodiscard]] const FilmEmulationColorProfile* film_emulation_color_profile(
    FilmEmulation emulation) noexcept;

}  // namespace negaflow::imaging::detail
