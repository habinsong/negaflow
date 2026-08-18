#include "negaflow/imaging/infrared_defect_detector.h"

#include "infrared_alignment.h"
#include "infrared_baseline.h"
#include "infrared_clusters.h"
#include "infrared_components.h"
#include "infrared_confirmation.h"
#include "infrared_detection_types.h"
#include "infrared_planes.h"

#include "grain_mend_morphology.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <numeric>
#include <utility>

namespace negaflow::imaging {
namespace {

using namespace negaflow::imaging::infrared_detail;

[[nodiscard]] bool checked_area(
    const std::uint32_t width,
    const std::uint32_t height,
    std::size_t& area) noexcept {
    if (width == 0U || height == 0U ||
        width > std::numeric_limits<std::size_t>::max() / height) {
        return false;
    }
    area = static_cast<std::size_t>(width) * height;
    return true;
}

}  // namespace

InfraredDetectorParameters sanitize_infrared_detector_parameters(
    const InfraredDetectorParameters& parameters,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    const auto maximum = static_cast<std::int32_t>(
        std::min<std::uint32_t>(std::max(width, height),
                                static_cast<std::uint32_t>(std::numeric_limits<std::int32_t>::max())));
    InfraredDetectorParameters result{};
    result.sensitivity = std::isfinite(parameters.sensitivity)
        ? std::clamp(parameters.sensitivity, 0.0, 1.0) : 0.5;
    result.dilate_radius = std::clamp(parameters.dilate_radius, 0, maximum);
    result.minimum_area = std::max(parameters.minimum_area, 1);
    result.maximum_coverage = std::isfinite(parameters.maximum_coverage)
        ? std::clamp(parameters.maximum_coverage, 0.0, 1.0) : 0.05;
    result.alignment_search_radius = std::clamp(parameters.alignment_search_radius, 0, maximum);
    result.cluster_tile = std::clamp(parameters.cluster_tile, 1, std::max(maximum, 1));
    result.cluster_padding = std::clamp(parameters.cluster_padding, 0, maximum);
    return result;
}

InfraredDetectionResult detect_infrared_defects(
    const std::span<const float> infrared,
    const std::span<const float> red,
    const std::uint32_t width,
    const std::uint32_t height,
    const InfraredDetectorParameters& raw_parameters,
    const negaflow::core::CancelFlag cancel) noexcept {
    InfraredDetectionResult result{};
    try {
        std::size_t area = 0U;
        if (!checked_area(width, height, area) || infrared.size() != area || red.size() != area ||
            !std::all_of(infrared.begin(), infrared.end(), [](float value) { return std::isfinite(value); }) ||
            !std::all_of(red.begin(), red.end(), [](float value) { return std::isfinite(value); })) {
            result.status = InfraredDetectionStatus::unreadable;
            return result;
        }
        if (width < 64U || height < 64U) {
            result.status = InfraredDetectionStatus::too_small;
            return result;
        }
        if (cancel.requested()) {
            result.status = InfraredDetectionStatus::cancelled;
            return result;
        }
        const InfraredDetectorParameters parameters =
            sanitize_infrared_detector_parameters(raw_parameters, width, height);
        result.detection.width = width;
        result.detection.height = height;
        std::vector<std::uint8_t> excluded(area, 0U);
        result.detection.alignment = estimate_alignment(
            infrared, red, width, height,
            static_cast<std::uint32_t>(parameters.alignment_search_radius));
        const bool seed_trusted =
            result.detection.alignment.status == InfraredAlignmentStatus::not_requested ||
            result.detection.alignment.status == InfraredAlignmentStatus::aligned;
        const std::int32_t seed_x = seed_trusted ? result.detection.alignment.offset_x : 0;
        const std::int32_t seed_y = seed_trusted ? result.detection.alignment.offset_y : 0;
        result.detection.offset_x = seed_x;
        result.detection.offset_y = seed_y;
        auto aligned_infrared = shift_plane(
            infrared, width, height, seed_x, seed_y, excluded);
        const float p95 = percentile(aligned_infrared, excluded, 0.95);
        if (!(p95 > 1.0e-4F)) {
            result.status = InfraredDetectionStatus::unreadable;
            return result;
        }
        const std::uint32_t rim = std::max(4U, std::min(24U, std::min(width, height) / 200U));
        exclude_border_dark(aligned_infrared, width, height, p95 * 0.2F, rim, excluded);
        if (cancel.requested()) {
            result.status = InfraredDetectionStatus::cancelled;
            return result;
        }

        const std::uint32_t radius = std::max(4U, std::min(96U, std::min(width, height) / 100U));
        auto ir_baseline = grain_mend_detail::closing(aligned_infrared, width, height, radius);
        auto density = optical_density(aligned_infrared, ir_baseline);
        ir_baseline.clear();
        const SignalStatistics statistics = signal_statistics(density, excluded, parameters.sensitivity);
        const float excess = statistics.threshold - statistics.floor;
        std::vector<std::uint8_t> candidate_mask(area, 0U);
        for (std::size_t index = 0U; index < area; ++index) {
            if (excluded[index] == 0U && density[index] >= statistics.floor + 0.5F * excess) {
                candidate_mask[index] = 1U;
            }
        }
        auto candidates = label_components(
            candidate_mask, width, height, static_cast<std::size_t>(parameters.minimum_area));
        candidates.erase(
            std::remove_if(candidates.begin(), candidates.end(), [&](const RawComponent& component) {
                double sum = 0.0;
                for (const std::size_t pixel : component.pixels) {
                    sum += static_cast<double>(density[pixel] - statistics.floor);
                }
                return sum < static_cast<double>(excess) *
                    std::sqrt(static_cast<double>(component.pixels.size()));
            }),
            candidates.end());
        result.detection.candidate_count = candidates.size();
        if (candidates.empty()) {
            result.status = InfraredDetectionStatus::no_defects;
            return result;
        }

        const std::vector<float> red_copy(red.begin(), red.end());
        auto visible_baseline = grain_mend_detail::closing(red_copy, width, height, radius);
        auto visible = optical_density(red, visible_baseline);
        visible_baseline.clear();
        const float visible_floor = signal_statistics(visible, excluded, parameters.sensitivity).floor;
        for (float& value : visible) value -= visible_floor;

        std::vector<ConfirmedCandidate> confirmed{};
        std::int32_t consensus_x = 0;
        std::int32_t consensus_y = 0;
        const std::int32_t coarse_search =
            std::max(4, std::min(20, parameters.alignment_search_radius));
        if (!seed_trusted && coarse_search > 4) {
            std::vector<std::size_t> order(candidates.size(), 0U);
            std::iota(order.begin(), order.end(), 0U);
            std::sort(order.begin(), order.end(), [&](const std::size_t a, const std::size_t b) {
                return candidates[a].source_area > candidates[b].source_area;
            });
            std::vector<std::int32_t> votes_x{};
            std::vector<std::int32_t> votes_y{};
            const std::size_t vote_count = std::min<std::size_t>(64U, order.size());
            votes_x.reserve(vote_count);
            votes_y.reserve(vote_count);
            for (std::size_t ordinal = 0U; ordinal < vote_count; ++ordinal) {
                RawComponent candidate = fill_component_holes(candidates[order[ordinal]], width);
                const auto extent = static_cast<std::int32_t>(
                    std::min(candidate.max_x - candidate.min_x,
                             candidate.max_y - candidate.min_y) / 2U + 1U);
                ConfirmedDefect vote{};
                if (confirm_component(candidate, density, visible, width, height,
                                      statistics.floor, coarse_search + extent, 0, 0, vote)) {
                    votes_x.push_back(vote.offset_x);
                    votes_y.push_back(vote.offset_y);
                }
            }
            if (votes_x.size() >= 8U) {
                std::sort(votes_x.begin(), votes_x.end());
                std::sort(votes_y.begin(), votes_y.end());
                consensus_x = votes_x[votes_x.size() / 2U];
                consensus_y = votes_y[votes_y.size() / 2U];
            }
            if (cancel.requested()) {
                result.status = InfraredDetectionStatus::cancelled;
                return result;
            }
        }
        result.detection.offset_x = seed_x + consensus_x;
        result.detection.offset_y = seed_y + consensus_y;
        const std::int32_t residual = std::max(4, std::min(8, parameters.alignment_search_radius));
        for (RawComponent& component : candidates) {
            if (cancel.requested()) {
                result.status = InfraredDetectionStatus::cancelled;
                return result;
            }
            RawComponent filled = fill_component_holes(component, width);
            const auto extent = static_cast<std::int32_t>(
                std::min(component.max_x - component.min_x,
                         component.max_y - component.min_y) / 2U + 1U);
            ConfirmedDefect match{};
            if (confirm_component(filled, density, visible, width, height,
                                  statistics.floor, std::min<int>(radius + residual, residual + extent + 3),
                                  consensus_x, consensus_y, match)) {
                confirmed.push_back(ConfirmedCandidate{
                    std::move(component), std::move(filled.pixels), match});
            }
        }
        result.detection.confirmed_count = confirmed.size();
        if (confirmed.empty()) {
            result.status = InfraredDetectionStatus::no_defects;
            return result;
        }

        std::vector<float> gains{};
        gains.reserve(confirmed.size());
        for (const auto& item : confirmed) gains.push_back(item.match.gain);
        std::sort(gains.begin(), gains.end());
        const float median_gain = gains[gains.size() / 2U];
        std::vector<float> deviations(gains.size(), 0.0F);
        std::transform(gains.begin(), gains.end(), deviations.begin(),
                       [median_gain](float gain) { return std::abs(gain - median_gain); });
        std::sort(deviations.begin(), deviations.end());
        const float gain_ceiling = median_gain + 2.0F * deviations[deviations.size() / 2U];
        result.detection.median_gain = median_gain;

        std::vector<float> attenuation(area, 0.0F);
        std::vector<std::size_t> core_pixels{};
        std::vector<std::uint8_t> visited(area, 0U);
        std::vector<std::size_t> frontier{};
        std::vector<std::size_t> reached{};
        for (const ConfirmedCandidate& candidate : confirmed) {
            const RawComponent& component = candidate.component;
            const ConfirmedDefect& match = candidate.match;
            const float gain = std::min(match.gain, gain_ceiling);
            const std::uint32_t x0 = component.min_x > radius ? component.min_x - radius : 0U;
            const std::uint32_t y0 = component.min_y > radius ? component.min_y - radius : 0U;
            const std::uint32_t x1 = std::min(width - 1U, component.max_x + radius);
            const std::uint32_t y1 = std::min(height - 1U, component.max_y + radius);
            frontier = candidate.correction_pixels;
            reached = candidate.correction_pixels;
            for (const std::size_t pixel : candidate.correction_pixels) visited[pixel] = 1U;
            while (!frontier.empty()) {
                const std::size_t pixel = frontier.back();
                frontier.pop_back();
                const std::uint32_t x = static_cast<std::uint32_t>(pixel % width);
                const std::uint32_t y = static_cast<std::uint32_t>(pixel / width);
                const auto visit = [&](const std::uint32_t next_x, const std::uint32_t next_y) {
                    if (next_x < x0 || next_x > x1 || next_y < y0 || next_y > y1) return;
                    const std::size_t next = static_cast<std::size_t>(next_y) * width + next_x;
                    if (visited[next] == 0U && density[next] > statistics.skirt_floor()) {
                        visited[next] = 1U;
                        frontier.push_back(next);
                        reached.push_back(next);
                    }
                };
                if (x > x0) visit(x - 1U, y);
                if (x < x1) visit(x + 1U, y);
                if (y > y0) visit(x, y - 1U);
                if (y < y1) visit(x, y + 1U);
            }
            for (const std::size_t pixel : reached) {
                visited[pixel] = 0U;
                const float value = density[pixel] - statistics.floor;
                if (!(value > 0.0F)) continue;
                const auto target_x = static_cast<std::int32_t>(pixel % width) + match.offset_x;
                const auto target_y = static_cast<std::int32_t>(pixel / width) + match.offset_y;
                if (target_x < 0 || target_y < 0 || target_x >= static_cast<std::int32_t>(width) ||
                    target_y >= static_cast<std::int32_t>(height)) continue;
                const float occlusion = std::min(0.98F, 1.0F - std::exp(-gain * value));
                const std::size_t target = static_cast<std::size_t>(target_y) * width +
                    static_cast<std::uint32_t>(target_x);
                attenuation[target] = std::max(attenuation[target], occlusion);
            }
        }
        const float significant_cut = std::max(
            1.0F - std::exp(-3.0F * statistics.sigma), 0.002F);
        std::size_t significant = 0U;
        for (std::size_t index = 0U; index < attenuation.size(); ++index) {
            if (attenuation[index] >= significant_cut) ++significant;
            if (attenuation[index] >= tuning::kCoreCut) core_pixels.push_back(index);
        }
        const std::size_t excluded_count = std::accumulate(
            excluded.begin(), excluded.end(), std::size_t{0U});
        const std::size_t valid_area = std::max<std::size_t>(1U, area - excluded_count);
        result.detection.coverage = static_cast<double>(significant) /
            static_cast<double>(valid_area);
        if (result.detection.coverage > parameters.maximum_coverage) {
            result.status = InfraredDetectionStatus::coverage_too_high;
            return result;
        }
        result.detection.components.reserve(confirmed.size());
        for (const ConfirmedCandidate& candidate : confirmed) {
            result.detection.components.push_back(summarize_component(
                candidate.component,
                candidate.correction_pixels,
                attenuation,
                width));
        }
        result.detection.clusters = render_clusters(
            attenuation, core_pixels, significant_cut, width, height, parameters);
        if (result.detection.clusters.empty()) {
            result.status = InfraredDetectionStatus::no_defects;
            return result;
        }
        result.status = InfraredDetectionStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = InfraredDetectionStatus::allocation_failed;
        return result;
    } catch (...) {
        result.status = InfraredDetectionStatus::unreadable;
        return result;
    }
}

const char* infrared_detection_status_name(const InfraredDetectionStatus status) noexcept {
    switch (status) {
        case InfraredDetectionStatus::ok: return "ok";
        case InfraredDetectionStatus::unreadable: return "unreadable";
        case InfraredDetectionStatus::too_small: return "too_small";
        case InfraredDetectionStatus::no_defects: return "no_defects";
        case InfraredDetectionStatus::coverage_too_high: return "coverage_too_high";
        case InfraredDetectionStatus::cancelled: return "cancelled";
        case InfraredDetectionStatus::allocation_failed: return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
