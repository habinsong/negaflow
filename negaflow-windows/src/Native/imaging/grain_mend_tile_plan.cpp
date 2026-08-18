#include "grain_mend_tile_plan.h"

#include "grain_mend_component_classification.h"
#include "grain_mend_component_gates.h"
#include "grain_mend_components.h"
#include "grain_mend_speck_detector.h"
#include "grain_mend_structure_lines.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

namespace negaflow::imaging::grain_mend_detail {

[[nodiscard]] std::uint32_t ceil_divide(
    const std::uint32_t value,
    const std::uint32_t divisor) noexcept {
    return value / divisor + (value % divisor == 0U ? 0U : 1U);
}

[[nodiscard]] double base_dust_area(const WorkingImage& image) noexcept {
    const double long_side = static_cast<double>(
        std::max(image.width, image.height));
    const double ratio =
        long_side / static_cast<double>(grain_mend_maximum_detection_dimension);
    return std::max(
        base_maximum_dust_area,
        std::llround(ratio * ratio * base_maximum_dust_area) * 1.0);
}

[[nodiscard]] std::uint32_t minimum_scratch_length(
    const DetectionImage& tile,
    const double dust_sensitivity) noexcept {
    const auto divisor = static_cast<std::uint32_t>(
        120.0 + dust_sensitivity * 120.0);
    return std::max(
        6U,
        std::max(tile.width, tile.height) / std::max(1U, divisor));
}

[[nodiscard]] Component to_raw_component(const ClassifiedComponent& source) {
    Component component{};
    component.pixels = source.pixels;
    component.minimum_x = source.minimum_x;
    component.maximum_x = source.maximum_x;
    component.minimum_y = source.minimum_y;
    component.maximum_y = source.maximum_y;
    return component;
}

void append_mapped_core_components(
    const TileWorkspace& workspace,
    const TilePlacement& placement,
    const std::uint32_t region_width,
    const std::size_t classification_dust_area,
    std::vector<ClassifiedComponent>& mapped) {
    std::vector<Component> dust = collect_components(
        workspace.tile, workspace.evidence, workspace.evidence, 1U);
    std::vector<Component> scratch = collect_components(
        workspace.tile, workspace.evidence, workspace.evidence, 2U);
    const std::vector<std::uint8_t> keep_dust(dust.size(), 0U);
    const std::vector<std::uint8_t> keep_scratch(scratch.size(), 0U);
    std::vector<ClassifiedComponent> tile_components{};
    collect_classified(
        dust,
        keep_dust,
        scratch,
        keep_scratch,
        workspace.tile,
        &workspace.candidates,
        classification_dust_area,
        tile_components);
    if (!workspace.specks.empty()) {
        std::vector<std::uint8_t> occupancy(workspace.evidence.size(), 0U);
        std::size_t accepted = 0U;
        for (std::size_t index = 0U; index < workspace.evidence.size(); ++index) {
            if (workspace.evidence[index] != 0U) {
                occupancy[index] = 1U;
                ++accepted;
            }
        }
        merge_micro_specks_into(
            workspace.specks,
            workspace.speck_confidence,
            workspace.tile.width,
            workspace.tile.height,
            &tile_components,
            occupancy,
            accepted,
            nullptr,
            nullptr);
    }
    const std::uint32_t tile_width = workspace.tile.width;
    for (const ClassifiedComponent& component : tile_components) {
        ClassifiedComponent mapped_component = component;
        mapped_component.pixels.clear();
        std::uint32_t minimum_x = region_width;
        std::uint32_t minimum_y = std::numeric_limits<std::uint32_t>::max();
        std::uint32_t maximum_x = 0U;
        std::uint32_t maximum_y = 0U;
        for (const std::size_t pixel : component.pixels) {
            const std::uint32_t tile_x =
                static_cast<std::uint32_t>(pixel % tile_width);
            const std::uint32_t tile_y =
                static_cast<std::uint32_t>(pixel / tile_width);
            const std::uint32_t frame_x = placement.detect_x0 + tile_x;
            const std::uint32_t frame_y = placement.detect_y0 + tile_y;
            if (frame_x < placement.core_x0 || frame_x >= placement.core_x1 ||
                frame_y < placement.core_y0 || frame_y >= placement.core_y1) {
                continue;
            }
            mapped_component.pixels.push_back(
                static_cast<std::size_t>(frame_y) * region_width + frame_x);
            minimum_x = std::min(minimum_x, frame_x);
            minimum_y = std::min(minimum_y, frame_y);
            maximum_x = std::max(maximum_x, frame_x);
            maximum_y = std::max(maximum_y, frame_y);
        }
        if (mapped_component.pixels.empty()) {
            continue;
        }
        mapped_component.minimum_x = minimum_x;
        mapped_component.minimum_y = minimum_y;
        mapped_component.maximum_x = maximum_x;
        mapped_component.maximum_y = maximum_y;
        mapped.push_back(std::move(mapped_component));
    }
}

}  // namespace negaflow::imaging::grain_mend_detail
