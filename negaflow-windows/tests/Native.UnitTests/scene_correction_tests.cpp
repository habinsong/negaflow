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

void test_changed_gamma_and_base_inputs_do_not_reuse_previous_correction() {
    constexpr std::uint32_t width = 64U, height = 32U;
    negaflow::imaging::SceneCorrectionInfo reused_info{};
    for (const double gamma : {1.8, 2.4}) {
        for (const double scale : {0.75, 1.25}) {
            for (const bool levels : {false, true}) {
                for (const bool color : {false, true}) {
                    std::vector<negaflow::core::Rgba32F> first(width * height);
                    for (std::size_t i = 0; i < first.size(); ++i) {
                        const double t = static_cast<double>(i % width) / (width - 1U);
                        first[i] = {static_cast<float>(std::pow(0.12 + 0.5 * t, gamma) * scale),
                            static_cast<float>(std::pow(0.2 + 0.5 * t, gamma) * scale),
                            static_cast<float>(std::pow(0.28 + 0.5 * t, gamma) * scale), 1.0F};
                    }
                    auto fresh = first;
                    negaflow::imaging::SceneCorrectionInfo fresh_info{};
                    const negaflow::imaging::SceneCorrectionParameters parameters{levels, color, true};
                    expect(negaflow::imaging::apply_scene_correction(view(first, width, height), parameters, reused_info)
                        == negaflow::core::KernelStatus::ok, "changed input correction succeeds");
                    expect(negaflow::imaging::apply_scene_correction(view(fresh, width, height), parameters, fresh_info)
                        == negaflow::core::KernelStatus::ok, "fresh input correction succeeds");
                    expect(reused_info.auto_levels_applied == fresh_info.auto_levels_applied &&
                        reused_info.neutral_balance_applied == fresh_info.neutral_balance_applied,
                        "correction status must not leak across changed inputs");
                    for (std::size_t i = 0; i < first.size(); ++i) {
                        expect(first[i].red == fresh[i].red && first[i].green == fresh[i].green &&
                            first[i].blue == fresh[i].blue && first[i].alpha == 1.0F,
                            "changed gamma/base input must match fresh scene correction pixels");
                    }
                }
            }
        }
    }
}

}  // namespace

int main() {
    try {
        test_disabled_is_identity();
        test_negative_auto_correction_changes_cast_range();
        test_changed_gamma_and_base_inputs_do_not_reuse_previous_correction();
        std::cout << "Scene correction tests passed\n";
        return 0;
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        return 1;
    }
}
