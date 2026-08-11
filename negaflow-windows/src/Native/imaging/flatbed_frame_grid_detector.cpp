#include "negaflow/imaging/flatbed_frame_grid_detector.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <numeric>
#include <optional>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

constexpr double kGridEvidenceFloor = 0.15;

struct IntRange final {
    int first{0};
    int last{0};  // exclusive

    [[nodiscard]] int count() const noexcept { return last - first; }
};

struct DoubleRange final {
    double first{0.0};
    double last{0.0};
};

struct Geometry final {
    double along_mm{0.0};
    double across_mm{0.0};
    double gap_min_mm{0.0};
    double gap_max_mm{0.0};
    bool rigid_pitch{false};
    double pixels_per_mm_x{0.0};
    double pixels_per_mm_y{0.0};

    [[nodiscard]] double along_pixels_y() const noexcept {
        return along_mm * pixels_per_mm_y;
    }
    [[nodiscard]] double across_pixels_x() const noexcept {
        return across_mm * pixels_per_mm_x;
    }
    [[nodiscard]] double gap_min_pixels_y() const noexcept {
        return gap_min_mm * pixels_per_mm_y;
    }
    [[nodiscard]] double gap_max_pixels_y() const noexcept {
        return gap_max_mm * pixels_per_mm_y;
    }
    [[nodiscard]] DoubleRange pitch_pixels_y() const noexcept {
        const double slack = rigid_pitch ? 0.02 : 0.05;
        return {
            (along_mm * (1.0 - slack) + gap_min_mm) * pixels_per_mm_y,
            (along_mm * (1.0 + slack) + gap_max_mm) * pixels_per_mm_y,
        };
    }
};

struct ColumnProfiles final {
    std::vector<double> detail{};
    std::vector<double> mean{};
};

struct RowProfiles final {
    std::vector<double> mean{};
    std::vector<double> detail{};
    std::vector<double> grain{};
    std::vector<double> surround{};
};

struct Slot final {
    IntRange measured{};
    IntRange snapped{};
};

struct GapEvidence final {
    std::vector<double> plateau{};
    std::vector<double> edge{};
    std::vector<double> content{};
    std::vector<double> prefix{};
    std::vector<double> content_prefix{};

    [[nodiscard]] int count() const noexcept {
        return static_cast<int>(plateau.size());
    }

    [[nodiscard]] std::pair<double, double> content_sum(
        const double from,
        const double to) const noexcept {
        const int lower = std::max(0, static_cast<int>(std::lround(from)));
        const int upper = std::min(count(), static_cast<int>(std::lround(to)));
        if (upper <= lower) {
            return {0.0, 0.0};
        }
        return {content_prefix[static_cast<std::size_t>(upper)] -
                    content_prefix[static_cast<std::size_t>(lower)],
                static_cast<double>(upper - lower)};
    }

    [[nodiscard]] std::optional<double> score(
        const double center,
        const double half) const noexcept {
        const int lower = static_cast<int>(std::lround(center - half));
        const int upper = static_cast<int>(std::lround(center + half));
        if (lower < 0 || upper > count() || upper <= lower) {
            return std::nullopt;
        }
        const double flat = (prefix[static_cast<std::size_t>(upper)] -
                             prefix[static_cast<std::size_t>(lower)]) /
                            static_cast<double>(upper - lower);
        const double leading = edge[static_cast<std::size_t>(std::clamp(
            lower, 0, count() - 1))];
        const double trailing = edge[static_cast<std::size_t>(std::clamp(
            upper - 1, 0, count() - 1))];
        return 0.5 * flat + 0.5 * std::sqrt(std::max(0.0, leading * trailing));
    }
};

struct Grid final {
    std::vector<double> boundaries{};
    double confidence{0.0};
};

[[nodiscard]] double pixel_at(
    const FlatbedFramePreview& preview,
    const int x,
    const int y) noexcept {
    return static_cast<double>(preview.luminance[
        static_cast<std::size_t>(y) * preview.width + static_cast<std::size_t>(x)]);
}

[[nodiscard]] double quantile(std::vector<double> values, double fraction) {
    if (values.empty()) {
        return 0.0;
    }
    fraction = std::clamp(fraction, 0.0, 1.0);
    const std::size_t index = static_cast<std::size_t>(std::llround(
        static_cast<double>(values.size() - 1U) * fraction));
    std::nth_element(values.begin(), values.begin() + static_cast<std::ptrdiff_t>(index),
                     values.end());
    return values[index];
}

[[nodiscard]] double median(std::vector<double> values) {
    return quantile(std::move(values), 0.5);
}

