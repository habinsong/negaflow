#include "negaflow/imaging/rescue_grade.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {

void expect(const bool condition, const char* const message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

negaflow::core::ImageView view(
    std::vector<negaflow::core::Rgba32F>& pixels,
    const std::uint32_t width,
    const std::uint32_t height) {
    return {pixels.data(), pixels.size(), width, height, width};
}

double mean_channel_spread(
    const std::vector<negaflow::core::Rgba32F>& pixels) {
    double total = 0.0;
    for (const auto& pixel : pixels) {
        total += std::max({pixel.red, pixel.green, pixel.blue}) -
                 std::min({pixel.red, pixel.green, pixel.blue});
    }
    return total / pixels.size();
}

void test_healthy_neutral_is_identity() {
    constexpr std::uint32_t width = 96U;
    constexpr std::uint32_t height = 64U;
    std::vector<negaflow::core::Rgba32F> pixels(width * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float value = 0.03F + (0.84F * static_cast<float>(x) / (width - 1U));
            pixels[static_cast<std::size_t>(y) * width + x] =
                {value, value, value, 0.75F};
        }
    }
    const auto before = pixels;
    negaflow::imaging::RescueGradeInfo info{};
    expect(
        negaflow::imaging::apply_rescue_grade(
            view(pixels, width, height), true, info) ==
            negaflow::core::KernelStatus::ok,
        "healthy neutral RescueGrade succeeds");
    expect(!info.applied, "healthy neutral evidence keeps RescueGrade inactive");
    for (std::size_t index = 0U; index < pixels.size(); ++index) {
        expect(
            pixels[index].red == before[index].red &&
                pixels[index].green == before[index].green &&
                pixels[index].blue == before[index].blue &&
                pixels[index].alpha == before[index].alpha,
            "inactive RescueGrade is exact identity");
    }
}

void test_coherent_cast_is_reduced() {
    constexpr std::uint32_t width = 96U;
    constexpr std::uint32_t height = 64U;
    std::vector<negaflow::core::Rgba32F> pixels(width * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float value = 0.03F + (0.80F * static_cast<float>(x) / (width - 1U));
            pixels[static_cast<std::size_t>(y) * width + x] = {
                value * 1.035F,
                value,
                value * 0.965F,
                0.65F,
            };
        }
    }
    const double before = mean_channel_spread(pixels);
    negaflow::imaging::RescueGradeInfo info{};
    expect(
        negaflow::imaging::apply_rescue_grade(
            view(pixels, width, height), true, info) ==
            negaflow::core::KernelStatus::ok,
        "cast RescueGrade succeeds");
    expect(info.applied, "coherent cast passes RescueGrade evidence gate");
    expect(info.eligible_band_count >= 3U, "RescueGrade uses multiple luma bands");
    expect(info.covered_tile_count >= 6U, "RescueGrade uses distributed tiles");
    expect(mean_channel_spread(pixels) < before, "RescueGrade reduces coherent cast");
    expect(pixels.front().alpha == 0.65F, "RescueGrade preserves alpha");
}

}  // namespace

int main() {
    try {
        test_healthy_neutral_is_identity();
        test_coherent_cast_is_reduced();
        std::cout << "RescueGrade tests passed\n";
        return 0;
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        return 1;
    }
}
