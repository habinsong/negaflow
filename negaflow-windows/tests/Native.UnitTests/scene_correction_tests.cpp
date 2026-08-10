#include "negaflow/imaging/scene_correction.h"

#include <cmath>
#include <cstddef>
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

void test_disabled_is_identity() {
    constexpr std::uint32_t width = 16U;
    constexpr std::uint32_t height = 16U;
    std::vector<negaflow::core::Rgba32F> pixels(
        width * height, {0.2F, 0.3F, 0.4F, 1.0F});
    const auto before = pixels;
    negaflow::imaging::SceneCorrectionInfo info{};
    expect(
        negaflow::imaging::apply_scene_correction(view(pixels, width, height), {}, info) ==
            negaflow::core::KernelStatus::ok,
        "disabled scene correction succeeds");
    for (std::size_t index = 0U; index < pixels.size(); ++index) {
        expect(
            pixels[index].red == before[index].red &&
                pixels[index].green == before[index].green &&
                pixels[index].blue == before[index].blue &&
                pixels[index].alpha == before[index].alpha,
            "disabled scene correction is exact identity");
    }
}

void test_negative_auto_correction_changes_cast_range() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 32U;
    std::vector<negaflow::core::Rgba32F> pixels(width * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float ramp = static_cast<float>(x) / static_cast<float>(width - 1U);
            pixels[static_cast<std::size_t>(y) * width + x] = {
                0.08F + (ramp * 0.52F),
                0.12F + (ramp * 0.58F),
                0.16F + (ramp * 0.62F),
                1.0F,
            };
        }
    }
    negaflow::imaging::SceneCorrectionInfo info{};
    const negaflow::imaging::SceneCorrectionParameters parameters{
        true, false, true};
    expect(
        negaflow::imaging::apply_scene_correction(
            view(pixels, width, height), parameters, info) ==
            negaflow::core::KernelStatus::ok,
        "negative auto correction succeeds");
    expect(info.auto_levels_applied, "Auto Levels applies to a narrow-range scan");
    expect(pixels.front().alpha == 1.0F, "scene correction preserves alpha");
    expect(pixels.back().red > 0.8F, "Auto Levels expands the visible range");

    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float ramp = static_cast<float>(x) / static_cast<float>(width - 1U);
            pixels[static_cast<std::size_t>(y) * width + x] = {
                0.12F + (ramp * 0.30F),
                0.28F + (ramp * 0.30F),
                0.44F + (ramp * 0.30F),
                1.0F,
            };
        }
    }
    const negaflow::imaging::SceneCorrectionParameters neutral_only{
        false, true, true};
    expect(
        negaflow::imaging::apply_scene_correction(
            view(pixels, width, height), neutral_only, info) ==
            negaflow::core::KernelStatus::ok,
        "Neutral Balance succeeds");
    expect(info.neutral_balance_applied, "Neutral Balance applies to a cast scan");
}

}  // namespace

int main() {
    try {
        test_disabled_is_identity();
        test_negative_auto_correction_changes_cast_range();
        std::cout << "Scene correction tests passed\n";
        return 0;
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        return 1;
    }
}
