#include "texture_stage_test_support.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <functional>
#include <numbers>
#include <string>
#include <vector>

// 선명도·부분 대비 계약입니다. macOS `DetailEnhancementTests` 와 같은 픽스처·문턱입니다.
namespace texture_stage_tests {
namespace {

[[nodiscard]] double encode(const double v) {
    return v <= 0.0031308 ? v * 12.92 : 1.055 * std::pow(v, 1.0 / 2.4) - 0.055;
}

[[nodiscard]] double decode(const double v) {
    return v <= 0.04045 ? v / 12.92 : std::pow((v + 0.055) / 1.055, 2.4);
}

[[nodiscard]] negaflow::imaging::WorkingImage strip(
    const std::uint32_t width,
    const std::uint32_t height,
    const std::function<std::array<double, 3>(std::uint32_t)>& linear_at) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const auto c = linear_at(x);
            image.pixels[static_cast<std::size_t>(y) * width + x] = {
                static_cast<float>(c[0]), static_cast<float>(c[1]), static_cast<float>(c[2]), 1.0F};
        }
    }
    return image;
}

[[nodiscard]] std::array<double, 3> grey(const double gamma) {
    const double v = decode(gamma);
    return {v, v, v};
}

[[nodiscard]] std::vector<double> gamma_row(const negaflow::imaging::WorkingImage& image) {
    std::vector<double> row(image.width);
    const std::uint32_t y = image.height / 2U;
    for (std::uint32_t x = 0U; x < image.width; ++x) {
        const auto& p = image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x];
        row[x] = encode(0.2126 * p.red + 0.7152 * p.green + 0.0722 * p.blue);
    }
    return row;
}

[[nodiscard]] negaflow::imaging::WorkingImage applied(
    const negaflow::imaging::WorkingImage& image, const float sharpness, const float clarity) {
    negaflow::imaging::TextureStageParameters parameters{};
    parameters.sharpness = sharpness;
    parameters.clarity = clarity;
    return negaflow::imaging::apply_texture_stage(image, parameters).image;
}

// 같은 사진의 원본과 반 크기 프록시에서 선명도 헤일로가 사진 대비 같은 폭입니다.
void test_sharpen_halo_scales_with_image() {
    const auto halo_fraction = [](const std::uint32_t width) {
        const auto image = strip(width, 16U, [width](const std::uint32_t x) {
            return grey(x < width / 2U ? 0.30 : 0.70);
        });
        const auto row = gamma_row(applied(image, 1.0F, 0.0F));
        const double peak = *std::max_element(row.begin() + width / 2U, row.end()) - 0.70;
        const auto wide = std::count_if(row.begin() + width / 2U, row.end(), [peak](const double v) {
            return v - 0.70 > 0.1 * peak;
        });
        return static_cast<double>(wide) / width;
    };
    const double full = halo_fraction(6000U);
    const double proxy = halo_fraction(3000U);
    expect(full > 0.0 && std::abs(proxy / full - 1.0) <= 0.35,
           "sharpen halo scales with the image, not with pixels");
}

// 문턱 아래 미세 진폭은 키우지 않고 경계만 날카롭게 합니다.
void test_sharpen_leaves_sub_threshold_noise() {
    constexpr std::uint32_t width = 6000U;
    const auto image = strip(width, 16U, [](const std::uint32_t x) {
        if (x >= width / 2U) {
            return grey(x < width * 3U / 4U ? 0.35 : 0.65);
        }
        return grey(0.45 + (x % 2U == 0U ? 0.0015 : -0.0015));
    });
    const auto before = gamma_row(image);
    const auto after = gamma_row(applied(image, 1.0F, 0.0F));
    const auto ripple = [](const std::vector<double>& row) {
        double sum = 0.0;
        for (std::size_t x = 100U; x < 1000U; ++x) {
            sum += std::abs(row[x] - row[x + 1U]);
        }
        return sum / 900.0;
    };
    expect(ripple(after) / ripple(before) < 1.25, "sharpen does not amplify the noise floor");
    const double overshoot =
        *std::max_element(after.begin() + width * 3U / 4U, after.begin() + width * 3U / 4U + 20U) - 0.65;
    expect(overshoot > 0.02, "sharpen still sharpens edges");
}

// 휘도에만 겁니다 — 유채색 경계에서 화소의 색 비율이 그대로입니다.
void test_detail_preserves_channel_ratios() {
    constexpr std::uint32_t width = 3000U;
    constexpr std::array<double, 3> colour{0.62, 0.30, 0.12};
    const auto image = strip(width, 16U, [&colour](const std::uint32_t x) {
        const double scale = (x < width / 2U ? 0.25 : 1.0) * (1.0 + 0.1 * std::sin(static_cast<double>(x) / 9.0));
        return std::array<double, 3>{colour[0] * scale, colour[1] * scale, colour[2] * scale};
    });
    for (const auto& output : {applied(image, 1.0F, 0.0F), applied(image, 0.0F, 1.0F), applied(image, 0.0F, -1.0F)}) {
        bool ok = true;
        for (std::uint32_t x = 10U; x < width - 10U; x += 37U) {
            const auto& p = output.pixels[static_cast<std::size_t>(8U) * width + x];
            ok = ok && std::abs(p.red / p.green - colour[0] / colour[1]) <= 2.0e-3 &&
                std::abs(p.green / p.blue - colour[1] / colour[2]) <= 4.0e-3;
        }
        expect(ok, "sharpness and clarity keep channel ratios");
    }
}

