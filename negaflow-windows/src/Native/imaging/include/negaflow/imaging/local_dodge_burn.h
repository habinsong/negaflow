#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging {

inline constexpr char local_dodge_burn_algorithm_version[] =
    "chromabase-local-dodge-burn-cpu-v1";
inline constexpr std::size_t local_dodge_burn_maximum_adjustments = 64U;
inline constexpr std::size_t local_dodge_burn_maximum_strokes_per_mask = 128U;
inline constexpr std::size_t local_dodge_burn_maximum_points = 4096U;

struct LocalDodgeBurnPoint final {
    float x{0.5F};
    float y{0.5F};
};

struct LocalDodgeBurnStroke final {
    std::vector<LocalDodgeBurnPoint> points{};
    float thickness{0.04F};
    float feather{0.02F};
};

enum class LocalDodgeBurnMaskKind : std::uint8_t {
    brush = 0,
    radial,
    linear,
    polygon,
};

struct LocalDodgeBurnMask final {
    LocalDodgeBurnMaskKind kind{LocalDodgeBurnMaskKind::brush};
    std::vector<LocalDodgeBurnStroke> strokes{};
    LocalDodgeBurnPoint center{};
    float radius{0.25F};
    float feather{0.25F};
    LocalDodgeBurnPoint start{0.5F, 0.0F};
    LocalDodgeBurnPoint end{0.5F, 1.0F};
    std::vector<LocalDodgeBurnPoint> points{};
};

enum class LocalDodgeBurnMode : std::uint8_t {
    dodge = 0,
    burn,
};

struct LocalDodgeBurnAdjustment final {
    LocalDodgeBurnMode mode{LocalDodgeBurnMode::dodge};
    float amount{0.0F};
    bool enabled{true};
    LocalDodgeBurnMask mask{};
};

struct LocalDodgeBurnParameters final {
    std::vector<LocalDodgeBurnAdjustment> adjustments{};
};

enum class LocalDodgeBurnStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    kernel_failed,
    allocation_failed,
};

struct LocalDodgeBurnInfo final {
    bool applied{false};
    std::size_t adjustments_applied{0U};
    std::size_t mask_scratch_peak_bytes{0U};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::ok};
};

struct LocalDodgeBurnResult final {
    LocalDodgeBurnStatus status{LocalDodgeBurnStatus::invalid_parameter};
    LocalDodgeBurnInfo info{};
    WorkingImage image{};
};

[[nodiscard]] bool valid_local_dodge_burn_parameters(
    const LocalDodgeBurnParameters& parameters) noexcept;

// Applies enabled adjustments in order, matching CIBlendWithMask over
// CIExposureAdjust. Coordinates are normalized to the image and alpha is
// preserved. A failure discards pixels so no partial adjustment is published.
[[nodiscard]] LocalDodgeBurnResult apply_local_dodge_burn(
    WorkingImage image,
    const LocalDodgeBurnParameters& parameters) noexcept;

[[nodiscard]] const char* local_dodge_burn_status_name(
    LocalDodgeBurnStatus status) noexcept;

}  // namespace negaflow::imaging
