#pragma once

#include "negaflow/imaging/grain_mend_classifier.h"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <vector>

namespace negaflow::imaging {

inline constexpr std::uint32_t grain_mend_review_dust_dilate_radius = 2U;
inline constexpr std::uint32_t grain_mend_review_scratch_dilate_radius = 3U;
inline constexpr std::uint32_t grain_mend_repair_context_radius = 264U;
inline constexpr std::uint32_t grain_mend_review_window_padding =
    grain_mend_repair_context_radius + grain_mend_review_scratch_dilate_radius;

enum class GrainMendAcceptedRegionStatus : std::uint8_t {
    ok = 0U,
    empty,
    invalid_geometry,
    allocation_failed,
};

struct GrainMendAcceptedRegion final {
    GrainMendAcceptedRegionStatus status{
        GrainMendAcceptedRegionStatus::invalid_geometry};
    // Raw source coordinates are top-first. Only the persisted recipe conversion is y-up.
    std::uint32_t roi_x{0U};
    std::uint32_t roi_y{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::size_t included_component_count{0U};
    std::size_t marked_pixel_count{0U};
    std::vector<std::uint8_t> rgba{};
};

// Owns the exact classified component pixels for one transient Auto/Guided review.
// Exact pixels never enter a recipe or sidecar; build_accepted() reduces them to the
// existing cropped RGBA8 region edit only when the user accepts the proposal.
class GrainMendReview final {
public:
    GrainMendReview(
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t source_width,
        std::uint32_t source_height,
        std::uint32_t roi_x,
        std::uint32_t roi_y,
        std::uint32_t roi_width,
        std::uint32_t roi_height,
        std::vector<grain_mend_detail::ClassifiedComponent> components);

    [[nodiscard]] bool valid() const noexcept { return valid_; }
    [[nodiscard]] std::uint32_t width() const noexcept { return width_; }
    [[nodiscard]] std::uint32_t height() const noexcept { return height_; }
    [[nodiscard]] const std::vector<grain_mend_detail::ClassifiedComponent>&
    components() const noexcept { return components_; }

    [[nodiscard]] std::size_t preview_point_count() const noexcept;

    // Matches DefectLabelField.nearestComponentID: exact ownership first, then square
    // rings; the last label visited in the first non-empty ring wins.
    [[nodiscard]] std::optional<std::size_t> nearest_component(
        std::int32_t x,
        std::int32_t y,
        std::uint32_t radius) const noexcept;

    [[nodiscard]] GrainMendAcceptedRegion build_accepted(
        std::span<const std::uint8_t> excluded) const noexcept;

private:
    struct LabelEntry final {
        std::size_t pixel{0U};
        std::uint32_t component{0U};
        bool is_scratch{false};
    };

    [[nodiscard]] std::optional<std::size_t> owner(std::size_t pixel) const noexcept;

    std::uint32_t width_{0U};
    std::uint32_t height_{0U};
    std::uint32_t source_width_{0U};
    std::uint32_t source_height_{0U};
    std::uint32_t roi_x_{0U};
    std::uint32_t roi_y_{0U};
    std::vector<grain_mend_detail::ClassifiedComponent> components_{};
    std::vector<LabelEntry> labels_{};
    bool valid_{false};
};

}  // namespace negaflow::imaging
