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
    ektachrome_e100 = 1,
    provia_100f = 2,
    velvia_50 = 3,
    portra_160 = 4,
    portra_400 = 5,
    portra_800 = 6,
    ektar_100 = 7,
    ultramax_400 = 8,
    colorplus_200 = 9,
    fujicolor_c200 = 10,
    pro_400h = 11,
    tri_x_400 = 12,
    hp5_plus = 13,
    fp4_plus = 14,
    delta_100 = 15,
    delta_400 = 16,
    delta_3200 = 17,
    tmax_100 = 18,
    tmax_400 = 19,
    tmax_p3200 = 20,
    kentmere_400 = 21,
    ortho_plus = 22,
    sfx_200 = 23,
    rollei_ir = 24,
    scala_200x = 25,
    rollei_superpan = 26,
    velvia_100 = 27,
    e100_vs = 28,
    astia_100f = 29,
    kodachrome_64 = 30,
    gold_200 = 31,
    pro_image_100 = 32,
    superia_400 = 33,
    superia_premium_400 = 34,
    superia_200 = 35,
    reala_100 = 36,
    industrial_100 = 37,
    lomo_cn_800 = 38,
    vision3_500t = 39,
    vision3_250d = 40,
    vision3_50d = 41,
    vision3_200t = 42,
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
