#pragma once

#include "negaflow/imaging/film_emulation_color.h"

#include <cstdint>

namespace negaflow::imaging {

enum class FilmEmulationKind : std::uint8_t {
    none = 0,
    slide,
    negative,
    black_and_white_negative,
    black_and_white_reversal,
    motion_picture,
};

[[nodiscard]] bool valid_film_emulation(FilmEmulation emulation) noexcept;
[[nodiscard]] FilmEmulationKind film_emulation_kind(
    FilmEmulation emulation) noexcept;
[[nodiscard]] bool is_black_and_white_film_emulation(
    FilmEmulation emulation) noexcept;

}  // namespace negaflow::imaging
