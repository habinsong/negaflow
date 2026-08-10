#include "negaflow/imaging/defect_component_repair.h"

#include "negaflow/color/srgb_transfer.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace {

using negaflow::core::Rgba32F;
using negaflow::imaging::DefectComponentRepairParameters;
using negaflow::imaging::DefectComponentRepairStatus;
using negaflow::imaging::WorkingImage;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] float to_linear(const float encoded) noexcept {
    return negaflow::color::srgb_encoded_to_linear(encoded);
}

[[nodiscard]] float to_encoded(const float linear) noexcept {
    return negaflow::color::linear_to_srgb_encoded(linear);
}

[[nodiscard]] WorkingImage make_uniform_image(
    const std::uint32_t width,
    const std::uint32_t height,
    const float encoded,
    const float alpha = 1.0F) {
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    const float linear = to_linear(encoded);
    image.pixels.assign(
        static_cast<std::size_t>(width) * height,
        Rgba32F{linear, linear, linear, alpha});
    return image;
}

void set_encoded(
    WorkingImage& image,
    const std::uint32_t x,
    const std::uint32_t y,
    const float red,
    const float green,
    const float blue) noexcept {
    Rgba32F& pixel = image.pixels[
        static_cast<std::size_t>(y) * image.stride_pixels + x];
    pixel.red = to_linear(red);
    pixel.green = to_linear(green);
    pixel.blue = to_linear(blue);
}

[[nodiscard]] float encoded_red(
    const WorkingImage& image,
    const std::uint32_t x,
    const std::uint32_t y) noexcept {
    return to_encoded(image.pixels[
        static_cast<std::size_t>(y) * image.stride_pixels + x].red);
}

[[nodiscard]] bool same_pixels(
    const std::vector<Rgba32F>& left,
    const std::vector<Rgba32F>& right) noexcept {
    return left.size() == right.size() &&
           std::memcmp(
               left.data(),
               right.data(),
               left.size() * sizeof(Rgba32F)) == 0;
}

void test_zero_mask_is_bit_exact() {
    auto image = make_uniform_image(48U, 36U, 0.47F, 0.71F);
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const float offset = static_cast<float>((x * 17U + y * 11U) % 9U) *
                0.003F;
            set_encoded(image, x, y, 0.42F + offset, 0.46F + offset, 0.50F + offset);
        }
    }
    const auto original = image.pixels;
    const std::vector<std::uint8_t> mask(
        static_cast<std::size_t>(image.width) * image.height,
        0U);
    const auto result = negaflow::imaging::repair_defect_components(
        std::move(image),
        mask,
        48U);
    expect(
        result.status == DefectComponentRepairStatus::ok &&
            !result.info.applied && result.info.component_count == 0U &&
            same_pixels(result.image.pixels, original),
        "an empty component mask is bit exact");
}

void test_strength_blends_the_same_repair() {
    constexpr std::uint32_t width = 48U;
    constexpr std::uint32_t height = 40U;
    auto source = make_uniform_image(width, height, 0.42F, 0.73F);
    std::vector<std::uint8_t> mask(
        static_cast<std::size_t>(width) * height,
        0U);
    for (std::uint32_t y = 10U; y < 30U; ++y) {
        set_encoded(source, 24U, y, 0.96F, 0.94F, 0.92F);
        mask[static_cast<std::size_t>(y) * width + 24U] = 255U;
    }
    const std::vector<Rgba32F> original = source.pixels;

    DefectComponentRepairParameters full_parameters{};
    full_parameters.has_preferred_angle = true;
    full_parameters.preferred_angle_degrees = 90.0;
    const auto full = negaflow::imaging::repair_defect_components(
        source,
        mask,
        width,
        full_parameters);

    DefectComponentRepairParameters half_parameters = full_parameters;
    half_parameters.strength = 0.5;
    const auto half = negaflow::imaging::repair_defect_components(
        source,
        mask,
        width,
        half_parameters);

    DefectComponentRepairParameters zero_parameters = full_parameters;
    zero_parameters.strength = 0.0;
    const auto zero = negaflow::imaging::repair_defect_components(
        std::move(source),
        mask,
        width,
        zero_parameters);

    const std::size_t center = 20U * width + 24U;
    expect(
        full.status == DefectComponentRepairStatus::ok && full.info.applied &&
            half.status == DefectComponentRepairStatus::ok && half.info.applied &&
            zero.status == DefectComponentRepairStatus::ok && !zero.info.applied,
        "strength variants complete the same component repair");
    if (full.image.pixels.empty() || half.image.pixels.empty() ||
        zero.image.pixels.empty()) {
        return;
    }
    const Rgba32F expected_half{
        (original[center].red + full.image.pixels[center].red) * 0.5F,
        (original[center].green + full.image.pixels[center].green) * 0.5F,
        (original[center].blue + full.image.pixels[center].blue) * 0.5F,
        original[center].alpha,
    };
    expect(
        std::abs(half.image.pixels[center].red - expected_half.red) < 1.0e-6F &&
            std::abs(half.image.pixels[center].green - expected_half.green) <
                1.0e-6F &&
            std::abs(half.image.pixels[center].blue - expected_half.blue) <
                1.0e-6F &&
            half.image.pixels[center].alpha == original[center].alpha,
        "half strength is the linear midpoint of the same full repair");
    expect(
        same_pixels(zero.image.pixels, original),
        "zero strength is bit exact even with a nonempty mask");
}

