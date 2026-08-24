#include "grain_mend_test_support.h"

#include "negaflow/imaging/grain_mend_review.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <initializer_list>
#include <utility>
#include <vector>

namespace grain_mend_tests {

namespace {

using negaflow::imaging::GrainMendAcceptedRegionStatus;
using negaflow::imaging::GrainMendReview;
using negaflow::imaging::grain_mend_detail::ClassifiedComponent;
using negaflow::imaging::grain_mend_detail::DefectClassification;

[[nodiscard]] ClassifiedComponent component(
    const std::uint32_t width,
    const bool scratch,
    const DefectClassification classification,
    const std::initializer_list<std::pair<std::uint32_t, std::uint32_t>> points) {
    ClassifiedComponent result{};
    result.minimum_x = width;
    result.minimum_y = width;
    result.is_scratch = scratch;
    result.classification = classification;
    result.confidence = 0.9;
    for (const auto [x, y] : points) {
        result.pixels.push_back(static_cast<std::size_t>(y) * width + x);
        result.minimum_x = std::min(result.minimum_x, x);
        result.minimum_y = std::min(result.minimum_y, y);
        result.maximum_x = std::max(result.maximum_x, x);
        result.maximum_y = std::max(result.maximum_y, y);
    }
    return result;
}

[[nodiscard]] bool marked(
    const negaflow::imaging::GrainMendAcceptedRegion& region,
    const std::uint32_t x,
    const std::uint32_t y) {
    if (x >= region.width || y >= region.height) return false;
    return region.rgba[(static_cast<std::size_t>(y) * region.width + x) * 4U] != 0U;
}

}  // namespace

void test_review_preserves_exact_component_ownership_and_acceptance() {
    constexpr std::uint32_t width = 1'000U;
    constexpr std::uint32_t height = 900U;
    std::vector<ClassifiedComponent> components{};
    components.push_back(component(
        width,
        false,
        DefectClassification::dust,
        {{400U, 350U}}));
    components.push_back(component(
        width,
        true,
        DefectClassification::scratch_horizontal,
        {{400U, 350U}, {401U, 350U}}));
    GrainMendReview review{
        width,
        height,
        1'400U,
        1'200U,
        100U,
        50U,
        width,
        height,
        std::move(components)};

    const auto overlap = review.nearest_component(400, 350, 3U);
    const auto scratch_only = review.nearest_component(401, 350, 3U);
    const std::array<std::uint8_t, 2U> include_all{0U, 0U};
    const std::array<std::uint8_t, 2U> exclude_dust{1U, 0U};
    const std::array<std::uint8_t, 2U> exclude_scratch{0U, 1U};
    const std::array<std::uint8_t, 2U> exclude_all{1U, 1U};
    const auto all = review.build_accepted(include_all);
    const auto scratch = review.build_accepted(exclude_dust);
    const auto dust = review.build_accepted(exclude_scratch);
    const auto empty = review.build_accepted(exclude_all);

    expect(
        review.valid() && review.preview_point_count() == 3U &&
            overlap == 0U && scratch_only == 1U,
        "review keeps exact pixels and dust owns a dust-scratch overlap");
    expect(
        all.status == GrainMendAcceptedRegionStatus::ok &&
            all.roi_x == 233U && all.roi_y == 133U &&
            all.width == 536U && all.height == 535U &&
            all.rgba.size() == 1'147'040U &&
            all.included_component_count == 2U && all.marked_pixel_count == 56U &&
            scratch.status == GrainMendAcceptedRegionStatus::ok &&
            scratch.width == 536U && scratch.height == 535U &&
            scratch.marked_pixel_count == 56U &&
            dust.status == GrainMendAcceptedRegionStatus::ok &&
            dust.width == 535U && dust.height == 535U &&
            dust.rgba.size() == 1'144'900U && dust.marked_pixel_count == 25U &&
            empty.status == GrainMendAcceptedRegionStatus::empty && empty.rgba.empty(),
        "acceptance uses dust radius 2, scratch radius 3, and survivor bbox plus 267 pixels");
    expect(
        !marked(all, 263U, 267U) && marked(all, 264U, 267U) &&
            marked(all, 271U, 267U) && !marked(all, 272U, 267U),
        "accepted scratch retains 264 clear repair-context pixels beyond its dilation");
}

void test_review_nearest_hit_matches_macos_ring_order() {
    constexpr std::uint32_t width = 24U;
    std::vector<ClassifiedComponent> components{};
    components.push_back(component(
        width, false, DefectClassification::dust, {{9U, 9U}}));
    components.push_back(component(
        width, false, DefectClassification::pinhole, {{11U, 11U}}));
    GrainMendReview review{
        width, 24U, width, 24U, 0U, 0U, width, 24U, std::move(components)};
    const auto nearest = review.nearest_component(10, 10, 3U);
    expect(
        nearest == 1U,
        "nearest hit returns the last label in the first non-empty macOS square ring");
}

}  // namespace grain_mend_tests
