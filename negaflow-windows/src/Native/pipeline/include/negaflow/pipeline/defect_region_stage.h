#pragma once

#include "negaflow/imaging/defect_component_repair.h"

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::pipeline {

inline constexpr std::size_t defect_region_maximum_edits = 4'096U;
inline constexpr std::size_t defect_region_maximum_mask_bytes =
    512U * 1'024U * 1'024U;

struct DefectRegionEdit final {
    bool enabled{true};
    // Raw-image pixel ROI. X is left-origin; Y is bottom-origin (y-up), matching
    // the fixed macOS recipe. Mask rows remain top-to-bottom (y-down).
    std::uint32_t roi_x{0U};
    std::uint32_t roi_y{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::span<const std::uint8_t> mask{};
    std::size_t mask_stride_bytes{0U};
    negaflow::imaging::DefectComponentRepairParameters repair{};
};

struct DefectRegionParameters final {
    // Order is semantically significant: each edit reads the result of every
    // earlier enabled edit, as in the fixed cleaned-raw recipe.
    std::vector<DefectRegionEdit> edits{};
};

enum class DefectRegionStageStatus : std::uint8_t {
    ok = 0,
    invalid_argument,
    kernel_failed,
    allocation_failed,
};

struct DefectRegionStageInfo final {
    bool applied{false};
    std::size_t applied_edit_count{0U};
    std::size_t repaired_pixels{0U};
};

struct DefectRegionStageResult final {
    DefectRegionStageStatus status{DefectRegionStageStatus::invalid_argument};
    DefectRegionStageInfo info{};
    negaflow::imaging::WorkingImage image{};
};

[[nodiscard]] DefectRegionStageResult apply_defect_region_edits(
    negaflow::imaging::WorkingImage image,
    const DefectRegionParameters& parameters) noexcept;

[[nodiscard]] const char* defect_region_stage_status_name(
    DefectRegionStageStatus status) noexcept;

}  // namespace negaflow::pipeline
