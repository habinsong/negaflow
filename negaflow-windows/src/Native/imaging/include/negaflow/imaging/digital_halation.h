#pragma once

#include "negaflow/imaging/digital_film_physics.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <array>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {

inline constexpr char digital_halation_algorithm_version[] =
    "chromabase-digital-halation-cpu-v1";
inline constexpr std::uint32_t digital_halation_tile_side = 512U;

struct DigitalHalationParameters final {
    FilmEmulation emulation{FilmEmulation::none};
    double strength{0.0};
};

struct DigitalHalationMaterial final {
    std::array<double, 3> scatter_strength{};
    std::array<double, 3> halation_strength{};
    double radius_ratio{0.0};
};

enum class DigitalHalationStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    invalid_image,
    allocation_failed,
    kernel_failed,
};

struct DigitalHalationInfo final {
    bool applied{false};
    std::size_t scratch_peak_bytes{0U};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::ok};
};

struct DigitalHalationResult final {
    DigitalHalationStatus status{DigitalHalationStatus::invalid_parameter};
    DigitalHalationInfo info{};
    WorkingImage image{};
};

[[nodiscard]] bool valid_digital_halation_parameters(
    const DigitalHalationParameters& parameters) noexcept;

[[nodiscard]] DigitalHalationResult apply_digital_halation(
    WorkingImage image,
    const DigitalHalationParameters& parameters) noexcept;

[[nodiscard]] DigitalHalationResult apply_digital_halation_material(
    WorkingImage image,
    const DigitalHalationMaterial& material,
    double strength) noexcept;

[[nodiscard]] const char* digital_halation_status_name(
    DigitalHalationStatus status) noexcept;

}  // namespace negaflow::imaging
