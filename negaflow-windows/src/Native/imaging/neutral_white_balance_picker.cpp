#include "negaflow/imaging/neutral_white_balance_picker.h"

#include "negaflow/imaging/white_balance.h"

#include <algorithm>
#include <cmath>

namespace negaflow::imaging {
namespace {

// `neutral_axis_evidence.cpp` 의 중립 후보 조건과 같은 값입니다(macOS `NeutralAxisEstimator`).
constexpr double minimum_channel = 0.004;
constexpr double maximum_luminance = 0.90;

}  // namespace

std::optional<std::array<double, 3>> sample_neutral_white_balance_reference(
    const negaflow::core::ConstImageView image,
    const double unit_x,
    const double unit_y) noexcept {
    if (image.pixels == nullptr || image.width == 0U || image.height == 0U ||
        !std::isfinite(unit_x) || !std::isfinite(unit_y)) {
        return std::nullopt;
    }
    const double width = static_cast<double>(image.width);
    const double height = static_cast<double>(image.height);
    const double radius =
        std::max(2.0, std::round(neutral_pick_radius_fraction * std::max(width, height)));
    // macOS 는 y-up 사각형 (cx − r, cy − r, 2r + 1, 2r + 1) 을 바깥으로 정수화합니다. 같은 화소를
    // 고르도록 y-up 경계로 계산한 뒤 행 번호로 바꿉니다.
    const double cx = std::clamp(unit_x, 0.0, 1.0) * width;
    const double cy_up = height - (std::clamp(unit_y, 0.0, 1.0) * height);
    const double x0 = std::clamp(std::floor(cx - radius), 0.0, width);
    const double x1 = std::clamp(std::ceil(cx + radius + 1.0), 0.0, width);
    const double y_up0 = std::clamp(std::floor(cy_up - radius), 0.0, height);
    const double y_up1 = std::clamp(std::ceil(cy_up + radius + 1.0), 0.0, height);
    if (x1 - x0 < 1.0 || y_up1 - y_up0 < 1.0) {
        return std::nullopt;
    }
    const auto column_begin = static_cast<std::size_t>(x0);
    const auto column_end = static_cast<std::size_t>(x1);
    const auto row_begin = static_cast<std::size_t>(height - y_up1);
    const auto row_end = static_cast<std::size_t>(height - y_up0);
    if ((row_end - 1U) * image.stride_pixels + column_end > image.pixel_capacity) {
        return std::nullopt;
    }

    std::array<double, 3> sum{};
    for (std::size_t row = row_begin; row < row_end; ++row) {
        const negaflow::core::Rgba32F* const line = image.pixels + (row * image.stride_pixels);
        for (std::size_t column = column_begin; column < column_end; ++column) {
            sum[0] += static_cast<double>(line[column].red);
            sum[1] += static_cast<double>(line[column].green);
            sum[2] += static_cast<double>(line[column].blue);
        }
    }
    const double count =
        static_cast<double>((row_end - row_begin) * (column_end - column_begin));
    const std::array<double, 3> mean{sum[0] / count, sum[1] / count, sum[2] / count};
    if (!std::isfinite(mean[0]) || !std::isfinite(mean[1]) || !std::isfinite(mean[2]) ||
        mean[0] <= minimum_channel || mean[1] <= minimum_channel || mean[2] <= minimum_channel ||
        (0.2126 * mean[0]) + (0.7152 * mean[1]) + (0.0722 * mean[2]) >= maximum_luminance) {
        return std::nullopt;
    }
    return mean;
}

std::optional<NeutralWhiteBalanceSolution> solve_neutral_white_balance(
    const std::array<double, 3>& reference) noexcept {
    if (!(reference[0] > 0.0) || !(reference[1] > 0.0) || !(reference[2] > 0.0) ||
        !std::isfinite(reference[0]) || !std::isfinite(reference[1]) ||
        !std::isfinite(reference[2])) {
        return std::nullopt;
    }
    const double red_blue = std::log2(reference[2] / reference[0]);
    const double green = std::log2(std::sqrt(reference[0] * reference[2]) / reference[1]);
    const double warmth = solve_white_balance(red_blue, [](const double value) noexcept {
        return warmth_red_blue_stops(value);
    });
    const double tint = solve_white_balance(
        green - warmth_green_stops(warmth),
        [](const double value) noexcept { return tint_green_stops(value); });
    return NeutralWhiteBalanceSolution{warmth, tint};
}

}  // namespace negaflow::imaging
