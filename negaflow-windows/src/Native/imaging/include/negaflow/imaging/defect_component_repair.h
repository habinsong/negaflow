#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::imaging {

inline constexpr char defect_component_repair_algorithm_version[] =
    "chromabase-defect-component-repair-v2";

enum class DefectComponentRepairStatus : std::uint8_t {
    ok = 0,
    invalid_argument,
    kernel_failed,
    allocation_failed,
};

struct DefectComponentRepairParameters final {
    bool has_preferred_angle{false};
    double preferred_angle_degrees{0.0};
    double strength{1.0};
};

struct DefectComponentRepairInfo final {
    bool applied{false};
    std::size_t component_count{0U};
    std::size_t input_mask_pixels{0U};
    std::size_t retained_mask_pixels{0U};
    std::size_t repaired_pixels{0U};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::ok};
};

struct DefectComponentRepairResult final {
    DefectComponentRepairStatus status{
        DefectComponentRepairStatus::invalid_argument};
    DefectComponentRepairInfo info{};
    WorkingImage image{};
    // Packed one-byte blend mask in ROI-local row-major order.
    std::vector<std::uint8_t> blend_mask{};
};

// Repairs an ROI-local linear working image from a one-channel mask. Mask values
// greater than 8 are structural damage, while the full 0...255 value remains the
// final blend weight. The repair math runs in the sRGB-encoded domain used by
// the fixed macOS component repairer and converts repaired pixels back to the
// linear working image. The source alpha is preserved exactly. Invalid input or
// an allocation failure discards image pixels so a partial repair cannot ship.
[[nodiscard]] DefectComponentRepairResult repair_defect_components(
    WorkingImage image,
    const std::vector<std::uint8_t>& mask,
    std::size_t mask_stride_bytes,
    const DefectComponentRepairParameters& parameters = {}) noexcept;

[[nodiscard]] DefectComponentRepairResult repair_defect_components(
    WorkingImage image,
    std::span<const std::uint8_t> mask,
    std::size_t mask_stride_bytes,
    const DefectComponentRepairParameters& parameters = {}) noexcept;

[[nodiscard]] const char* defect_component_repair_status_name(
    DefectComponentRepairStatus status) noexcept;

}  // namespace negaflow::imaging