[[nodiscard]] std::vector<double> robust_normalized(const std::vector<double>& values) {
    const double low = quantile(values, 0.02);
    const double high = quantile(values, 0.98);
    std::vector<double> result(values.size(), 0.0);
    if (!(high - low > 1.0e-9)) {
        return result;
    }
    for (std::size_t index = 0U; index < values.size(); ++index) {
        result[index] = std::clamp((values[index] - low) / (high - low), 0.0, 1.0);
    }
    return result;
}

[[nodiscard]] std::vector<double> moving_average(
    const std::vector<double>& values,
    const int radius) {
    std::vector<double> result(values.size(), 0.0);
    if (values.empty()) {
        return result;
    }
    const int clamped_radius = std::max(0, radius);
    std::vector<double> prefix(values.size() + 1U, 0.0);
    for (std::size_t index = 0U; index < values.size(); ++index) {
        prefix[index + 1U] = prefix[index] + values[index];
    }
    for (int index = 0; index < static_cast<int>(values.size()); ++index) {
        const int first = std::max(0, index - clamped_radius);
        const int last = std::min(static_cast<int>(values.size()), index + clamped_radius + 1);
        result[static_cast<std::size_t>(index)] =
            (prefix[static_cast<std::size_t>(last)] - prefix[static_cast<std::size_t>(first)]) /
            static_cast<double>(last - first);
    }
    return result;
}

[[nodiscard]] std::optional<double> split_threshold(const std::vector<double>& values) {
    if (values.empty()) {
        return std::nullopt;
    }
    const auto [minimum, maximum] = std::minmax_element(values.begin(), values.end());
    if (!(*maximum - *minimum > 1.0e-6)) {
        return std::nullopt;
    }
    constexpr int bin_count = 128;
    std::array<std::size_t, bin_count> histogram{};
    for (const double value : values) {
        const int bin = std::clamp(static_cast<int>(
            (value - *minimum) / (*maximum - *minimum) * static_cast<double>(bin_count - 1)),
            0, bin_count - 1);
        ++histogram[static_cast<std::size_t>(bin)];
    }
    const double total = static_cast<double>(values.size());
    double sum = 0.0;
    for (int bin = 0; bin < bin_count; ++bin) {
        sum += static_cast<double>(bin) * static_cast<double>(histogram[static_cast<std::size_t>(bin)]);
    }
    double lower_sum = 0.0;
    double lower_count = 0.0;
    double best_variance = -1.0;
    int best_bin = 0;
    for (int bin = 0; bin < bin_count; ++bin) {
        const double count = static_cast<double>(histogram[static_cast<std::size_t>(bin)]);
        lower_count += count;
        if (lower_count == 0.0) {
            continue;
        }
        const double upper_count = total - lower_count;
        if (upper_count == 0.0) {
            break;
        }
        lower_sum += static_cast<double>(bin) * count;
        const double lower_mean = lower_sum / lower_count;
        const double upper_mean = (sum - lower_sum) / upper_count;
        const double delta = lower_mean - upper_mean;
        const double variance = lower_count * upper_count * delta * delta;
        if (variance > best_variance) {
            best_variance = variance;
            best_bin = bin;
        }
    }
    return *minimum + (static_cast<double>(best_bin) + 0.5) /
        static_cast<double>(bin_count) * (*maximum - *minimum);
}

[[nodiscard]] std::vector<IntRange> included_runs(
    const std::vector<double>& values,
    const double threshold) {
    std::vector<IntRange> result{};
    int first = -1;
    for (int index = 0; index < static_cast<int>(values.size()); ++index) {
        if (values[static_cast<std::size_t>(index)] > threshold && first < 0) {
            first = index;
        }
        if (values[static_cast<std::size_t>(index)] <= threshold && first >= 0) {
            result.push_back({first, index});
            first = -1;
        }
    }
    if (first >= 0) {
        result.push_back({first, static_cast<int>(values.size())});
    }
    return result;
}

[[nodiscard]] std::vector<IntRange> bridge_ranges(
    const std::vector<IntRange>& ranges,
    const int maximum_gap) {
    if (ranges.empty() || maximum_gap <= 0) {
        return ranges;
    }
    std::vector<IntRange> result{};
    IntRange current = ranges.front();
    for (std::size_t index = 1U; index < ranges.size(); ++index) {
        const IntRange next = ranges[index];
        if (next.first - current.last <= maximum_gap) {
            current.last = next.last;
        } else {
            result.push_back(current);
            current = next;
        }
    }
    result.push_back(current);
    return result;
}

