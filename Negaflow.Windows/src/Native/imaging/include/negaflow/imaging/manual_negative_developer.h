#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <array>
#include <cstdint>

namespace negaflow::imaging {

enum class NegativeFilmType : std::uint8_t {
    color = 0,
    black_and_white,
};

enum class ManualNegativeDevelopStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    kernel_failed,
};

struct ManualNegativeDevelopParameters final {
    std::array<float, 3> dmin;
    NegativeFilmType film_type{NegativeFilmType::color};
};

struct ManualNegativeDevelopInfo final {
    std::array<float, 3> applied_dmin{};
    std::array<float, 3> dmax_normalized{};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::invalid_argument};
};

struct ManualNegativeDevelopResult final {
    ManualNegativeDevelopStatus status{ManualNegativeDevelopStatus::invalid_parameter};
    ManualNegativeDevelopInfo info{};
    WorkingImage image{};
};

// Deterministic generic manual path matching the macOS baseline:
// - Dmin is clamped to [1e-3, 1] per channel;
// - dmaxNormalized is the selected fixed print response normal range;
// - the owned WorkingImage is transformed in place, avoiding a second full-frame buffer.
[[nodiscard]] ManualNegativeDevelopResult develop_manual_negative(
    WorkingImage image,
    const ManualNegativeDevelopParameters& parameters) noexcept;

[[nodiscard]] const char* manual_negative_develop_status_name(
    ManualNegativeDevelopStatus status) noexcept;
[[nodiscard]] const char* negative_film_type_name(NegativeFilmType film_type) noexcept;

}  // namespace negaflow::imaging
