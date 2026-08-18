#include "infrared_alignment.h"

#include "infrared_alignment_math.h"
#include "infrared_defect_alignment.h"

#include "grain_mend_morphology.h"

#include <algorithm>
#include <cmath>
#include <cstddef>

namespace negaflow::imaging::infrared_detail {

InfraredAlignmentDiagnostics estimate_alignment(
    const std::span<const float> infrared,
    const std::span<const float> red,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t search_radius) {
    InfraredAlignmentDiagnostics result{};
    result.search_radius = search_radius;
    if (search_radius == 0U) {
        result.status = InfraredAlignmentStatus::not_requested;
        return result;
    }
    if (const auto defect = estimate_defect_alignment(
            infrared, red, width, height, search_radius)) {
        result.status = defect->at_search_limit
            ? InfraredAlignmentStatus::search_limit_reached
            : InfraredAlignmentStatus::aligned;
        result.offset_x = defect->offset_x;
        result.offset_y = defect->offset_y;
        result.peak_correlation = defect->peak;
        result.runner_up_correlation = defect->runner_up;
        return result;
    }
    const std::uint32_t factor = std::max(1U, std::min(width, height) / 384U);
    result.downsample_factor = factor;
    auto infrared_down = block_mean(infrared, width, height, factor);
    auto red_down = block_mean(red, width, height, factor);
    if (infrared_down.width <= 24U || infrared_down.height <= 24U) {
        result.status = InfraredAlignmentStatus::insufficient_texture;
        return result;
    }
    auto ir_low = grain_mend_detail::box_mean(
        infrared_down.pixels, infrared_down.width, infrared_down.height, 4U);
    auto red_low = grain_mend_detail::box_mean(
        red_down.pixels, red_down.width, red_down.height, 4U);
    double ir_square_sum = 0.0;
    for (std::size_t index = 0U; index < infrared_down.pixels.size(); ++index) {
        infrared_down.pixels[index] -= ir_low[index];
        red_down.pixels[index] -= red_low[index];
        ir_square_sum += static_cast<double>(infrared_down.pixels[index]) *
            infrared_down.pixels[index];
    }
    const double ir_rms = std::sqrt(ir_square_sum /
        static_cast<double>(infrared_down.pixels.size()));
    if (ir_rms <= 0.003) {
        result.status = InfraredAlignmentStatus::insufficient_texture;
        return result;
    }
    const std::int32_t radius = static_cast<std::int32_t>(std::max(
        1U,
        std::min(search_radius / factor,
                 std::min(infrared_down.width, infrared_down.height) / 4U)));
    std::int32_t best_x = 0;
    std::int32_t best_y = 0;
    double best = -1.0;
    double runner_up = -1.0;
    for (std::int32_t y = -radius; y <= radius; ++y) {
        for (std::int32_t x = -radius; x <= radius; ++x) {
            const double score = correlation(
                infrared_down.pixels, red_down.pixels,
                infrared_down.width, infrared_down.height, x, y, 1U);
            if (score > best) {
                runner_up = best;
                best = score;
                best_x = x;
                best_y = y;
            } else if (score > runner_up) {
                runner_up = score;
            }
        }
    }
    if (best <= 0.2) {
        result.status = InfraredAlignmentStatus::weak_correlation;
        result.peak_correlation = best;
        result.runner_up_correlation = runner_up;
        return result;
    }
    std::int32_t fine_x = best_x * static_cast<std::int32_t>(factor);
    std::int32_t fine_y = best_y * static_cast<std::int32_t>(factor);
    double fine_best = -1.0;
    double fine_runner_up = -1.0;
    const auto search = static_cast<std::int32_t>(search_radius);
    const std::int32_t minimum_y =
        std::max(-search, fine_y - static_cast<std::int32_t>(factor));
    const std::int32_t maximum_y =
        std::min(search, fine_y + static_cast<std::int32_t>(factor));
    const std::int32_t minimum_x =
        std::max(-search, fine_x - static_cast<std::int32_t>(factor));
    const std::int32_t maximum_x =
        std::min(search, fine_x + static_cast<std::int32_t>(factor));
    for (std::int32_t y = minimum_y; y <= maximum_y; ++y) {
        for (std::int32_t x = minimum_x; x <= maximum_x; ++x) {
            const double score = correlation(
                infrared, red, width, height, x, y, std::max(2U, factor));
            if (score > fine_best) {
                fine_runner_up = fine_best;
                fine_best = score;
                fine_x = x;
                fine_y = y;
            } else if (score > fine_runner_up) {
                fine_runner_up = score;
            }
        }
    }
    result.offset_x = fine_x;
    result.offset_y = fine_y;
    result.peak_correlation = fine_best;
    result.runner_up_correlation = fine_runner_up;
    result.status = std::abs(fine_x) == search || std::abs(fine_y) == search
        ? InfraredAlignmentStatus::search_limit_reached
        : InfraredAlignmentStatus::aligned;
    return result;
}

}  // namespace negaflow::imaging::infrared_detail
