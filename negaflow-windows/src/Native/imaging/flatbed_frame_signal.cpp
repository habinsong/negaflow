#include "flatbed_frame_signal.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <numeric>

namespace negaflow::imaging::flatbed_detail {

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

}  // namespace negaflow::imaging::flatbed_detail
