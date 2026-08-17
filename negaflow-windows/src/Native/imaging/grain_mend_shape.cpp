#include "grain_mend_shape.h"

#include <algorithm>
#include <cmath>
#include <numbers>

namespace negaflow::imaging::grain_mend_detail {
namespace {

// 좌표 종류가 달라도 셈은 하나입니다 — macOS 도 DefectShape 하나로 씁니다.
template <typename Index, typename Width>
[[nodiscard]] PcaMetrics measure(
    const std::vector<Index>& pixels,
    const Width width) noexcept {
    if (pixels.empty() || width <= Width{0}) {
        return {};
    }
    const double count = static_cast<double>(pixels.size());
    double mean_x = 0.0;
    double mean_y = 0.0;
    for (const Index pixel : pixels) {
        mean_x += static_cast<double>(pixel % static_cast<Index>(width));
        mean_y += static_cast<double>(pixel / static_cast<Index>(width));
    }
    mean_x /= count;
    mean_y /= count;

    double covariance_xx = 0.0;
    double covariance_yy = 0.0;
    double covariance_xy = 0.0;
    for (const Index pixel : pixels) {
        const double dx =
            static_cast<double>(pixel % static_cast<Index>(width)) - mean_x;
        const double dy =
            static_cast<double>(pixel / static_cast<Index>(width)) - mean_y;
        covariance_xx += dx * dx;
        covariance_yy += dy * dy;
        covariance_xy += dx * dy;
    }
    covariance_xx /= count;
    covariance_yy /= count;
    covariance_xy /= count;

    const double half_trace = (covariance_xx + covariance_yy) * 0.5;
    const double determinant =
        covariance_xx * covariance_yy - covariance_xy * covariance_xy;
    const double discriminant =
        std::sqrt(std::max(0.0, half_trace * half_trace - determinant));
    const double length = std::max(
        1.0,
        std::floor(std::sqrt(12.0 * (half_trace + discriminant))) + 1.0);
    const double thickness = std::max(1.0, count / length);

    double angle = 0.5 *
        std::atan2(2.0 * covariance_xy, covariance_xx - covariance_yy) *
        180.0 / std::numbers::pi;
    if (angle < 0.0) {
        angle += 180.0;
    }
    if (angle >= 180.0) {
        angle -= 180.0;
    }
    return {length, thickness, length / thickness, angle};
}

}  // namespace

PcaMetrics pca_metrics(
    const std::vector<std::size_t>& pixels,
    const std::uint32_t width) noexcept {
    return measure(pixels, static_cast<std::size_t>(width));
}

PcaMetrics pca_metrics(const std::vector<int>& pixels, const int width) noexcept {
    return measure(pixels, width);
}

}  // namespace negaflow::imaging::grain_mend_detail