[[nodiscard]] std::optional<Geometry> make_geometry(
    const FlatbedFramePreview& preview,
    const FlatbedFrameFormat format) noexcept {
    Geometry geometry{};
    switch (format) {
        case FlatbedFrameFormat::full_frame_35mm: geometry.along_mm = 36.0; geometry.across_mm = 24.0; break;
        case FlatbedFrameFormat::square_35mm: geometry.along_mm = 24.0; geometry.across_mm = 24.0; break;
        case FlatbedFrameFormat::half_frame_35mm: geometry.along_mm = 18.0; geometry.across_mm = 24.0; break;
        case FlatbedFrameFormat::medium_645: geometry.along_mm = 41.5; geometry.across_mm = 56.0; break;
        case FlatbedFrameFormat::medium_66: geometry.along_mm = 56.0; geometry.across_mm = 56.0; break;
        case FlatbedFrameFormat::medium_67: geometry.along_mm = 69.0; geometry.across_mm = 55.0; break;
        case FlatbedFrameFormat::medium_68: geometry.along_mm = 76.0; geometry.across_mm = 56.0; break;
        case FlatbedFrameFormat::medium_69: geometry.along_mm = 84.0; geometry.across_mm = 56.0; break;
        case FlatbedFrameFormat::medium_612: geometry.along_mm = 112.0; geometry.across_mm = 56.0; break;
        case FlatbedFrameFormat::medium_617: geometry.along_mm = 168.0; geometry.across_mm = 56.0; break;
        default: return std::nullopt;
    }
    geometry.rigid_pitch = format <= FlatbedFrameFormat::half_frame_35mm;
    geometry.gap_min_mm = geometry.rigid_pitch ? 1.0 : 2.0;
    geometry.gap_max_mm = geometry.rigid_pitch ? 3.5 : 9.0;
    geometry.pixels_per_mm_x = static_cast<double>(preview.width) / preview.physical_width_mm;
    geometry.pixels_per_mm_y = static_cast<double>(preview.height) / preview.physical_height_mm;
    return geometry;
}

[[nodiscard]] ColumnProfiles column_profiles(const FlatbedFramePreview& preview) {
    ColumnProfiles profiles{};
    profiles.detail.assign(preview.width, 0.0);
    profiles.mean.assign(preview.width, 0.0);
    for (int y = 0; y < static_cast<int>(preview.height); ++y) {
        for (int x = 0; x < static_cast<int>(preview.width); ++x) {
            const double value = pixel_at(preview, x, y);
            profiles.mean[static_cast<std::size_t>(x)] += value;
            if (y + 1 < static_cast<int>(preview.height)) {
                profiles.detail[static_cast<std::size_t>(x)] +=
                    std::abs(pixel_at(preview, x, y + 1) - value);
            }
        }
    }
    const double rows = static_cast<double>(preview.height);
    const double steps = static_cast<double>(std::max(1U, preview.height - 1U));
    for (std::size_t index = 0U; index < profiles.mean.size(); ++index) {
        profiles.mean[index] /= rows;
        profiles.detail[index] /= steps;
    }
    return profiles;
}

[[nodiscard]] std::vector<double> side_means(
    const FlatbedFramePreview& preview,
    const IntRange slot,
    const std::vector<double>& fallback) {
    const int guard_width = std::max(2, slot.count() / 6);
    const int sample = std::max(3, slot.count() / 2);
    const IntRange left{slot.first - guard_width - sample, slot.first - guard_width};
    const IntRange right{slot.last + guard_width, slot.last + guard_width + sample};
    std::vector<IntRange> sides{};
    if (left.first >= 0 && left.last <= static_cast<int>(preview.width)) sides.push_back(left);
    if (right.first >= 0 && right.last <= static_cast<int>(preview.width)) sides.push_back(right);
    if (sides.empty()) {
        return fallback;
    }
    double best_texture = std::numeric_limits<double>::infinity();
    std::vector<double> result = fallback;
    for (const IntRange side : sides) {
        std::vector<double> means(preview.height, 0.0);
        double texture = 0.0;
        for (int y = 0; y < static_cast<int>(preview.height); ++y) {
            double sum = 0.0;
            double previous = pixel_at(preview, side.first, y);
            for (int x = side.first; x < side.last; ++x) {
                const double value = pixel_at(preview, x, y);
                sum += value;
                texture += std::abs(value - previous);
                previous = value;
            }
            means[static_cast<std::size_t>(y)] = sum / static_cast<double>(side.count());
        }
        texture /= static_cast<double>(preview.height * static_cast<std::uint32_t>(side.count()));
        if (texture < best_texture) {
            best_texture = texture;
            result = std::move(means);
        }
    }
    return result;
}

