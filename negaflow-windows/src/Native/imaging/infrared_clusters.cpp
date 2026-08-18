#include "infrared_clusters.h"

#include <algorithm>
#include <cmath>
#include <utility>

namespace negaflow::imaging::infrared_detail {

InfraredDetectedComponent summarize_component(
    const RawComponent& component,
    const std::span<const std::size_t> correction_pixels,
    const std::span<const float> attenuation,
    const std::uint32_t width) {
    double sum_x = 0.0;
    double sum_y = 0.0;
    double attenuation_sum = 0.0;
    for (const std::size_t pixel : component.pixels) {
        sum_x += static_cast<double>(pixel % width);
        sum_y += static_cast<double>(pixel / width);
        attenuation_sum += attenuation[pixel];
    }
    const double count = static_cast<double>(component.pixels.size());
    const double mean_x = sum_x / count;
    const double mean_y = sum_y / count;
    double covariance_xx = 0.0;
    double covariance_yy = 0.0;
    double covariance_xy = 0.0;
    for (const std::size_t pixel : component.pixels) {
        const double dx = static_cast<double>(pixel % width) - mean_x;
        const double dy = static_cast<double>(pixel / width) - mean_y;
        covariance_xx += dx * dx;
        covariance_yy += dy * dy;
        covariance_xy += dx * dy;
    }
    covariance_xx /= count;
    covariance_yy /= count;
    covariance_xy /= count;
    const double trace = covariance_xx + covariance_yy;
    const double determinant = covariance_xx * covariance_yy - covariance_xy * covariance_xy;
    const double discriminant = std::max(0.0, trace * trace / 4.0 - determinant);
    const double first_eigenvalue = trace / 2.0 + std::sqrt(discriminant);
    const double second_eigenvalue = std::max(1.0e-6, trace / 2.0 - std::sqrt(discriminant));
    const double elongation = std::sqrt(first_eigenvalue / second_eigenvalue);
    const std::uint32_t span = std::max(
        component.max_x - component.min_x,
        component.max_y - component.min_y) + 1U;

    InfraredDetectedComponent summary{};
    if (elongation >= 3.5 && span >= 16U) {
        const double angle = std::abs(0.5 * std::atan2(
            2.0 * covariance_xy, covariance_xx - covariance_yy) * 180.0 / tuning::kPi);
        if (angle <= 30.0) summary.classification = InfraredDefectClass::scratch_horizontal;
        else if (angle >= 60.0) summary.classification = InfraredDefectClass::scratch_vertical;
        else summary.classification = InfraredDefectClass::scratch_diagonal;
    }
    summary.confidence = std::clamp(
        attenuation_sum / count / static_cast<double>(tuning::kCoreCut), 0.3, 0.98);
    summary.area = component.pixels.size();
    constexpr std::size_t kMaximumPreviewPoints = 240U;
    const std::size_t step = std::max<std::size_t>(
        1U, correction_pixels.size() / kMaximumPreviewPoints);
    for (std::size_t ordinal = 0U; ordinal < correction_pixels.size(); ordinal += step) {
        const std::size_t pixel = correction_pixels[ordinal];
        summary.preview_points.push_back({
            static_cast<std::uint32_t>(pixel % width),
            static_cast<std::uint32_t>(pixel / width)});
    }
    return summary;
}

std::vector<InfraredCorrectionCluster> render_clusters(
    const std::span<const float> attenuation,
    const std::vector<std::size_t>& core_pixels,
    const float threshold,
    const std::uint32_t width,
    const std::uint32_t height,
    const InfraredDetectorParameters& parameters) {
    const std::uint32_t tile = static_cast<std::uint32_t>(parameters.cluster_tile);
    const std::uint32_t padding = static_cast<std::uint32_t>(parameters.cluster_padding);
    const std::uint32_t columns = std::max(1U, (width + tile - 1U) / tile);
    const std::uint32_t rows = std::max(1U, (height + tile - 1U) / tile);
    std::vector<std::uint8_t> touched(static_cast<std::size_t>(columns) * rows, 0U);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            if (attenuation[static_cast<std::size_t>(y) * width + x] >= threshold) {
                touched[static_cast<std::size_t>(y / tile) * columns + x / tile] = 1U;
            }
        }
    }
    std::vector<InfraredCorrectionCluster> clusters{};
    for (std::uint32_t key = 0U; key < touched.size(); ++key) {
        if (touched[key] == 0U) continue;
        const std::uint32_t column = key % columns;
        const std::uint32_t row = key / columns;
        const std::uint32_t x0 = column * tile > padding ? column * tile - padding : 0U;
        const std::uint32_t y0 = row * tile > padding ? row * tile - padding : 0U;
        const std::uint32_t x1 = std::min(width, (column + 1U) * tile + padding);
        const std::uint32_t y1 = std::min(height, (row + 1U) * tile + padding);
        InfraredCorrectionCluster cluster{};
        cluster.roi_x = x0;
        cluster.roi_y_up = height - y1;
        cluster.width = x1 - x0;
        cluster.height = y1 - y0;
        const std::size_t cluster_area = static_cast<std::size_t>(cluster.width) * cluster.height;
        cluster.core_mask.assign(cluster_area * 4U, 0U);
        cluster.attenuation_r16.assign(cluster_area, 0U);
        for (std::uint32_t y = y0; y < y1; ++y) {
            for (std::uint32_t x = x0; x < x1; ++x) {
                const std::size_t source = static_cast<std::size_t>(y) * width + x;
                const std::size_t target = static_cast<std::size_t>(y - y0) * cluster.width + x - x0;
                cluster.attenuation_r16[target] = static_cast<std::uint16_t>(std::lround(
                    std::clamp(attenuation[source], 0.0F, 1.0F) * 65535.0F));
            }
        }
        const auto dilate = static_cast<std::uint32_t>(parameters.dilate_radius);
        for (const std::size_t pixel : core_pixels) {
            const std::uint32_t px = static_cast<std::uint32_t>(pixel % width);
            const std::uint32_t py = static_cast<std::uint32_t>(pixel / width);
            const std::uint32_t sx0 = px > dilate ? px - dilate : 0U;
            const std::uint32_t sy0 = py > dilate ? py - dilate : 0U;
            const std::uint32_t sx1 = std::min(width - 1U, px + dilate);
            const std::uint32_t sy1 = std::min(height - 1U, py + dilate);
            for (std::uint32_t y = std::max(y0, sy0); y <= std::min(y1 - 1U, sy1); ++y) {
                for (std::uint32_t x = std::max(x0, sx0); x <= std::min(x1 - 1U, sx1); ++x) {
                    const std::size_t local = static_cast<std::size_t>(y - y0) * cluster.width + x - x0;
                    std::fill_n(
                        cluster.core_mask.begin() + static_cast<std::ptrdiff_t>(local * 4U),
                        4U,
                        static_cast<std::uint8_t>(255U));
                }
            }
        }
        clusters.push_back(std::move(cluster));
    }
    return clusters;
}

}  // namespace negaflow::imaging::infrared_detail
