#pragma once

#include "negaflow/imaging/digital_film_physics.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstdint>

namespace negaflow::imaging {

inline constexpr char digital_film_grain_algorithm_version[] =
    "chromabase-digital-film-grain-cpu-v1";

struct DigitalFilmGrainParameters final {
    FilmEmulation emulation{FilmEmulation::none};
    double strength{0.0};
};

enum class DigitalFilmGrainStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    kernel_failed,
};

struct DigitalFilmGrainInfo final {
    bool applied{false};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::ok};
};

struct DigitalFilmGrainResult final {
    DigitalFilmGrainStatus status{DigitalFilmGrainStatus::invalid_parameter};
    DigitalFilmGrainInfo info{};
    WorkingImage image{};
};

[[nodiscard]] bool valid_digital_film_grain_parameters(
    const DigitalFilmGrainParameters& parameters) noexcept;

// The fixed macOS density-domain response is preserved. The random field is a
// deterministic absolute-coordinate CPU field so retries and tiles cannot drift;
// macOS/Windows grain is therefore statistical, not pixel-exact, until a shared
// seed contract exists in the product recipe.
[[nodiscard]] DigitalFilmGrainResult apply_digital_film_grain(
    WorkingImage image,
    const DigitalFilmGrainParameters& parameters) noexcept;

[[nodiscard]] DigitalFilmGrainResult apply_digital_film_grain_material(
    WorkingImage image,
    const DigitalFilmGrainProfile& profile,
    double strength) noexcept;

[[nodiscard]] const char* digital_film_grain_status_name(
    DigitalFilmGrainStatus status) noexcept;

}  // namespace negaflow::imaging
