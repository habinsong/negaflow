#include "negaflow/imaging/defect_clone_stamp.h"
#include "defect_clone_stamp_mask.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <span>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        ++failures;
        std::cerr << "FAIL: " << message << '\n';
    }
}

[[nodiscard]] negaflow::imaging::WorkingImage make_gradient(
    const std::uint32_t width = 32U,
    const std::uint32_t height = 24U) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            image.pixels[static_cast<std::size_t>(y) * width + x] = {
                static_cast<float>(x + 1U) / static_cast<float>(width + 1U),
                static_cast<float>(y + 1U) / static_cast<float>(height + 1U),
                static_cast<float>(x + y + 1U) /
                    static_cast<float>(width + height + 1U),
                1.0F,
            };
        }
    }
    return image;
}

[[nodiscard]] float quantize16(const float value) noexcept {
    return static_cast<float>(std::floor(
        static_cast<double>(value) * 65'535.0 + 0.5)) / 65'535.0F;
}

[[nodiscard]] bool close(
    const float actual,
    const float expected,
    const float tolerance = 1.0e-6F) noexcept {
    return std::abs(actual - expected) <= tolerance;
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

void test_single_stamp_copies_the_integer_offset_source() {
    auto source = make_gradient();
    const auto original = source.pixels;
    const std::vector<negaflow::imaging::DefectClonePoint> points{{
        8.0 / 32.0,
        12.0 / 24.0,
    }};
    const negaflow::imaging::DefectCloneStroke stroke{
        points,
        8.0 / 32.0,
        0.0,
        6.0,
        1.0,
    };
    const auto result = negaflow::imaging::apply_defect_clone_stamps(
        std::move(source),
        {std::span<const negaflow::imaging::DefectCloneStroke>(&stroke, 1U),
         1.0});

    const std::size_t destination = 11U * 32U + 7U;
    const std::size_t expected_source = 11U * 32U + 15U;
    expect(
        result.status == negaflow::imaging::DefectCloneStatus::ok &&
            result.info.applied && result.info.applied_strokes == 1U,
        "one valid clone stroke is applied");
    expect(
        close(
            result.image.pixels[destination].red,
            quantize16(original[expected_source].red)) &&
            close(
                result.image.pixels[destination].green,
                quantize16(original[expected_source].green)) &&
            close(
                result.image.pixels[destination].blue,
                quantize16(original[expected_source].blue)),
        "a hard stamp copies the rounded source offset through linear RGBA16");
    expect(
        result.image.pixels.front().red == original.front().red &&
            result.image.pixels.front().green == original.front().green &&
            result.image.pixels.front().blue == original.front().blue,
        "pixels outside the patch remain byte exact");
}

void test_layer_strength_mixes_the_full_strength_patch() {
    auto source = make_gradient();
    const auto original = source.pixels;
    const std::vector<negaflow::imaging::DefectClonePoint> points{{
        8.0 / 32.0,
        12.0 / 24.0,
    }};
    const negaflow::imaging::DefectCloneStroke stroke{
        points,
        8.0 / 32.0,
        0.0,
        6.0,
        1.0,
    };
    const auto result = negaflow::imaging::apply_defect_clone_stamps(
        std::move(source),
        {std::span<const negaflow::imaging::DefectCloneStroke>(&stroke, 1U),
         0.5});

    const std::size_t destination = 11U * 32U + 7U;
    const std::size_t expected_source = 11U * 32U + 15U;
    const float expected = original[destination].red * 0.5F +
        quantize16(original[expected_source].red) * 0.5F;
    expect(
        result.status == negaflow::imaging::DefectCloneStatus::ok &&
            close(result.image.pixels[destination].red, expected),
        "layer strength linearly mixes the cached full-strength patch");
}

void test_later_stroke_reads_the_prior_full_strength_patch() {
    auto source = make_gradient(24U, 16U);
    const auto original = source.pixels;
    const std::vector<negaflow::imaging::DefectClonePoint> first_points{{
        8.0 / 24.0,
        8.0 / 16.0,
    }};
    const std::vector<negaflow::imaging::DefectClonePoint> second_points{{
        4.0 / 24.0,
        8.0 / 16.0,
    }};
    const std::vector<negaflow::imaging::DefectCloneStroke> strokes{
        {first_points, 8.0 / 24.0, 0.0, 4.0, 1.0},
        {second_points, 4.0 / 24.0, 0.0, 4.0, 1.0},
    };
    const auto result = negaflow::imaging::apply_defect_clone_stamps(
        std::move(source),
        {strokes, 0.5});

    const std::size_t destination = 7U * 24U + 3U;
    const std::size_t original_source = 7U * 24U + 15U;
    const float twice_quantized = quantize16(quantize16(
        original[original_source].red));
    const float expected = original[destination].red * 0.5F +
        twice_quantized * 0.5F;
    expect(
        result.status == negaflow::imaging::DefectCloneStatus::ok &&
            result.info.applied_strokes == 2U &&
            close(result.image.pixels[destination].red, expected),
        "a later stroke samples the prior full-strength patch, not its partial display mix");
}

void test_zero_offset_is_a_no_op_and_invalid_input_fails_closed() {
    auto source = make_gradient();
    const auto original = source.pixels;
    const std::vector<negaflow::imaging::DefectClonePoint> points{{0.5, 0.5}};
    const negaflow::imaging::DefectCloneStroke zero_offset{
        points,
        0.0,
        0.0,
        8.0,
        0.5,
    };
    const auto identity = negaflow::imaging::apply_defect_clone_stamps(
        source,
        {std::span<const negaflow::imaging::DefectCloneStroke>(
             &zero_offset, 1U),
         1.0});
    expect(
        identity.status == negaflow::imaging::DefectCloneStatus::ok &&
            !identity.info.applied && same_pixels(identity.image.pixels, original),
        "a rounded zero source offset is an exact no-op");

    const std::vector<negaflow::imaging::DefectClonePoint> invalid_points{{
        std::numeric_limits<double>::quiet_NaN(),
        0.5,
    }};
    const negaflow::imaging::DefectCloneStroke invalid{
        invalid_points,
        0.1,
        0.0,
        8.0,
        0.5,
    };
    const auto failed = negaflow::imaging::apply_defect_clone_stamps(
        std::move(source),
        {std::span<const negaflow::imaging::DefectCloneStroke>(&invalid, 1U),
         1.0});
    expect(
        failed.status ==
                negaflow::imaging::DefectCloneStatus::invalid_argument &&
            failed.image.pixels.empty(),
        "non-finite clone geometry fails closed");
}

void test_cancellation_stops_before_a_stamp_and_discards_pixels() {
    std::uint32_t cancel_word = 1U;
    const negaflow::core::CancelFlag cancel{&cancel_word};
    const std::vector<negaflow::imaging::clone_stamp_detail::PixelPoint>
        pixel_points{{4.0, 4.0}, {28.0, 4.0}};
    std::vector<float> mask(32U * 8U, 0.0F);
    const bool rasterized =
        negaflow::imaging::clone_stamp_detail::rasterize_stroke(
            pixel_points,
            2.0,
            2.0,
            1.0,
            0U,
            0U,
            32U,
            8U,
            mask,
            cancel);
    expect(
        !rasterized &&
            std::all_of(mask.begin(), mask.end(), [](const float value) {
                return value == 0.0F;
            }),
        "a latched cancellation stops before the first clone stamp");

    auto source = make_gradient();
    const std::vector<negaflow::imaging::DefectClonePoint> points{
        {0.25, 0.5},
        {0.75, 0.5},
    };
    const negaflow::imaging::DefectCloneStroke stroke{
        points,
        0.1,
        0.0,
        8.0,
        0.5,
    };
    const auto result = negaflow::imaging::apply_defect_clone_stamps(
        std::move(source),
        {std::span<const negaflow::imaging::DefectCloneStroke>(&stroke, 1U),
         1.0},
        cancel);
    expect(
        result.status == negaflow::imaging::DefectCloneStatus::cancelled &&
            result.image.pixels.empty(),
        "a cancelled clone recipe cannot publish partial pixels");
}

}  // namespace

int main() {
    test_single_stamp_copies_the_integer_offset_source();
    test_layer_strength_mixes_the_full_strength_patch();
    test_later_stroke_reads_the_prior_full_strength_patch();
    test_zero_offset_is_a_no_op_and_invalid_input_fails_closed();
    test_cancellation_stops_before_a_stamp_and_discards_pixels();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"defect_clone_stamp\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
