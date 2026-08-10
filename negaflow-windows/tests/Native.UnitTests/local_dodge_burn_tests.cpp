#include "negaflow/imaging/local_dodge_burn.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] negaflow::imaging::WorkingImage make_image(
    const std::uint32_t width,
    const std::uint32_t height,
    const float value = 0.42F) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float gradient = value +
                0.04F * static_cast<float>(x) /
                    static_cast<float>(width - 1U);
            image.pixels[static_cast<std::size_t>(y) * width + x] = {
                gradient * 1.02F,
                gradient,
                gradient * 0.97F,
                0.2F + 0.7F * static_cast<float>(y) /
                    static_cast<float>(height - 1U),
            };
        }
    }
    return image;
}

[[nodiscard]] float luma(const negaflow::core::Rgba32F value) noexcept {
    return value.red * 0.2126F + value.green * 0.7152F +
           value.blue * 0.0722F;
}

[[nodiscard]] float mean_luma(
    const negaflow::imaging::WorkingImage& image,
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    float sum = 0.0F;
    std::size_t count = 0U;
    for (std::uint32_t row = y; row < y + height; ++row) {
        for (std::uint32_t column = x; column < x + width; ++column) {
            sum += luma(image.pixels[
                static_cast<std::size_t>(row) * image.stride_pixels + column]);
            ++count;
        }
    }
    return sum / static_cast<float>(count);
}