// 부분 대비 − 는 미드톤 질감을 줄이되 큰 경계는 한 화소 안에서 그대로 끊깁니다.
void test_negative_clarity_flattens_texture_but_keeps_edges() {
    constexpr std::uint32_t width = 3000U;
    const auto image = strip(width, 16U, [](const std::uint32_t x) {
        return x < width / 2U
            ? grey(0.45 + 0.04 * std::sin(static_cast<double>(x) * 2.0 * std::numbers::pi / 40.0))
            : grey(0.85);
    });
    const auto before = gamma_row(image);
    const auto after = gamma_row(applied(image, 0.0F, -1.0F));
    const auto amplitude = [](const std::vector<double>& row) {
        const auto [low, high] = std::minmax_element(row.begin() + 400, row.begin() + 1200);
        return (*high - *low) / 2.0;
    };
    expect(amplitude(after) < 0.6 * amplitude(before), "negative clarity flattens midtone texture");
    const auto jump = [](const std::vector<double>& row) {
        double best = 0.0;
        for (std::uint32_t x = width / 2U - 3U; x < width / 2U + 3U; ++x) {
            best = std::max(best, std::abs(row[x + 1U] - row[x]));
        }
        return best;
    };
    expect(jump(after) > 0.9 * jump(before), "negative clarity keeps large edges crisp");
}

// 부분 대비 + 는 미드톤 질감을 키우고 깊은 암부는 훨씬 덜 건드립니다.
void test_positive_clarity_favours_midtones() {
    constexpr std::uint32_t width = 3000U;
    const auto boost = [](const double level) {
        const auto image = strip(width, 16U, [level](const std::uint32_t x) {
            return grey(level + 0.02 * std::sin(static_cast<double>(x) * 2.0 * std::numbers::pi / 40.0));
        });
        const auto before = gamma_row(image);
        const auto after = gamma_row(applied(image, 0.0F, 1.0F));
        const auto [b_low, b_high] = std::minmax_element(before.begin() + 800, before.begin() + 2200);
        const auto [a_low, a_high] = std::minmax_element(after.begin() + 800, after.begin() + 2200);
        return (*a_high - *a_low) / (*b_high - *b_low);
    };
    const double mid = boost(0.50);
    const double shadow = boost(0.06);
    expect(mid > 1.4, "positive clarity boosts midtone texture");
    expect(shadow - 1.0 < (mid - 1.0) / 2.0, "positive clarity spares deep shadows");
}

// SP 타겟의 기본 부분 대비(`target_clarity`)는 사용자 슬라이더와 별개로 약하게 걸린다
// (macOS `testSPTargetAddsBaselineLocalContrastInTextureStage` 와 같은 문턱).
void test_target_clarity_adds_mild_baseline_local_contrast() {
    constexpr std::uint32_t width = 3000U;
    const auto image = strip(width, 16U, [](const std::uint32_t x) {
        return grey(0.50 + 0.02 * std::sin(static_cast<double>(x) * 2.0 * std::numbers::pi / 40.0));
    });
    negaflow::imaging::TextureStageParameters parameters{};
    parameters.target_clarity = negaflow::imaging::sp_target_local_contrast;
    const auto result = negaflow::imaging::apply_texture_stage(image, parameters);
    expect(result.status == negaflow::imaging::TextureStageStatus::ok, "target clarity is valid");
    const auto before = gamma_row(image);
    const auto after = gamma_row(result.image);
    const auto [b_low, b_high] = std::minmax_element(before.begin() + 800, before.begin() + 2200);
    const auto [a_low, a_high] = std::minmax_element(after.begin() + 800, after.begin() + 2200);
    const double ratio = (*a_high - *a_low) / (*b_high - *b_low);
    expect(ratio > 1.08, "SP baseline local contrast is applied");
    expect(ratio < 1.35, "SP baseline local contrast stays mild");
}

}  // namespace

void test_detail_enhancement() {
    test_sharpen_halo_scales_with_image();
    test_sharpen_leaves_sub_threshold_noise();
    test_detail_preserves_channel_ratios();
    test_negative_clarity_flattens_texture_but_keeps_edges();
    test_positive_clarity_favours_midtones();
    test_target_clarity_adds_mild_baseline_local_contrast();
}

}  // namespace texture_stage_tests
