#pragma once

#include "negaflow/imaging/film_emulation_color.h"

namespace negaflow::imaging::detail {

struct FilmEmulationAcutanceProfileData final {
    double radius;
    double intensity;
    double gaussian_sigma;
};

[[nodiscard]] const FilmEmulationAcutanceProfileData*
film_emulation_acutance_profile_data(FilmEmulation emulation) noexcept;

}  // namespace negaflow::imaging::detail
