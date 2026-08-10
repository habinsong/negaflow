#pragma once

#include "negaflow/core/pixel.h"

#include <cstddef>
#include <cstdint>
#include <functional>
#include <optional>
#include <vector>

namespace negaflow::imaging::defect_component_repair_detail {

struct ComponentBounds final {
    int min_x{0};
    int max_x{0};
    int min_y{0};
    int max_y{0};
};

struct TextureSigma final {
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
};

using ComponentCallback = std::function<void(
    const std::vector<int>&,
    const ComponentBounds&)>;

struct StructureRepairInfo final {
    std::size_t component_count{0U};
    std::size_t repaired_pixels{0U};
};

void for_each_component(
    const std::vector<std::uint8_t>& damaged,
    int width,
    int height,
    const ComponentCallback& callback);

[[nodiscard]] std::vector<std::uint8_t> refine_broad_damage_mask(
    const std::vector<negaflow::core::Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    int width,
    int height);

[[nodiscard]] StructureRepairInfo repair_component_structures(
    std::vector<negaflow::core::Rgba32F>& source,
    std::vector<negaflow::core::Rgba32F>& repaired,
    std::vector<std::uint8_t>& damaged,
    const std::vector<std::uint8_t>& damaged_original,
    int width,
    int height,
    std::optional<double> cross_angle,
    std::uint64_t& seed);

[[nodiscard]] TextureSigma grain_sigma_rgb(
    const std::vector<negaflow::core::Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    int width,
    int height,
    const ComponentBounds& bounds) noexcept;

void transfer_component_texture(
    std::vector<negaflow::core::Rgba32F>& repaired,
    const std::vector<negaflow::core::Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged_original,
    int width,
    int height,
    const std::vector<int>& filled,
    std::size_t component_count,
    const ComponentBounds& bounds,
    std::optional<double> cross_angle,
    TextureSigma sigma,
    std::uint64_t& seed);

}  // namespace negaflow::imaging::defect_component_repair_detail
