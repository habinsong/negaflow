#include "flatbed_frame_grid_fit.h"

#include "flatbed_frame_bands.h"
#include "flatbed_frame_signal.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <limits>

namespace negaflow::imaging::flatbed_detail {

[[nodiscard]] std::optional<std::pair<double, double>> fit_line(
    const std::vector<std::pair<double, double>>& samples) noexcept {
    if (samples.size() < 2U) return std::nullopt;
    double mean_index = 0.0;
    double mean_position = 0.0;
    for (const auto& sample : samples) { mean_index += sample.first; mean_position += sample.second; }
    mean_index /= static_cast<double>(samples.size());
    mean_position /= static_cast<double>(samples.size());
    double numerator = 0.0;
    double denominator = 0.0;
    for (const auto& sample : samples) {
        const double delta = sample.first - mean_index;
        numerator += delta * (sample.second - mean_position);
        denominator += delta * delta;
    }
    if (!(denominator > 1.0e-9)) return std::nullopt;
    const double slope = numerator / denominator;
    return std::pair<double, double>{mean_position - slope * mean_index, slope};
}

// A single locally-refined boundary can be pulled into a frame by an unexposed
// image or holder mark.  Use the median pairwise slope before the least-squares
// inlier refit so that error stays local to that boundary.
[[nodiscard]] std::optional<std::pair<double, double>> robust_line(
    const std::vector<std::pair<double, double>>& samples) {
    if (samples.size() < 2U) return std::nullopt;
    std::vector<double> slopes{};
    slopes.reserve(samples.size() * (samples.size() - 1U) / 2U);
    for (std::size_t left = 0U; left < samples.size(); ++left) {
        for (std::size_t right = left + 1U; right < samples.size(); ++right) {
            const double delta = samples[right].first - samples[left].first;
            if (std::abs(delta) > 1.0e-9) {
                slopes.push_back((samples[right].second - samples[left].second) / delta);
            }
        }
    }
    if (slopes.empty()) return std::nullopt;
    const double slope = median(std::move(slopes));
    std::vector<double> intercepts{};
    intercepts.reserve(samples.size());
    for (const auto& sample : samples) intercepts.push_back(sample.second - slope * sample.first);
    return std::pair<double, double>{median(std::move(intercepts)), slope};
}

[[nodiscard]] double refined_center(
    const double center,
    const GapEvidence& evidence,
    const double radius,
    const double half) noexcept {
    double position = center;
    double best = -std::numeric_limits<double>::infinity();
    for (double offset = -radius; offset <= radius; offset += 0.5) {
        if (const auto score = evidence.score(center + offset, half); score && *score > best) {
            best = *score;
            position = center + offset;
        }
    }
    return position;
}

[[nodiscard]] std::optional<Grid> fit_grid(
    const GapEvidence& evidence,
    const Geometry& geometry,
    const negaflow::core::CancelFlag cancel) {
    if (evidence.count() <= 8) return std::nullopt;
    const double length = static_cast<double>(evidence.count());
    const DoubleRange range = geometry.pitch_pixels_y();
    if (!(range.last > range.first && range.first > 2.0)) return std::nullopt;
    const double pitch_step = std::max(0.05 * geometry.pixels_per_mm_y, 0.25);
    const double phase_step = std::max(0.35, geometry.gap_min_pixels_y() / 6.0);
    const double nominal_half = gap_half_width((range.first + range.last) * 0.5, geometry);
    std::vector<double> everywhere{};
    for (int row = 0; row < evidence.count(); ++row) {
        if (const auto score = evidence.score(static_cast<double>(row), nominal_half)) everywhere.push_back(*score);
    }
    if (everywhere.empty()) return std::nullopt;
    const double floor = std::max(quantile(std::move(everywhere), 0.10), 1.0e-4);
    struct Candidate final { double score; double pitch; double phase; double separation; };
    std::optional<Candidate> best{};
    std::size_t polls = 0U;
    for (double pitch = range.first; pitch <= range.last; pitch += pitch_step) {
        if ((++polls & 15U) == 0U && cancel.requested()) return std::nullopt;
        const double half = gap_half_width(pitch, geometry);
        const int frames = std::max(1, static_cast<int>(std::floor(
            (length - geometry.along_pixels_y()) / pitch)) + 1);
        const double coverage = std::min(1.0, geometry.along_pixels_y() * static_cast<double>(frames) / length);
        for (double phase = 0.0; phase < pitch; phase += phase_step) {
            double gap_sum = 0.0, gap_length = 0.0, frame_sum = 0.0, frame_length = 0.0, plateau_log = 0.0;
            int boundaries = 0;
            for (int index = 0;; ++index) {
                const double center = phase + pitch * static_cast<double>(index);
                if (center > length) break;
                const auto gap = evidence.content_sum(center - half, center + half);
                gap_sum += gap.first; gap_length += gap.second;
                plateau_log += std::log(std::max(evidence.score(center, half).value_or(floor), floor));
                ++boundaries;
                const auto interior = evidence.content_sum(center + half * 2.0, center + pitch - half * 2.0);
                frame_sum += interior.first; frame_length += interior.second;
            }
            if (boundaries < 2 || gap_length <= 0.0 || frame_length <= 0.0) continue;
            const double gap_mean = gap_sum / gap_length;
            const double frame_mean = frame_sum / frame_length;
            const double separation = (frame_mean - gap_mean) / (frame_mean + gap_mean + 1.0e-9);
            const double plateau = std::exp(plateau_log / static_cast<double>(boundaries));
            const double score = std::sqrt(std::max(0.0, separation) * std::max(0.0, plateau)) * coverage;
            if (!best || score > best->score) best = Candidate{score, pitch, phase, separation};
        }
    }
    if (cancel.requested() || !best || best->separation < kGridEvidenceFloor) return std::nullopt;
    const double half = gap_half_width(best->pitch, geometry);
    const double radius = std::max(1.0, half * 0.9);
    std::vector<std::pair<double, double>> samples{};
    for (int index = 0;; ++index) {
        const double center = best->phase + best->pitch * static_cast<double>(index);
        if (center - half > length) break;
        samples.emplace_back(static_cast<double>(index), refined_center(center, evidence, radius, half));
    }
    const auto initial = robust_line(samples);
    if (!initial) return std::nullopt;
    const double tolerance = std::max(half * 0.6, 1.0);
    std::vector<std::pair<double, double>> kept{};
    for (const auto& sample : samples) {
        if (std::abs(sample.second - (initial->first + initial->second * sample.first)) <= tolerance) kept.push_back(sample);
    }
    const auto refit = kept.size() >= std::max<std::size_t>(2U, samples.size() / 2U)
        ? fit_line(kept).value_or(*initial) : *initial;
    const double spacing = refit.second > 1.0 ? refit.second : best->pitch;
    Grid result{};
    result.confidence = std::min(1.0, 0.5 + best->separation * 0.5);
    result.boundaries.reserve(samples.size() + 2U);
    for (int index = -1; index <= static_cast<int>(samples.size()); ++index) {
        double position = refit.first + spacing * static_cast<double>(index);
        for (const auto& sample : kept) {
            if (static_cast<int>(sample.first) == index && sample.second >= 0.0 &&
                sample.second <= length &&
                std::abs(sample.second - position) <= tolerance) {
                position = sample.second;
                break;
            }
        }
        result.boundaries.push_back(position);
    }
    return result;
}

[[nodiscard]] std::vector<DoubleRange> frame_spans(
    const Grid& grid,
    const IntRange band,
    const Geometry& geometry) {
    std::vector<DoubleRange> result{};
    const double length = geometry.along_pixels_y();
    const double band_length = static_cast<double>(band.count());
    for (std::size_t index = 1U; index < grid.boundaries.size(); ++index) {
        const double center = (grid.boundaries[index - 1U] + grid.boundaries[index]) * 0.5;
        const double first = center - length * 0.5;
        const double last = center + length * 0.5;
        const double overlap = std::min(last, band_length) - std::max(first, 0.0);
        if (overlap >= length * 0.8) result.push_back({static_cast<double>(band.first) + first,
                                                       static_cast<double>(band.first) + last});
    }
    return result;
}

[[nodiscard]] std::vector<DoubleRange> occupied(
    const std::vector<DoubleRange>& spans,
    const RowProfiles& rows,
    const double noise,
    const std::uint32_t height) {
    if (spans.size() <= 1U || !(noise > 0.0)) return spans;
    std::vector<double> levels{};
    levels.reserve(spans.size());
    for (const DoubleRange span : spans) {
        const int first = std::max(0, static_cast<int>(std::lround(span.first)));
        const int last = std::min(static_cast<int>(height), static_cast<int>(std::lround(span.last)));
        std::vector<double> values{};
        for (int y = first; y < last; ++y) values.push_back(rows.grain[static_cast<std::size_t>(y)]);
        levels.push_back(values.empty() ? 0.0 : median(std::move(values)));
    }
    const double threshold = noise * 2.0;
    std::size_t first = 0U;
    std::size_t last = spans.size();
    while (first < last && levels[first] < threshold) ++first;
    while (last > first && levels[last - 1U] < threshold) --last;
    return {spans.begin() + static_cast<std::ptrdiff_t>(first),
            spans.begin() + static_cast<std::ptrdiff_t>(last)};
}

}  // namespace negaflow::imaging::flatbed_detail