void test_thin_scratch_preserves_crossing_structure() {
    constexpr std::uint32_t width = 96U;
    constexpr std::uint32_t height = 72U;
    auto clean = make_uniform_image(width, height, 0.65F, 0.63F);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 47U; x <= 49U; ++x) {
            set_encoded(clean, x, y, 0.21F, 0.21F, 0.21F);
        }
    }
    auto damaged = clean;
    std::vector<std::uint8_t> mask(
        static_cast<std::size_t>(width) * height,
        0U);
    for (std::uint32_t y = 35U; y <= 37U; ++y) {
        for (std::uint32_t x = 24U; x <= 72U; ++x) {
            set_encoded(damaged, x, y, 0.92F, 0.92F, 0.92F);
            mask[static_cast<std::size_t>(y) * width + x] = 255U;
        }
    }
    DefectComponentRepairParameters parameters{};
    parameters.has_preferred_angle = true;
    parameters.preferred_angle_degrees = 0.0;
    const auto result = negaflow::imaging::repair_defect_components(
        std::move(damaged),
        mask,
        width,
        parameters);
    expect(
        result.status == DefectComponentRepairStatus::ok && result.info.applied &&
            result.info.component_count == 1U,
        "a guided thin scratch is repaired as one component");
    if (result.status != DefectComponentRepairStatus::ok ||
        result.image.pixels.empty()) {
        return;
    }
    expect(
        encoded_red(result.image, 48U, 36U) < 0.34F,
        "the vertical structure crossing a horizontal scratch remains dark");
    expect(
        std::abs(encoded_red(result.image, 40U, 36U) - 0.65F) < 0.08F,
        "the scratch-only background returns to its surrounding tone");
    expect(
        result.image.pixels[36U * width + 48U].alpha == 0.63F,
        "component repair preserves source alpha exactly");
}

void test_twenty_six_degree_thin_structure_is_preserved() {
    constexpr std::uint32_t width = 96U;
    constexpr std::uint32_t height = 64U;
    auto image = make_uniform_image(width, height, 0.66F);
    for (std::uint32_t x = 4U; x < 92U; ++x) {
        const std::uint32_t y = x / 2U;
        set_encoded(image, x, y, 0.19F, 0.19F, 0.19F);
    }
    std::vector<std::uint8_t> mask(
        static_cast<std::size_t>(width) * height,
        0U);
    for (std::uint32_t x = 46U; x <= 50U; ++x) {
        const std::uint32_t y = x / 2U;
        set_encoded(image, x, y, 0.91F, 0.91F, 0.91F);
        mask[static_cast<std::size_t>(y) * width + x] = 255U;
    }
    const auto result = negaflow::imaging::repair_defect_components(
        std::move(image),
        mask,
        width);
    expect(
        result.status == DefectComponentRepairStatus::ok &&
            result.info.repaired_pixels == 5U,
        "a 26.6-degree thin component is completely repaired");
    if (result.status == DefectComponentRepairStatus::ok &&
        !result.image.pixels.empty()) {
        expect(
            encoded_red(result.image, 48U, 24U) < 0.34F,
            "the extended thin-direction set reconnects a 2:1 structure");
    }
}

