#include "negaflow/imaging/bw_toning.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <iostream>
#include <limits>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] negaflow::imaging::WorkingImage ramp() {
    negaflow::imaging::WorkingImage image{};
    image.width = 96U;
    image.height = 8U;
    image.stride_pixels = image.width;
    image.pixels.resize(static_cast<std::size_t>(image.width) * image.height);
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const float value = 0.08F + 0.82F * static_cast<float>(x) /
                static_cast<float>(image.width - 1U);
            image.pixels[static_cast<std::size_t>(y) * image.width + x] = {
                value + 0.06F, value, value - 0.04F,
                0.3F + 0.5F * static_cast<float>(y) /
                    static_cast<float>(image.height - 1U),
            };
        }
    }
    return image;
}

[[nodiscard]] bool same_pixels(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept {
    return left.size() == right.size() &&
           std::memcmp(left.data(), right.data(),
                       left.size() * sizeof(left.front())) == 0;
}

void test_color_is_exact_noop_and_bw_is_neutral() {
    const auto source = ramp();
    const auto color = negaflow::imaging::apply_bw_toning(
        source, negaflow::imaging::NegativeFilmType::color, {});
    expect(
        color.status == negaflow::imaging::BwToningStatus::ok &&
            !color.info.neutralized && same_pixels(color.image.pixels, source.pixels),
        "color film remains byte exact");

    const auto bw = negaflow::imaging::apply_bw_toning(
        source, negaflow::imaging::NegativeFilmType::black_and_white, {});
    bool neutral = bw.info.neutralized && !bw.info.toned;
    for (std::size_t index = 0U; index < bw.image.pixels.size(); ++index) {
        const auto pixel = bw.image.pixels[index];
        neutral = neutral && pixel.red == pixel.green && pixel.green == pixel.blue &&
                  pixel.alpha == source.pixels[index].alpha;
    }
    expect(neutral, "B&W film is neutralized and alpha is preserved");
}

void test_toning_has_fixed_character_and_luma_order() {
    negaflow::imaging::BwToningParameters selenium{};
    selenium.mode = negaflow::imaging::BwToningMode::selenium;
    selenium.shadow_hue = 285.0;
    selenium.highlight_hue = 34.0;
    selenium.strength = 0.85;
    const auto result = negaflow::imaging::apply_bw_toning(
        ramp(), negaflow::imaging::NegativeFilmType::black_and_white, selenium);
    const auto low = result.image.pixels[12U];
    const auto middle = result.image.pixels[48U];
    const auto high = result.image.pixels[84U];
    const auto luma = [](const negaflow::core::Rgba32F pixel) {
        return pixel.red * 0.2126F + pixel.green * 0.7152F +
               pixel.blue * 0.0722F;
    };
    const auto spread = [](const negaflow::core::Rgba32F pixel) {
        return std::max({pixel.red, pixel.green, pixel.blue}) -
               std::min({pixel.red, pixel.green, pixel.blue});
    };
    expect(
        result.status == negaflow::imaging::BwToningStatus::ok &&
            result.info.toned && spread(low) > 0.01F &&
            luma(low) < luma(middle) && luma(middle) < luma(high),
        "selenium produces chroma while preserving ramp order");
}

void test_nonfinite_parameter_fails_closed() {
    negaflow::imaging::BwToningParameters invalid{};
    invalid.strength = std::numeric_limits<double>::quiet_NaN();
    const auto result = negaflow::imaging::apply_bw_toning(
        ramp(), negaflow::imaging::NegativeFilmType::black_and_white, invalid);
    expect(
        result.status == negaflow::imaging::BwToningStatus::invalid_parameter &&
            result.image.pixels.empty(),
        "non-finite B&W recipe fails closed");
}

}  // namespace

int main() {
    test_color_is_exact_noop_and_bw_is_neutral();
    test_toning_has_fixed_character_and_luma_order();
    test_nonfinite_parameter_fails_closed();
    return failures == 0 ? 0 : 1;
}
