#pragma once

#include "negaflow/imaging/film_emulation_color.h"

#include <array>

namespace negaflow::imaging {

struct DigitalBwFilmProfile final {
    std::array<double, 3> spectral_weights;
    double contrast_index;
    double toe_softness;
    double shoulder_softness;
    double latitude_stops;
    double dmax_multiplier;
    double grain_amplitude;
    double grain_size;
    double acutance_radius;
    double acutance_intensity;
    double scatter_strength;
    double halation_strength;
    double halation_radius_ratio;
    bool reversal;
};

[[nodiscard]] const DigitalBwFilmProfile* digital_bw_film_profile(
    FilmEmulation emulation) noexcept;

}  // namespace negaflow::imaging
