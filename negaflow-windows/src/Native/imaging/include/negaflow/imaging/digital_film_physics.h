#pragma once

#include "negaflow/imaging/film_emulation_color.h"

#include <array>

namespace negaflow::imaging {

inline constexpr char digital_film_physics_version[] =
    "chromabase-digital-film-physics-v1";

struct DigitalFilmGrainProfile final {
    double amplitude;
    double chroma_ratio;
    double size;
};

struct DigitalFilmPhysics final {
    std::array<double, 3> scatter_strength;
    std::array<double, 3> halation_strength;
    double halation_radius_ratio;
    DigitalFilmGrainProfile grain;
};

[[nodiscard]] const DigitalFilmPhysics* digital_film_physics(
    FilmEmulation emulation) noexcept;

}  // namespace negaflow::imaging
