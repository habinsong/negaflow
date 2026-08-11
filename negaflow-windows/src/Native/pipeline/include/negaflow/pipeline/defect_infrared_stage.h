#pragma once

#include "negaflow/imaging/defect_component_repair.h"

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::pipeline {

struct DefectInfraredEdit final {
    bool enabled{true};
    std::uint32_t roi_x{0U};
    std::uint32_t roi_y{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::span<const std::uint8_t> core_mask{};
    std::size_t core_mask_stride_bytes{0U};
    // Optional ROI-local top-first little-endian R16 attenuation.
    std::span<const std::uint8_t> attenuation_r16{};
    std::size_t attenuation_stride_bytes{0U};
    double strength{1.0};
};

struct DefectInfraredItem final {
    bool enabled{true};
    double strength{1.0};
    std::vector<DefectInfraredEdit> clusters{};
};

enum class DefectInfraredStageStatus : std::uint8_t {
    ok = 0,
    invalid_argument,
    kernel_failed,
    repair_failed,
    allocation_failed,
};

struct DefectInfraredStageInfo final {
    bool applied{false};
    std::size_t attenuated_pixels{0U};
    std::size_t repaired_pixels{0U};
    negaflow::imaging::DefectComponentRepairStatus repair_status{
        negaflow::imaging::DefectComponentRepairStatus::ok};
};

struct DefectInfraredStageResult final {
    DefectInfraredStageStatus status{DefectInfraredStageStatus::invalid_argument};
    DefectInfraredStageInfo info{};
    negaflow::imaging::WorkingImage image{};
};

[[nodiscard]] DefectInfraredStageResult apply_defect_infrared_edit(
    negaflow::imaging::WorkingImage image,
    const DefectInfraredEdit& edit) noexcept;

[[nodiscard]] DefectInfraredStageResult apply_defect_infrared_item(
    negaflow::imaging::WorkingImage image,
    const DefectInfraredItem& item) noexcept;

[[nodiscard]] const char* defect_infrared_stage_status_name(
    const DefectInfraredStageResult& result) noexcept;

}  // namespace negaflow::pipeline