void test_thick_component_uses_onion_peel_fill() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 64U;
    auto image = make_uniform_image(width, height, 0.42F, 0.37F);
    std::vector<std::uint8_t> mask(
        static_cast<std::size_t>(width) * height,
        0U);
    for (std::uint32_t y = 27U; y <= 37U; ++y) {
        for (std::uint32_t x = 27U; x <= 37U; ++x) {
            set_encoded(image, x, y, 0.95F, 0.95F, 0.95F);
            mask[static_cast<std::size_t>(y) * width + x] = 255U;
        }
    }
    const auto result = negaflow::imaging::repair_defect_components(
        std::move(image),
        mask,
        width);
    expect(
        result.status == DefectComponentRepairStatus::ok &&
            result.info.repaired_pixels == 121U,
        "a thick component fills every onion-peel layer");
    if (result.status == DefectComponentRepairStatus::ok &&
        !result.image.pixels.empty()) {
        expect(
            std::abs(encoded_red(result.image, 32U, 32U) - 0.42F) < 2.0e-4F,
            "the center of a thick dust blob is restored from clear layers");
        expect(
            result.image.pixels[32U * width + 32U].alpha == 0.37F,
            "onion-peel repair preserves alpha");
    }
}

void test_texture_transfer_is_deterministic_and_not_smooth() {
    constexpr std::uint32_t width = 96U;
    constexpr std::uint32_t height = 80U;
    auto clean = make_uniform_image(width, height, 0.50F, 0.82F);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const int red_code = static_cast<int>((x * 37U + y * 19U) % 13U) - 6;
            const int green_code = static_cast<int>((x * 17U + y * 41U) % 11U) - 5;
            const int blue_code = static_cast<int>((x * 29U + y * 23U) % 15U) - 7;
            set_encoded(
                clean,
                x,
                y,
                0.50F + static_cast<float>(red_code) * 0.006F,
                0.49F + static_cast<float>(green_code) * 0.006F,
                0.51F + static_cast<float>(blue_code) * 0.005F);
        }
    }
    auto first_input = clean;
    auto second_input = clean;
    std::vector<std::uint8_t> mask(
        static_cast<std::size_t>(width) * height,
        0U);
    for (std::uint32_t y = 35U; y <= 45U; ++y) {
        for (std::uint32_t x = 42U; x <= 54U; ++x) {
            set_encoded(first_input, x, y, 0.88F, 0.88F, 0.88F);
            set_encoded(second_input, x, y, 0.88F, 0.88F, 0.88F);
            mask[static_cast<std::size_t>(y) * width + x] = 255U;
        }
    }
    const auto first = negaflow::imaging::repair_defect_components(
        std::move(first_input),
        mask,
        width);
    const auto second = negaflow::imaging::repair_defect_components(
        std::move(second_input),
        mask,
        width);
    expect(
        first.status == DefectComponentRepairStatus::ok &&
            second.status == DefectComponentRepairStatus::ok &&
            same_pixels(first.image.pixels, second.image.pixels),
        "texture transfer is deterministic for the same source and component order");
    if (first.status != DefectComponentRepairStatus::ok ||
        first.image.pixels.empty()) {
        return;
    }
    double mean = 0.0;
    double input_error = 0.0;
    double output_error = 0.0;
    std::size_t count = 0U;
    for (std::uint32_t y = 35U; y <= 45U; ++y) {
        for (std::uint32_t x = 42U; x <= 54U; ++x) {
            const float output = encoded_red(first.image, x, y);
            const float reference = encoded_red(clean, x, y);
            mean += output;
            input_error += std::abs(0.88 - static_cast<double>(reference));
            output_error += std::abs(
                static_cast<double>(output) - static_cast<double>(reference));
            ++count;
        }
    }
    mean /= static_cast<double>(count);
    double variance = 0.0;
    for (std::uint32_t y = 35U; y <= 45U; ++y) {
        for (std::uint32_t x = 42U; x <= 54U; ++x) {
            const double delta = static_cast<double>(encoded_red(first.image, x, y)) - mean;
            variance += delta * delta;
        }
    }
    variance /= static_cast<double>(count);
    expect(
        std::sqrt(variance) > 0.003,
        "the repaired component retains visible high-frequency texture");
    expect(
        output_error < input_error * 0.30,
        "texture-aware repair is materially closer to the clean field than the defect");
}

