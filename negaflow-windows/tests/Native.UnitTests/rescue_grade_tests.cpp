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

/// 오래된 필름이 실제로 내는 <b>센</b> 캐스트입니다.
///
/// 위 시험의 캐스트는 ±3.5% 로 약합니다. 유통기한이 한참 지난 필름은 베이스 포그가 층마다
/// 다르게 쌓여 훨씬 크게 쏠리고(노랗게 보입니다), 그때 EXPIRED 가 아무 일도 하지 않는다는
/// 보고가 있었습니다. 쏠림의 크기만 다를 뿐 성질은 같습니다 — 모든 밝기대가 같은 방향으로,
/// 낮은 흩어짐으로 움직입니다. 그러니 여기서도 걸려야 합니다.
void test_strong_cast_is_reduced() {
    constexpr std::uint32_t width = 96U;
    constexpr std::uint32_t height = 64U;
    std::vector<negaflow::core::Rgba32F> pixels(width * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float value = 0.03F + (0.80F * static_cast<float>(x) / (width - 1U));
            pixels[static_cast<std::size_t>(y) * width + x] = {
                value * 1.16F,
                value * 1.05F,
                value * 0.62F,
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
        "strong cast RescueGrade succeeds");
    expect(info.applied, "strong cast passes RescueGrade evidence gate");
    // "줄기는 했다" 로는 부족합니다. 눈에 띄게 펴져야 고쳤다고 할 수 있습니다.
    const double after = mean_channel_spread(pixels);
    std::cout << "  strong cast spread " << before << " -> " << after
              << " (" << (after / before * 100.0) << "%)\n";
    expect(after < before * 0.5, "RescueGrade removes most of a strong cast");
}

/// 진짜 색이 있는 사진은 건드리지 않아야 합니다.
///
/// 후보 선별에서 원점 거리 상한을 걷어냈으므로, 그 보호를 남은 검사들이 실제로 대신하는지
/// 여기서 증명합니다. 캐스트는 <b>모든 밝기대가 같은 방향으로 조금씩</b> 쏠린 것이고, 색이
/// 있는 장면은 <b>자리마다 제각각</b> 입니다 — 흩어짐(MAD)과 홀드아웃 일치가 그 둘을
/// 가릅니다. 노을 한 장이 통째로 회색이 되면 그것은 복구가 아니라 파괴입니다.
void test_saturated_scene_is_untouched() {
    constexpr std::uint32_t width = 96U;
    constexpr std::uint32_t height = 64U;
    std::vector<negaflow::core::Rgba32F> pixels(width * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float value = 0.05F + (0.80F * static_cast<float>(x) / (width - 1U));
            // 가로로는 밝기가, 세로로는 색상이 바뀝니다. 밴드마다 쏠린 방향이 제각각이라
            // 한 방향으로 모이지 않습니다.
            const std::uint32_t hue = (y / 8U) % 6U;
            const float warm = hue < 3U ? 1.45F : 0.60F;
            const float cool = (hue % 3U) == 0U ? 0.55F : 1.40F;
            pixels[static_cast<std::size_t>(y) * width + x] = {
                value * warm,
                value * ((hue % 2U) == 0U ? 1.30F : 0.70F),
                value * cool,
                0.9F,
            };
        }
    }
    const auto before = pixels;
    negaflow::imaging::RescueGradeInfo info{};
    expect(
        negaflow::imaging::apply_rescue_grade(
            view(pixels, width, height), true, info) ==
            negaflow::core::KernelStatus::ok,
        "saturated scene RescueGrade succeeds");
    expect(!info.applied, "a genuinely coloured scene is left alone");
    for (std::size_t index = 0U; index < pixels.size(); ++index) {
        expect(
            pixels[index].red == before[index].red &&
                pixels[index].green == before[index].green &&
                pixels[index].blue == before[index].blue,
            "an untouched scene is exact identity");
    }
}

}  // namespace

int main() {
    try {
        test_healthy_neutral_is_identity();
        test_coherent_cast_is_reduced();
        test_strong_cast_is_reduced();
        test_saturated_scene_is_untouched();
        std::cout << "RescueGrade tests passed\n";
        return 0;
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        return 1;
    }
}
