#pragma once

#include "negaflow/core/cancel_flag.h"
#include "negaflow/core/pixel.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::imaging {

inline constexpr std::size_t defect_clone_maximum_strokes = 100'000U;
inline constexpr std::size_t defect_clone_maximum_points = 5'000'000U;
inline constexpr std::size_t defect_clone_maximum_patch_bytes =
    512U * 1'024U * 1'024U;

struct DefectClonePoint final {
    // Raw-image normalized coordinates, top-left origin (y-down).
    double x{0.0};
    double y{0.0};
};

struct DefectCloneStroke final {
    std::span<const DefectClonePoint> points{};
    // Source minus destination in normalized y-down coordinates.
    double offset_x{0.0};
    double offset_y{0.0};
    double diameter_pixels{0.0};
    double hardness{0.0};
};

struct DefectCloneParameters final {
    std::span<const DefectCloneStroke> strokes{};
    double strength{1.0};
};

enum class DefectCloneStatus : std::uint8_t {
    ok = 0,
    invalid_argument,
    kernel_failed,
    allocation_failed,
    cancelled,
};

struct DefectCloneInfo final {
    bool applied{false};
    std::size_t applied_strokes{0U};
    std::size_t patched_pixels{0U};
    std::size_t peak_patch_bytes{0U};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::ok};
};

struct DefectCloneResult final {
    DefectCloneStatus status{DefectCloneStatus::invalid_argument};
    DefectCloneInfo info{};
    WorkingImage image{};
};

// Applies one ordered Clone Stamp layer. Each full-strength stroke patch reads
// the full-strength result of the preceding stroke, is quantized to the same
// linear RGBA16 patch domain as macOS, and is then mixed into the visible image
// with the layer strength. Source pixels outside the image are ignored.
[[nodiscard]] DefectCloneResult apply_defect_clone_stamps(
    WorkingImage image,
    const DefectCloneParameters& parameters,
    negaflow::core::CancelFlag cancel = {}) noexcept;

[[nodiscard]] const char* defect_clone_status_name(
    DefectCloneStatus status) noexcept;

}  // namespace negaflow::imaging
