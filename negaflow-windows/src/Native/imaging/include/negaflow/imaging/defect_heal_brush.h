#pragma once

#include "negaflow/imaging/scanner_to_working.h"

#include <cstddef>
#include <cstdint>
#include <span>

namespace negaflow::imaging {

inline constexpr std::size_t defect_heal_brush_maximum_patch_bytes =
    512U * 1'024U * 1'024U;

struct DefectBrushPoint final {
    double x{0.0};
    double y{0.0};
};

struct DefectBrushStroke final {
    std::span<const DefectBrushPoint> points{};
    // Fraction of the raw image's shorter dimension.
    double thickness{0.0};
};

struct DefectHealBrushParameters final {
    std::span<const DefectBrushStroke> strokes{};
    double strength{1.0};
};

enum class DefectHealBrushStatus : std::uint8_t {
    ok = 0,
    invalid_argument,
    kernel_failed,
    allocation_failed,
};

struct DefectHealBrushInfo final {
    bool applied{false};
    std::size_t applied_chunk_count{0U};
    std::size_t healed_component_count{0U};
    std::size_t healed_pixels{0U};
    std::size_t fallback_chunk_count{0U};
    std::size_t peak_patch_bytes{0U};
};

struct DefectHealBrushResult final {
    DefectHealBrushStatus status{DefectHealBrushStatus::invalid_argument};
    DefectHealBrushInfo info{};
    WorkingImage image{};
};

// Applies the fixed cleaned-raw brush contract. Stroke coordinates are
// normalized raw-image coordinates with a top-left origin. Each chunk first
// tries displaced real-pixel texture transfer with low-frequency tone matching;
// an unavailable source patch falls back to the component repairer. Invalid
// input discards pixels so a partial edit cannot ship.
[[nodiscard]] DefectHealBrushResult apply_defect_heal_brush(
    WorkingImage image,
    const DefectHealBrushParameters& parameters) noexcept;

[[nodiscard]] const char* defect_heal_brush_status_name(
    DefectHealBrushStatus status) noexcept;

}  // namespace negaflow::imaging
