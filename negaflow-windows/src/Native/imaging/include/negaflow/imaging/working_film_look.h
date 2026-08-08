#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/film_emulation_acutance.h"
#include "negaflow/imaging/film_emulation_color.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {

inline constexpr char working_film_look_algorithm_version[] =
    "chromabase-working-film-look-v1";

enum class DevelopSourceKind : std::uint8_t {
    film_scan = 0,
    rendered_digital,
};

enum class FilmLookRoute : std::uint8_t {
    invalid = 0,
    identity,
    film_scan_emulation,
    digital_film_look,
};

enum class WorkingFilmLookStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    unsupported_route,
    kernel_failed,
};

struct WorkingFilmLookParameters final {
    DevelopSourceKind source_kind{DevelopSourceKind::film_scan};
    FilmEmulation emulation{FilmEmulation::none};
    double intensity{0.5};
};

// The caller retains both reusable resources. The color cube is built only
// when its profile/quantized intensity does not match. Acutance scratch is
// width-bounded and may be empty for an identity route.
struct WorkingFilmLookWorkspace final {
    FilmEmulationColorCube* color_cube{nullptr};
    FilmEmulationAcutanceScratch acutance{};
};

struct WorkingFilmLookInfo final {
    FilmLookRoute route{FilmLookRoute::invalid};
    bool color_cube_built{false};
    bool color_cube_reused{false};
    bool color_applied{false};
    bool acutance_applied{false};
    std::uint32_t color_intensity_step{0U};
    double acutance_amount{0.0};
    std::size_t required_acutance_scratch_pixels{0U};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::ok};
};

struct WorkingFilmLookResult final {
    WorkingFilmLookStatus status{WorkingFilmLookStatus::invalid_parameter};
    WorkingFilmLookInfo info{};
    WorkingImage image{};
};

[[nodiscard]] bool valid_working_film_look_parameters(
    const WorkingFilmLookParameters& parameters) noexcept;

// The route is explicit and never inferred from a path, decoder, film type, or
// pixel statistics. Active rendered-digital input resolves to the future
// complete DigitalFilmLook route rather than reusing the film-scan subset.
[[nodiscard]] bool try_resolve_film_look_route(
    const WorkingFilmLookParameters& parameters,
    FilmLookRoute& route) noexcept;

// Applies only a complete route. Film scans run color then acutance in place.
// Active rendered-digital requests fail closed until their complete graph is
// implemented. Any failure discards pixels so a partial look cannot publish.
// kernel_status is meaningful when status is kernel_failed.
[[nodiscard]] WorkingFilmLookResult apply_working_film_look(
    WorkingImage image,
    const WorkingFilmLookParameters& parameters,
    WorkingFilmLookWorkspace workspace = {}) noexcept;

[[nodiscard]] const char* develop_source_kind_name(
    DevelopSourceKind source_kind) noexcept;
[[nodiscard]] const char* film_look_route_name(FilmLookRoute route) noexcept;
[[nodiscard]] const char* working_film_look_status_name(
    WorkingFilmLookStatus status) noexcept;

}  // namespace negaflow::imaging