[[nodiscard]] RowProfiles row_profiles(
    const FlatbedFramePreview& preview,
    const IntRange slot) {
    const int inset = std::max(1, slot.count() / 10);
    const int first = slot.first + inset;
    const int last = std::max(first + 1, slot.last - inset);
    RowProfiles profiles{};
    profiles.mean.assign(preview.height, 0.0);
    profiles.detail.assign(preview.height, 0.0);
    profiles.grain.assign(preview.height, 0.0);
    for (int y = 0; y < static_cast<int>(preview.height); ++y) {
        double sum = 0.0;
        double horizontal = 0.0;
        double vertical = 0.0;
        double previous = pixel_at(preview, first, y);
        for (int x = first; x < last; ++x) {
            const double value = pixel_at(preview, x, y);
            sum += value;
            horizontal += std::abs(value - previous);
            previous = value;
            if (y + 1 < static_cast<int>(preview.height)) {
                vertical += std::abs(pixel_at(preview, x, y + 1) - value);
            }
        }
        profiles.mean[static_cast<std::size_t>(y)] = sum / static_cast<double>(last - first);
        profiles.detail[static_cast<std::size_t>(y)] = horizontal /
            static_cast<double>(std::max(1, last - first - 1));
        profiles.grain[static_cast<std::size_t>(y)] = vertical /
            static_cast<double>(last - first);
    }
    profiles.surround = side_means(preview, slot, profiles.mean);
    return profiles;
}

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
            const double score = (separation * 0.75 + std::exp(plateau_log / static_cast<double>(boundaries)) * 0.25) * coverage;
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
    const auto initial = fit_line(samples);
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
        result.boundaries.push_back(refit.first + spacing * static_cast<double>(index));
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

[[nodiscard]] bool valid_preview(const FlatbedFramePreview& preview) noexcept {
    if (preview.width <= 32U || preview.height <= 32U ||
        !std::isfinite(preview.physical_width_mm) || !std::isfinite(preview.physical_height_mm) ||
        preview.physical_width_mm <= 0.0 || preview.physical_height_mm <= 0.0 ||
        preview.luminance.size() != static_cast<std::size_t>(preview.width) * preview.height) {
        return false;
    }
    return std::all_of(preview.luminance.begin(), preview.luminance.end(), [](const float value) {
        return std::isfinite(value) && value >= 0.0F && value <= 1.0F;
    });
}

}  // namespace

FlatbedFrameGridResult detect_flatbed_frame_grid(
    const FlatbedFramePreview& preview,
    const FlatbedFrameFormat format,
    const negaflow::core::CancelFlag cancel) noexcept {
    FlatbedFrameGridResult result{};
    if (!valid_preview(preview)) {
        result.status = FlatbedFrameGridStatus::invalid_input;
        return result;
    }
    if (cancel.requested()) {
        result.status = FlatbedFrameGridStatus::cancelled;
        return result;
    }
    try {
        const auto geometry = make_geometry(preview, format);
        if (!geometry || geometry->along_pixels_y() < 8.0 || geometry->across_pixels_x() < 8.0) {
            result.status = FlatbedFrameGridStatus::invalid_input;
            return result;
        }
        const ColumnProfiles columns = column_profiles(preview);
        const std::vector<Slot> detected_slots = slots(preview, columns, *geometry);
        if (cancel.requested()) {
            result.status = FlatbedFrameGridStatus::cancelled;
            return result;
        }
        const double floor = noise_floor(columns, detected_slots);
        for (std::size_t row = 0U; row < detected_slots.size(); ++row) {
            const RowProfiles rows = row_profiles(preview, detected_slots[row].measured);
            const std::vector<IntRange> bands = film_bands(preview, rows, *geometry);
            std::uint32_t column = 0U;
            for (const IntRange band : bands) {
                if (cancel.requested()) {
                    result.detections.clear();
                    result.status = FlatbedFrameGridStatus::cancelled;
                    return result;
                }
                const auto grid = fit_grid(gap_evidence(rows, band, *geometry), *geometry, cancel);
                if (cancel.requested()) {
                    result.detections.clear();
                    result.status = FlatbedFrameGridStatus::cancelled;
                    return result;
                }
                if (!grid) continue;
                for (const DoubleRange span : occupied(frame_spans(*grid, band, *geometry), rows, floor, preview.height)) {
                    result.detections.push_back({
                        static_cast<double>(detected_slots[row].snapped.first) / preview.width,
                        span.first / preview.height,
                        static_cast<double>(detected_slots[row].snapped.count()) / preview.width,
                        (span.last - span.first) / preview.height,
                        grid->confidence,
                        static_cast<std::uint32_t>(row),
                        column++,
                    });
                }
            }
        }
        result.status = FlatbedFrameGridStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.detections.clear();
        result.status = FlatbedFrameGridStatus::allocation_failed;
        return result;
    } catch (...) {
        result.detections.clear();
        result.status = FlatbedFrameGridStatus::invalid_input;
        return result;
    }
}

const char* flatbed_frame_grid_status_name(const FlatbedFrameGridStatus status) noexcept {
    switch (status) {
        case FlatbedFrameGridStatus::ok: return "ok";
        case FlatbedFrameGridStatus::invalid_input: return "invalid_input";
        case FlatbedFrameGridStatus::cancelled: return "cancelled";
        case FlatbedFrameGridStatus::allocation_failed: return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