[[nodiscard]] bool same_pixels(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept {
    return left.size() == right.size() &&
           std::memcmp(
               left.data(),
               right.data(),
               left.size() * sizeof(negaflow::core::Rgba32F)) == 0;
}

[[nodiscard]] negaflow::imaging::LocalDodgeBurnAdjustment adjustment(
    const negaflow::imaging::LocalDodgeBurnMode mode,
    const float amount,
    negaflow::imaging::LocalDodgeBurnMask mask) {
    return {mode, amount, true, std::move(mask)};
}

void test_identity_visibility_and_invalid_input() {
    auto source = make_image(64U, 48U);
    const auto original = source.pixels;
    const auto empty = negaflow::imaging::apply_local_dodge_burn(source, {});
    expect(
        empty.status == negaflow::imaging::LocalDodgeBurnStatus::ok &&
            !empty.info.applied && same_pixels(empty.image.pixels, original),
        "an empty local adjustment list is byte exact");

    negaflow::imaging::LocalDodgeBurnMask hidden_mask{};
    hidden_mask.kind = negaflow::imaging::LocalDodgeBurnMaskKind::radial;
    negaflow::imaging::LocalDodgeBurnAdjustment hidden = adjustment(
        negaflow::imaging::LocalDodgeBurnMode::dodge,
        1.0F,
        hidden_mask);
    hidden.enabled = false;
    const auto hidden_result = negaflow::imaging::apply_local_dodge_burn(
        source,
        {{hidden}});
    expect(
        !hidden_result.info.applied &&
            same_pixels(hidden_result.image.pixels, original),
        "a disabled adjustment is byte exact");

    hidden.amount = std::numeric_limits<float>::quiet_NaN();
    const auto invalid = negaflow::imaging::apply_local_dodge_burn(
        std::move(source),
        {{hidden}});
    expect(
        invalid.status ==
                negaflow::imaging::LocalDodgeBurnStatus::invalid_parameter &&
            invalid.image.pixels.empty(),
        "a non-finite local control fails closed");
}

void test_radial_dodge_is_local_and_preserves_alpha() {
    auto source = make_image(96U, 72U, 0.34F);
    const auto baseline = source;
    negaflow::imaging::LocalDodgeBurnMask mask{};
    mask.kind = negaflow::imaging::LocalDodgeBurnMaskKind::radial;
    mask.center = {0.5F, 0.5F};
    mask.radius = 0.24F;
    mask.feather = 0.45F;
    const auto result = negaflow::imaging::apply_local_dodge_burn(
        std::move(source),
        {{adjustment(
            negaflow::imaging::LocalDodgeBurnMode::dodge,
            0.7F,
            std::move(mask))}});
    expect(
        result.status == negaflow::imaging::LocalDodgeBurnStatus::ok &&
            result.info.applied && result.info.adjustments_applied == 1U,
        "an enabled radial dodge is applied once");
    expect(
        mean_luma(result.image, 40U, 28U, 16U, 16U) >
            mean_luma(baseline, 40U, 28U, 16U, 16U) + 0.08F,
        "a radial dodge lifts its center");
    expect(
        std::abs(
            mean_luma(result.image, 2U, 2U, 14U, 14U) -
            mean_luma(baseline, 2U, 2U, 14U, 14U)) < 0.018F,
        "a radial dodge leaves distant corners unchanged");

    bool alpha_preserved = true;
    for (std::size_t index = 0U; index < baseline.pixels.size(); ++index) {
        alpha_preserved = alpha_preserved &&
            result.image.pixels[index].alpha == baseline.pixels[index].alpha;
    }
    expect(alpha_preserved, "local exposure preserves alpha exactly");
}

void expect_local_delta(
    negaflow::imaging::LocalDodgeBurnMask mask,
    const negaflow::imaging::LocalDodgeBurnMode mode,
    const float amount,
    const std::uint32_t changed_x,
    const std::uint32_t changed_y,
    const std::uint32_t guarded_x,
    const std::uint32_t guarded_y,
    const float sign,
    const char* const message) {
    auto source = make_image(128U, 96U);
    const auto baseline = source;
    const auto result = negaflow::imaging::apply_local_dodge_burn(
        std::move(source),
        {{adjustment(mode, amount, std::move(mask))}});
    const float changed =
        mean_luma(result.image, changed_x, changed_y, 16U, 16U) -
        mean_luma(baseline, changed_x, changed_y, 16U, 16U);
    const float guarded =
        mean_luma(result.image, guarded_x, guarded_y, 16U, 16U) -
        mean_luma(baseline, guarded_x, guarded_y, 16U, 16U);
    expect(
        result.status == negaflow::imaging::LocalDodgeBurnStatus::ok &&
            changed * sign > 0.06F && std::abs(guarded) < 0.015F,
        message);
}

void test_brush_linear_and_polygon_masks_stay_local() {
    negaflow::imaging::LocalDodgeBurnMask brush{};
    brush.kind = negaflow::imaging::LocalDodgeBurnMaskKind::brush;
    brush.strokes = {{{{0.18F, 0.52F}, {0.36F, 0.52F}}, 0.08F, 0.025F}};
    expect_local_delta(
        std::move(brush),
        negaflow::imaging::LocalDodgeBurnMode::dodge,
        0.65F,
        24U,
        40U,
        98U,
        40U,
        1.0F,
        "the feathered brush mask only lifts its stroke region");

    negaflow::imaging::LocalDodgeBurnMask linear{};
    linear.kind = negaflow::imaging::LocalDodgeBurnMaskKind::linear;
    linear.start = {0.5F, 0.05F};
    linear.end = {0.5F, 0.48F};
    linear.feather = 1.0F;
    expect_local_delta(
        std::move(linear),
        negaflow::imaging::LocalDodgeBurnMode::burn,
        0.55F,
        54U,
        6U,
        54U,
        74U,
        -1.0F,
        "the linear burn follows the normalized gradient direction");

    negaflow::imaging::LocalDodgeBurnMask polygon{};
    polygon.kind = negaflow::imaging::LocalDodgeBurnMaskKind::polygon;
    polygon.feather = 0.03F;
    polygon.points = {
        {0.66F, 0.30F},
        {0.92F, 0.32F},
        {0.82F, 0.72F},
        {0.60F, 0.68F},
    };
    expect_local_delta(
        std::move(polygon),
        negaflow::imaging::LocalDodgeBurnMode::burn,
        0.70F,
        88U,
        48U,
        12U,
        48U,
        -1.0F,
        "the feathered polygon burn stays inside its local region");
}

}  // namespace

int main() {
    test_identity_visibility_and_invalid_input();
    test_radial_dodge_is_local_and_preserves_alpha();
    test_brush_linear_and_polygon_masks_stay_local();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"local_dodge_burn\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