void test_guided_broad_mask_keeps_only_real_damage() {
    constexpr std::uint32_t width = 96U;
    constexpr std::uint32_t height = 72U;
    auto image = make_uniform_image(width, height, 0.50F);
    std::vector<std::uint8_t> mask(
        static_cast<std::size_t>(width) * height,
        0U);
    for (std::uint32_t y = 18U; y <= 53U; ++y) {
        for (std::uint32_t x = 16U; x <= 79U; ++x) {
            mask[static_cast<std::size_t>(y) * width + x] = 255U;
        }
    }
    for (std::uint32_t y = 34U; y <= 37U; ++y) {
        for (std::uint32_t x = 45U; x <= 52U; ++x) {
            set_encoded(image, x, y, 0.86F, 0.86F, 0.86F);
        }
    }
    const auto original = image.pixels;
    DefectComponentRepairParameters parameters{};
    parameters.has_preferred_angle = true;
    parameters.preferred_angle_degrees = 0.0;
    const auto result = negaflow::imaging::repair_defect_components(
        std::move(image),
        mask,
        width,
        parameters);
    expect(
        result.status == DefectComponentRepairStatus::ok &&
            result.info.input_mask_pixels == 2304U &&
            result.info.retained_mask_pixels == 32U,
        "a wide guided mask is refined to its high-contrast defect pixels");
    if (result.status != DefectComponentRepairStatus::ok ||
        result.image.pixels.empty()) {
        return;
    }
    expect(
        result.blend_mask[20U * width + 20U] == 0U &&
            result.blend_mask[35U * width + 48U] == 255U,
        "the refined blend mask excludes painted clear texture and retains damage");
    expect(
        std::memcmp(
            &result.image.pixels[20U * width + 20U],
            &original[20U * width + 20U],
            sizeof(Rgba32F)) == 0,
        "normal texture inside a broad brush remains bit exact");
    expect(
        std::abs(encoded_red(result.image, 48U, 35U) - 0.50F) < 0.03F,
        "the retained bright defect is repaired to the surrounding tone");
}

void test_invalid_inputs_fail_closed() {
    auto invalid_angle_image = make_uniform_image(32U, 24U, 0.5F);
    std::vector<std::uint8_t> mask(32U * 24U, 0U);
    DefectComponentRepairParameters invalid_angle{};
    invalid_angle.has_preferred_angle = true;
    invalid_angle.preferred_angle_degrees =
        std::numeric_limits<double>::quiet_NaN();
    const auto angle_result = negaflow::imaging::repair_defect_components(
        std::move(invalid_angle_image),
        mask,
        32U,
        invalid_angle);
    expect(
        angle_result.status == DefectComponentRepairStatus::invalid_argument &&
            angle_result.image.pixels.empty(),
        "a non-finite preferred angle fails closed");

    auto short_mask_image = make_uniform_image(32U, 24U, 0.5F);
    const std::vector<std::uint8_t> short_mask(31U, 255U);
    const auto mask_result = negaflow::imaging::repair_defect_components(
        std::move(short_mask_image),
        short_mask,
        32U);
    expect(
        mask_result.status == DefectComponentRepairStatus::invalid_argument &&
            mask_result.image.pixels.empty(),
        "an undersized component mask fails closed");

    auto invalid_pixel_image = make_uniform_image(32U, 24U, 0.5F);
    invalid_pixel_image.pixels[0].red = std::numeric_limits<float>::infinity();
    const auto pixel_result = negaflow::imaging::repair_defect_components(
        std::move(invalid_pixel_image),
        mask,
        32U);
    expect(
        pixel_result.status == DefectComponentRepairStatus::kernel_failed &&
            pixel_result.info.kernel_status ==
                negaflow::core::KernelStatus::non_finite_input &&
            pixel_result.image.pixels.empty(),
        "non-finite ROI pixels fail closed without a partial repair");
}

}  // namespace

int main() {
    test_zero_mask_is_bit_exact();
    test_strength_blends_the_same_repair();
    test_thin_scratch_preserves_crossing_structure();
    test_twenty_six_degree_thin_structure_is_preserved();
    test_thick_component_uses_onion_peel_fill();
    test_texture_transfer_is_deterministic_and_not_smooth();
    test_guided_broad_mask_keeps_only_real_damage();
    test_invalid_inputs_fail_closed();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"defect_component_repair\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
