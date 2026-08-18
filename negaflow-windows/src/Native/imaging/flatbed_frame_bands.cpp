#include "flatbed_frame_bands.h"

#include "flatbed_frame_profiles.h"
#include "flatbed_frame_signal.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <optional>

namespace negaflow::imaging::flatbed_detail {

[[nodiscard]] std::vector<Slot> slots(
    const FlatbedFramePreview& preview,
    const ColumnProfiles& profiles,
    const Geometry& geometry) {
    const std::optional<double> threshold = split_threshold(profiles.detail);
    if (!threshold) {
        return {};
    }
    const double expected = geometry.across_pixels_x();
    const double background = quantile(profiles.detail, 0.1);
    auto cores_above = [&](const double level) {
        std::vector<IntRange> result = included_runs(profiles.detail, level);
        result.erase(std::remove_if(result.begin(), result.end(), [&](const IntRange range) {
            return static_cast<double>(range.count()) < expected * 0.4;
        }), result.end());
        return result;
    };
    std::vector<IntRange> cores = cores_above(*threshold);
    if (cores.empty()) {
        cores = cores_above(std::max(background * 2.5, *threshold * 0.3));
    }
    if (cores.empty()) {
        return {};
    }
    std::vector<IntRange> grown{};
    for (const IntRange core : cores) {
        double total = 0.0;
        for (int x = core.first; x < core.last; ++x) total += profiles.detail[static_cast<std::size_t>(x)];
        const double core_level = total / static_cast<double>(core.count());
        const double floor = std::max(background * 2.0, core_level * 0.15);
        const int limit = static_cast<int>(std::lround(expected * 1.45));
        IntRange range = core;
        while (range.first > 0 && range.count() < limit &&
               profiles.detail[static_cast<std::size_t>(range.first - 1)] >= floor) --range.first;
        while (range.last < static_cast<int>(preview.width) && range.count() < limit &&
               profiles.detail[static_cast<std::size_t>(range.last)] >= floor) ++range.last;
        if (!grown.empty() && range.first <= grown.back().last) {
            grown.back().last = std::max(grown.back().last, range.last);
        } else {
            grown.push_back(range);
        }
    }
    std::vector<Slot> result{};
    for (const IntRange measured : grown) {
        if (measured.first <= 0 || measured.last >= static_cast<int>(preview.width)) continue;
        const double width = static_cast<double>(measured.count());
        if (width < expected * 0.7 || width > expected * 1.45) continue;
        const double center = static_cast<double>(measured.first + measured.last) * 0.5;
        int first = static_cast<int>(std::lround(center - expected * 0.5));
        int last = first + static_cast<int>(std::lround(expected));
        if (first < 0) { last -= first; first = 0; }
        if (last > static_cast<int>(preview.width)) { first -= last - static_cast<int>(preview.width); last = static_cast<int>(preview.width); }
        if (first >= 0 && last > first) result.push_back({measured, {first, last}});
    }
    return result;
}

[[nodiscard]] double noise_floor(
    const ColumnProfiles& profiles,
    const std::vector<Slot>& slots) {
    std::vector<double> outside{};
    outside.reserve(profiles.detail.size());
    for (int x = 0; x < static_cast<int>(profiles.detail.size()); ++x) {
        bool in_slot = false;
        for (const Slot& slot : slots) {
            if (x >= slot.measured.first && x < slot.measured.last) { in_slot = true; break; }
        }
        if (!in_slot) outside.push_back(profiles.detail[static_cast<std::size_t>(x)]);
    }
    return outside.empty() ? 0.0 : quantile(std::move(outside), 0.25);
}

[[nodiscard]] IntRange trim_band(
    IntRange band,
    const RowProfiles& rows,
    const Geometry& geometry) {
    std::vector<double> inside{};
    inside.reserve(static_cast<std::size_t>(band.count()));
    for (int y = band.first; y < band.last; ++y) inside.push_back(rows.detail[static_cast<std::size_t>(y)]);
    const double floor = median(std::move(inside)) * 0.25;
    if (!(floor > 0.0)) return band;
    const int limit = static_cast<int>(geometry.along_pixels_y());
    int first = band.first;
    int last = band.last;
    while (first < last && first - band.first < limit && rows.detail[static_cast<std::size_t>(first)] < floor) ++first;
    while (last > first && band.last - last < limit && rows.detail[static_cast<std::size_t>(last - 1)] < floor) --last;
    return {first, last};
}

[[nodiscard]] std::vector<IntRange> film_bands(
    const FlatbedFramePreview& preview,
    const RowProfiles& rows,
    const Geometry& geometry) {
    std::vector<double> difference(preview.height, 0.0);
    for (std::size_t y = 0U; y < difference.size(); ++y) {
        difference[y] = std::abs(rows.mean[y] - rows.surround[y]);
    }
    const double brightness_scale = std::max(quantile(difference, 0.9), 1.0e-4);
    const double detail_scale = std::max(quantile(rows.detail, 0.9), 1.0e-5);
    std::vector<double> filmness(preview.height, 0.0);
    for (std::size_t y = 0U; y < filmness.size(); ++y) {
        filmness[y] = std::max(difference[y] / brightness_scale, rows.detail[y] / detail_scale);
    }
    const int maximum_gap = static_cast<int>(geometry.along_pixels_y() * 1.3);
    const int minimum_rows = static_cast<int>(geometry.along_pixels_y() * 0.55);
    std::vector<IntRange> result{};
    for (IntRange band : bridge_ranges(included_runs(filmness, 0.07), maximum_gap)) {
        if (band.count() < std::max(4, minimum_rows)) continue;
        band = trim_band(band, rows, geometry);
        if (band.count() >= std::max(4, minimum_rows)) result.push_back(band);
    }
    return result;
}

[[nodiscard]] GapEvidence gap_evidence(
    const RowProfiles& rows,
    const IntRange band,
    const Geometry& geometry) {
    const int count = band.count();
    GapEvidence evidence{};
    evidence.plateau.assign(static_cast<std::size_t>(std::max(0, count)), 0.0);
    evidence.edge.assign(evidence.plateau.size(), 0.0);
    evidence.content.assign(evidence.plateau.size(), 0.0);
    if (count > 8) {
        std::vector<double> mean(static_cast<std::size_t>(count));
        for (int y = 0; y < count; ++y) mean[static_cast<std::size_t>(y)] = rows.mean[static_cast<std::size_t>(band.first + y)];
        std::vector<double> prefix(static_cast<std::size_t>(count + 1), 0.0);
        for (int index = 0; index < count; ++index) prefix[static_cast<std::size_t>(index + 1)] = prefix[static_cast<std::size_t>(index)] + mean[static_cast<std::size_t>(index)];
        const int half = std::max(1, static_cast<int>(std::lround(geometry.gap_min_pixels_y() * 0.6)));
        const int offset = half + std::max(2, static_cast<int>(geometry.along_pixels_y() * 0.12));
        auto window_mean = [&](const int center) -> std::optional<double> {
            const int first = center - half;
            const int last = center + half + 1;
            if (first < 0 || last > count) return std::nullopt;
            return (prefix[static_cast<std::size_t>(last)] - prefix[static_cast<std::size_t>(first)]) /
                static_cast<double>(last - first);
        };
        std::vector<double> bright(static_cast<std::size_t>(count), 0.0);
        std::vector<double> dark(static_cast<std::size_t>(count), 0.0);
        for (int y = 0; y < count; ++y) {
            const auto center = window_mean(y);
            if (!center) continue;
            const auto left = window_mean(y - offset);
            const auto right = window_mean(y + offset);
            if (!left && !right) continue;
            const double sides = left && right ? (*left + *right) * 0.5 : (left ? *left : *right);
            bright[static_cast<std::size_t>(y)] = *center - sides;
            dark[static_cast<std::size_t>(y)] = sides - *center;
        }
        std::vector<double> raw_detail(static_cast<std::size_t>(count));
        for (int y = 0; y < count; ++y) raw_detail[static_cast<std::size_t>(y)] = rows.detail[static_cast<std::size_t>(band.first + y)];
        const std::vector<double> normalized_detail = robust_normalized(raw_detail);
        const std::vector<double> normalized_bright = robust_normalized(bright);
        const std::vector<double> normalized_dark = robust_normalized(dark);
        auto peakedness = [](const std::vector<double>& values) { return quantile(values, 0.95) - quantile(values, 0.5); };
        std::vector<double> chosen(static_cast<std::size_t>(count), 0.0);
        const bool use_bright = peakedness(normalized_bright) >= peakedness(normalized_dark);
        for (int y = 0; y < count; ++y) {
            const double uniform = 1.0 - normalized_detail[static_cast<std::size_t>(y)];
            chosen[static_cast<std::size_t>(y)] = (use_bright ? normalized_bright[static_cast<std::size_t>(y)] : normalized_dark[static_cast<std::size_t>(y)]) * uniform;
        }
        const int smoothing = std::max(1, static_cast<int>(geometry.gap_min_pixels_y() / 8.0));
        const int step = std::max(1, static_cast<int>(std::lround(geometry.gap_min_pixels_y() * 0.25)));
        for (int y = step; y < count - step; ++y) {
            evidence.edge[static_cast<std::size_t>(y)] = std::abs(mean[static_cast<std::size_t>(y + step)] - mean[static_cast<std::size_t>(y - step)]);
        }
        evidence.plateau = moving_average(chosen, smoothing);
        evidence.edge = robust_normalized(moving_average(evidence.edge, smoothing));
        evidence.content = moving_average(raw_detail, smoothing);
    }
    evidence.prefix.assign(evidence.plateau.size() + 1U, 0.0);
    evidence.content_prefix.assign(evidence.content.size() + 1U, 0.0);
    for (std::size_t index = 0U; index < evidence.plateau.size(); ++index) {
        evidence.prefix[index + 1U] = evidence.prefix[index] + evidence.plateau[index];
        evidence.content_prefix[index + 1U] = evidence.content_prefix[index] + evidence.content[index];
    }
    return evidence;
}

[[nodiscard]] double gap_half_width(const double pitch, const Geometry& geometry) noexcept {
    const double width = std::min(std::max(pitch - geometry.along_pixels_y(),
                                           geometry.gap_min_pixels_y()),
                                  geometry.gap_max_pixels_y());
    return std::max(1.0, width * 0.5);
}

}  // namespace negaflow::imaging::flatbed_detail
