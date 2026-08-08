#pragma once

#include "negaflow/core/pixel.h"

#include <array>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {

inline constexpr char film_emulation_color_algorithm_version[] =
    "chromabase-film-emulation-color-v1";
inline constexpr std::uint32_t film_emulation_cube_dimension = 33U;
inline constexpr std::size_t film_emulation_cube_entry_count =
    static_cast<std::size_t>(film_emulation_cube_dimension) *
    film_emulation_cube_dimension * film_emulation_cube_dimension;

enum class FilmEmulation : std::uint8_t {
    none = 0,
    ektachrome_e100,
    provia_100f,
    velvia_50,
    portra_160,
    portra_400,
    portra_800,
    ektar_100,
    ultramax_400,
    colorplus_200,
    fujicolor_c200,
    pro_400h,
};

struct FilmEmulationColorParameters final {
    FilmEmulation emulation{FilmEmulation::none};
    double intensity{0.5};
};

struct FilmEmulationCubeEntry final {
    float red;
    float green;
    float blue;
};

static_assert(sizeof(FilmEmulationCubeEntry) == 12U);

// The caller owns this bounded 33^3 RGB cube so allocation policy remains
// outside the pointwise math. Allocate it on the heap, not on the stack.
struct FilmEmulationColorCube final {
    std::array<FilmEmulationCubeEntry, film_emulation_cube_entry_count> entries;
    FilmEmulation emulation{FilmEmulation::none};
    std::uint32_t intensity_step{0U};
    bool ready{false};
};

inline constexpr std::size_t film_emulation_color_cube_bytes =
    sizeof(FilmEmulationCubeEntry) * film_emulation_cube_entry_count;

[[nodiscard]] bool valid_film_emulation_color_parameters(
    const FilmEmulationColorParameters& parameters) noexcept;
[[nodiscard]] bool has_film_emulation_color_change(
    const FilmEmulationColorParameters& parameters) noexcept;
[[nodiscard]] std::uint32_t film_emulation_intensity_step(
    const FilmEmulationColorParameters& parameters) noexcept;

// Builds the same bounded procedural cube shape as the macOS color substage.
// Spatial acutance is intentionally outside this contract.
[[nodiscard]] negaflow::core::KernelStatus build_film_emulation_color_cube(
    const FilmEmulationColorParameters& parameters,
    FilmEmulationColorCube& cube) noexcept;

// Input/output is extended-linear sRGB. Active input is converted to the sRGB
// cube domain, clamped to [0, 1], sampled trilinearly, and converted back to
// linear working RGB. Identity preserves extended RGB and alpha bit exactly.
// Input and output may alias.
[[nodiscard]] negaflow::core::KernelStatus apply_film_emulation_color_cube(
    negaflow::core::ConstImageView input,
    negaflow::core::ImageView output,
    const FilmEmulationColorParameters& parameters,
    const FilmEmulationColorCube* cube) noexcept;

}  // namespace negaflow::imaging
