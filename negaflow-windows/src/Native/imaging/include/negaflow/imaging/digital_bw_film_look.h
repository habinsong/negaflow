#pragma once

#include "negaflow/imaging/digital_bw_emulsion_response.h"
#include "negaflow/imaging/digital_film_grain.h"
#include "negaflow/imaging/digital_halation.h"
#include "negaflow/imaging/film_emulation_acutance.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstdint>

namespace negaflow::imaging {

inline constexpr char digital_bw_film_look_algorithm_version[] =
    "chromabase-digital-bw-film-look-v1";

struct DigitalBwFilmLookParameters final {
    FilmEmulation emulation{FilmEmulation::none};
    double intensity{0.0};
    double grain_override{0.0};
    double halation_override{0.0};
};

enum class DigitalBwFilmLookStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    digital_halation_failed,
    emulsion_response_failed,
    acutance_failed,
    digital_grain_failed,
};

struct DigitalBwFilmLookInfo final {
    bool digital_halation_applied{false};
    bool emulsion_response_applied{false};
    bool acutance_applied{false};
    bool digital_grain_applied{false};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::ok};
};

struct DigitalBwFilmLookResult final {
    DigitalBwFilmLookStatus status{DigitalBwFilmLookStatus::invalid_parameter};
    DigitalBwFilmLookInfo info{};
    WorkingImage image{};
};

// GPU 사슬용 계획. 게이트는 CPU 가 한 번만 판정합니다.
struct DigitalBwFilmLookPlan final {
    DigitalHalationMaterial halation_material{};
    double halation_strength{0.0};
    bool halation_requested{false};
    DigitalBwEmulsionSetup emulsion{};
    FilmEmulationAcutanceSetup acutance{};
    DigitalFilmGrainProfile grain{0.0, 0.0, 1.0};
    double grain_strength{0.0};
    bool grain_requested{false};
};

struct DigitalBwFilmLookApplied final {
    bool halation{false};
    bool emulsion{false};
    bool acutance{false};
    bool grain{false};
};

[[nodiscard]] bool valid_digital_bw_film_look_parameters(
    const DigitalBwFilmLookParameters& parameters) noexcept;

// Fixed macOS ordering: halation -> spectral emulsion response -> acutance ->
// density grain. Any failed stage discards pixels so no partial look can publish.
[[nodiscard]] DigitalBwFilmLookResult apply_digital_bw_film_look(
    WorkingImage image,
    const DigitalBwFilmLookParameters& parameters,
    FilmEmulationAcutanceScratch acutance_scratch = {}) noexcept;

[[nodiscard]] const char* digital_bw_film_look_status_name(
    DigitalBwFilmLookStatus status) noexcept;

}  // namespace negaflow::imaging
